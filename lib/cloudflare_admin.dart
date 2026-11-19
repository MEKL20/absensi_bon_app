import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class CloudflareAdminException implements Exception {
  const CloudflareAdminException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class CloudflareSession {
  const CloudflareSession({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
  });
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  bool get expired => DateTime.now().isAfter(expiresAt);
}

class ProvisionedWorkspace {
  const ProvisionedWorkspace({
    required this.origin,
    required this.accountId,
    required this.databaseId,
    required this.bucketName,
    required this.workerName,
  });
  final String origin;
  final String accountId;
  final String databaseId;
  final String bucketName;
  final String workerName;
}

class CloudflareMigration {
  const CloudflareMigration({required this.tag, required this.sql});
  final String tag;
  final String sql;
  factory CloudflareMigration.fromJson(Map<String, dynamic> json) =>
      CloudflareMigration(
        tag: json['tag'] as String,
        sql: json['sql'] as String,
      );
}

class CloudflareAdmin {
  CloudflareAdmin({
    required this.clientId,
    required this.redirectUri,
    http.Client? client,
    String apiBase = 'https://api.cloudflare.com/client/v4',
    String authBase = 'https://dash.cloudflare.com',
  }) : _client = client ?? http.Client(),
       _apiBase = apiBase,
       _authBase = authBase;

  static const requiredScopeLabels = [
    'D1 Write',
    'Workers R2 Storage Write',
    'Workers Scripts Write',
    'Account Settings Read',
  ];
  final String clientId;
  final String redirectUri;
  final http.Client _client;
  final String _apiBase;
  final String _authBase;

  String newPkceVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(48, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String challengeFor(String verifier) => base64UrlEncode(
    sha256.convert(utf8.encode(verifier)).bytes,
  ).replaceAll('=', '');

  Uri authorizeUrl({
    required String state,
    required String codeChallenge,
    required List<String> scopeIds,
  }) => Uri.parse('$_authBase/oauth2/auth').replace(
    queryParameters: {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'state': state,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'scope': scopeIds.join(' '),
    },
  );

  Future<CloudflareSession> exchangeCode({
    required String code,
    required String codeVerifier,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_authBase/oauth2/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'grant_type': 'authorization_code',
            'code': code,
            'client_id': clientId,
            'redirect_uri': redirectUri,
            'code_verifier': codeVerifier,
          },
        )
        .timeout(const Duration(seconds: 30));
    Map<String, dynamic> json;
    try {
      final dynamic value = jsonDecode(response.body);
      if (value is! Map<String, dynamic>) throw const FormatException();
      json = value;
    } on FormatException {
      throw const CloudflareAdminException(
        'oauth_invalid',
        'Respons token Cloudflare tidak dapat dibaca.',
      );
    }
    final token = json['access_token'];
    final expires = json['expires_in'];
    if (response.statusCode != 200 || token is! String || expires is! num) {
      final description = json['error_description'] ?? json['error'];
      throw CloudflareAdminException(
        'oauth_invalid',
        description is String && description.isNotEmpty
            ? description
            : 'Login Cloudflare ditolak atau kedaluwarsa.',
      );
    }
    return CloudflareSession(
      accessToken: token,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: DateTime.now().add(Duration(seconds: expires.toInt())),
    );
  }

  Future<List<String>> resolveScopeIds(
    CloudflareSession session,
    List<String> labels,
  ) async {
    final json = await _get(session, '/oauth/scopes');
    final results = json['result'];
    if (results is! List) {
      throw const CloudflareAdminException(
        'oauth_scopes',
        'Daftar scope Cloudflare tidak dapat dibaca.',
      );
    }
    final byLabel = <String, String>{};
    for (final row in results) {
      if (row is! Map) continue;
      final name = row['name'] ?? row['scope'];
      final id = row['id'] ?? row['scope'];
      if (name is String && id is String) byLabel[name.toLowerCase()] = id;
    }
    final missing = <String>[];
    final ids = <String>[];
    for (final label in labels) {
      final id = byLabel[label.toLowerCase()];
      if (id == null) {
        missing.add(label);
      } else {
        ids.add(id);
      }
    }
    if (missing.isNotEmpty) {
      throw CloudflareAdminException(
        'oauth_scopes',
        'Scope Cloudflare tidak tersedia: ${missing.join(', ')}. Perbarui registrasi OAuth client.',
      );
    }
    return ids;
  }

  Future<ProvisionedWorkspace> provision({
    required CloudflareSession session,
    required String workerName,
    required String databaseName,
    required String bucketName,
    required Uint8List workerBundle,
    required List<CloudflareMigration> migrations,
    required Map<String, String> vars,
    required List<String> crons,
    required String compatibilityDate,
    required String setupDigest,
    void Function(String step)? onProgress,
  }) async {
    void step(String value) => onProgress?.call(value);
    step('Membaca akun Cloudflare');
    final accounts = await _get(session, '/accounts?per_page=5');
    final accountList = accounts['result'];
    if (accountList is! List ||
        accountList.isEmpty ||
        accountList.first is! Map) {
      throw const CloudflareAdminException(
        'account',
        'Tidak ada akun Cloudflare yang dapat diakses token ini.',
      );
    }
    final accountId = (accountList.first as Map)['id'] as String;

    step('Menyiapkan database D1');
    final databaseId = await _ensureD1(session, accountId, databaseName);

    step('Menyiapkan bucket R2 privat');
    await _ensureBucket(session, accountId, bucketName);

    step('Menerapkan migrasi skema');
    await _applyMigrations(session, accountId, databaseId, migrations);

    step('Mengunggah Worker');
    await _uploadWorker(
      session,
      accountId,
      workerName,
      workerBundle,
      databaseId,
      bucketName,
      vars,
      crons,
      compatibilityDate,
      migrations.isEmpty ? null : migrations.last.tag,
    );

    step('Menyimpan secret setup');
    await _putSecret(
      session,
      accountId,
      workerName,
      'OWNER_SETUP_TOKEN_SHA256',
      setupDigest,
    );

    step('Mengaktifkan alamat workers.dev');
    final origin = await _enableWorkersDev(session, accountId, workerName);
    step('Selesai');
    return ProvisionedWorkspace(
      origin: origin,
      accountId: accountId,
      databaseId: databaseId,
      bucketName: bucketName,
      workerName: workerName,
    );
  }

  Future<String> _ensureD1(
    CloudflareSession session,
    String accountId,
    String name,
  ) async {
    final list = await _get(
      session,
      '/accounts/$accountId/d1/database?name=${Uri.encodeComponent(name)}',
    );
    final results = list['result'];
    if (results is List) {
      for (final row in results) {
        if (row is Map && row['name'] == name && row['uuid'] is String) {
          return row['uuid'] as String;
        }
      }
    }
    final created = await _send(
      session,
      'POST',
      '/accounts/$accountId/d1/database',
      body: {'name': name},
    );
    final result = created['result'];
    final id = result is Map ? result['uuid'] : null;
    if (id is! String) {
      throw const CloudflareAdminException(
        'd1',
        'Database D1 tidak dapat dibuat.',
      );
    }
    return id;
  }

  Future<void> _ensureBucket(
    CloudflareSession session,
    String accountId,
    String name,
  ) async {
    final list = await _get(session, '/accounts/$accountId/r2/buckets');
    final results = list['result'];
    if (results is List) {
      for (final row in results) {
        if (row is Map && row['name'] == name) return;
      }
    } else if (results is Map && results['name'] == name) {
      return;
    }
    try {
      await _send(
        session,
        'POST',
        '/accounts/$accountId/r2/buckets',
        body: {'name': name},
      );
    } on CloudflareAdminException catch (error) {
      if (error.code == 'r2_billing') rethrow;
      if (!error.message.toLowerCase().contains('exists')) rethrow;
    }
  }

  Future<void> _applyMigrations(
    CloudflareSession session,
    String accountId,
    String databaseId,
    List<CloudflareMigration> migrations,
  ) async {
    if (migrations.isEmpty) {
      throw const CloudflareAdminException(
        'migrations',
        'Aset migrasi tidak tersedia.',
      );
    }
    final check = await _send(
      session,
      'POST',
      '/accounts/$accountId/d1/database/$databaseId/query',
      body: [
        {
          'sql':
              "SELECT name FROM sqlite_master WHERE type='table' AND name='workspace_setup'",
          'params': const [],
        },
      ],
    );
    if (_queryRows(check).isNotEmpty) {
      return; // Schema already applied by an earlier provisioning attempt.
    }
    final batch = migrations
        .map((m) => {'sql': m.sql, 'params': const []})
        .toList();
    await _send(
      session,
      'POST',
      '/accounts/$accountId/d1/database/$databaseId/query',
      body: batch,
    );
  }

  List<dynamic> _queryRows(Map<String, dynamic> response) {
    final result = response['result'];
    if (result is List && result.isNotEmpty && result.first is Map) {
      final results = (result.first as Map)['results'];
      if (results is List) return results;
    }
    if (result is Map) {
      final results = result['results'];
      if (results is List) return results;
    }
    return const [];
  }

  Future<void> _uploadWorker(
    CloudflareSession session,
    String accountId,
    String name,
    Uint8List bundle,
    String databaseId,
    String bucketName,
    Map<String, String> vars,
    List<String> crons,
    String compatibilityDate,
    String? migrationTag,
  ) async {
    final metadata = {
      'main_module': 'worker.js',
      'compatibility_date': compatibilityDate,
      'bindings': [
        {'type': 'd1', 'name': 'DB', 'id': databaseId},
        {'type': 'r2_bucket', 'name': 'PHOTOS', 'bucket_name': bucketName},
        ...vars.entries.map(
          (entry) => {
            'type': 'plain_text',
            'name': entry.key,
            'text': entry.value,
          },
        ),
      ],
      if (crons.isNotEmpty) 'triggers': {'crons': crons},
      if (migrationTag != null) 'migrations': {'new_tag': migrationTag},
    };
    final request =
        http.MultipartRequest(
            'PUT',
            Uri.parse(
              '$_apiBase/accounts/$accountId/workers/scripts/${Uri.encodeComponent(name)}',
            ),
          )
          ..headers['Authorization'] = 'Bearer ${session.accessToken}'
          ..files.add(
            http.MultipartFile.fromString(
              'metadata',
              jsonEncode(metadata),
              contentType: MediaType('application', 'json'),
            ),
          )
          ..files.add(
            http.MultipartFile.fromBytes(
              'worker.js',
              bundle,
              contentType: MediaType('application', 'javascript+module'),
            ),
          );
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 120));
    _decode(response);
  }

  Future<void> _putSecret(
    CloudflareSession session,
    String accountId,
    String script,
    String name,
    String text,
  ) async {
    await _send(
      session,
      'PUT',
      '/accounts/$accountId/workers/scripts/${Uri.encodeComponent(script)}/secrets',
      body: {'name': name, 'text': text, 'type': 'secret_text'},
    );
  }

  Future<String> _enableWorkersDev(
    CloudflareSession session,
    String accountId,
    String script,
  ) async {
    String? subdomain;
    try {
      final current = await _get(
        session,
        '/accounts/$accountId/workers/subdomain',
      );
      final result = current['result'];
      if (result is Map && result['subdomain'] is String) {
        subdomain = result['subdomain'] as String;
      }
    } on CloudflareAdminException catch (error) {
      if (error.code != 'not_found') rethrow;
    }
    if (subdomain == null) {
      final created = await _send(
        session,
        'PUT',
        '/accounts/$accountId/workers/subdomain',
        body: {'enabled': true},
      );
      final result = created['result'];
      subdomain = result is Map ? result['subdomain'] as String? : null;
    }
    if (subdomain == null) {
      throw const CloudflareAdminException(
        'subdomain',
        'Subdomain workers.dev belum aktif. Aktifkan di dashboard Cloudflare lalu ulangi setup.',
      );
    }
    await _send(
      session,
      'POST',
      '/accounts/$accountId/workers/scripts/${Uri.encodeComponent(script)}/subdomain',
      body: {'enabled': true},
    );
    return 'https://$script.$subdomain.workers.dev';
  }

  Future<Map<String, dynamic>> _get(CloudflareSession session, String path) =>
      _send(session, 'GET', path);

  Future<Map<String, dynamic>> _send(
    CloudflareSession session,
    String method,
    String path, {
    Object? body,
  }) async {
    final request = http.Request(method, Uri.parse('$_apiBase$path'))
      ..headers['Authorization'] = 'Bearer ${session.accessToken}';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 60));
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> decoded;
    try {
      final dynamic value = jsonDecode(response.body);
      if (value is! Map<String, dynamic>) throw const FormatException();
      decoded = value;
    } on FormatException {
      throw CloudflareAdminException(
        'invalid_response',
        'Respons Cloudflare tidak dapat dibaca (status ${response.statusCode}).',
      );
    }
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        decoded['success'] == true) {
      return decoded;
    }
    final errors = decoded['errors'];
    var code = 'cloudflare';
    var message =
        'Permintaan Cloudflare ditolak (status ${response.statusCode}).';
    if (errors is List && errors.isNotEmpty && errors.first is Map) {
      final first = errors.first as Map;
      final rawCode = first['code'];
      final rawMessage = first['message'];
      if (rawMessage is String && rawMessage.isNotEmpty) message = rawMessage;
      if (rawCode != null) code = rawCode.toString();
      final combined = '$code $message'.toLowerCase();
      if (combined.contains('subscription') ||
          combined.contains('payment') ||
          combined.contains('billing') ||
          code == '10038') {
        throw const CloudflareAdminException(
          'r2_billing',
          'R2 memerlukan aktivasi langganan/payment method di akun Cloudflare Anda. Selesaikan di dashboard, lalu ulangi setup.',
        );
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw CloudflareAdminException(
          'forbidden',
          'Token Cloudflare tidak memiliki izin untuk langkah ini: $message',
        );
      }
      if (response.statusCode == 404) code = 'not_found';
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      code = 'forbidden';
      message = 'Sesi Cloudflare ditolak atau kedaluwarsa. Masuk ulang.';
    } else if (response.statusCode == 404) {
      code = 'not_found';
    }
    throw CloudflareAdminException(code, message);
  }
}

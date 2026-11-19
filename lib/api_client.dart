import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'models.dart';
import 'pending_store.dart';
import 'workspace_store.dart';

String newRequestId() {
  final random = Random.secure();
  return List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.uncertain = false});
  final String code;
  final String message;
  final bool uncertain;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl, http.Client? client, PendingStore? pendingStore})
    : _initialBaseUrl = baseUrl ?? const String.fromEnvironment('API_BASE_URL'),
      _baseUrl = '',
      _client = client ?? http.Client(),
      _pendingStore = pendingStore ?? PendingStore();

  WorkspaceConnection? get activeWorkspace =>
      _workspaceId == null || _baseUrl.isEmpty
      ? null
      : WorkspaceConnection(
          origin: _baseUrl,
          workspaceId: _workspaceId!,
          name: '',
        );

  Future<WorkspaceConnection> loadWorkspace(WorkspaceStore store) async {
    final saved = await store.selected();
    if (saved != null) {
      final verified = await inspectWorkspace(saved.origin);
      if (verified.workspaceId != saved.workspaceId) {
        throw const ApiException(
          'workspace_mismatch',
          'Ruang kerja tersimpan berbeda dari server.',
        );
      }
      if (_token == null || _workspaceId != verified.workspaceId) {
        _baseUrl = verified.origin;
        _workspaceId = verified.workspaceId;
        _workspaceReady = verified.ready;
        _pending = _userId == null ? null : await _loadPending(_userId!);
        _revision++;
      }
      if (!verified.ready) {
        throw const ApiException(
          'workspace_unclaimed',
          'Workspace belum diklaim pemilik. Selesaikan setup token terlebih dahulu.',
        );
      }
      return verified;
    }
    if (_initialBaseUrl.isNotEmpty) {
      final verified = await inspectWorkspace(_initialBaseUrl);
      if (!verified.ready) {
        throw const ApiException(
          'workspace_unclaimed',
          'Workspace belum diklaim pemilik.',
        );
      }
      _baseUrl = verified.origin;
      _workspaceId = verified.workspaceId;
      _workspaceReady = verified.ready;
      await store.add(verified);
      await store.select(verified);
      _revision++;
      return verified;
    }
    throw const ApiException(
      'workspace_required',
      'Hubungkan workspace Cloudflare terlebih dahulu.',
    );
  }

  final String _initialBaseUrl;
  String _baseUrl;
  String get baseUrl => _baseUrl;
  String? _workspaceId;
  bool _workspaceReady = false;
  bool get hasVerifiedWorkspace =>
      _workspaceId != null && _workspaceReady && isConfigured;

  Future<WorkspaceConnection> inspectWorkspace(String origin) =>
      WorkspaceConnection.verifyOrigin(origin, client: _client);

  Future<(AppUser, String)> claimWorkspaceOwner(
    WorkspaceConnection workspace, {
    required String setupToken,
    required String name,
    required String username,
    required String password,
    required String workspaceName,
  }) async {
    if (!workspaceName.trim().isNotEmpty ||
        workspaceName.trim().length > 100 ||
        setupToken.isEmpty ||
        setupToken.length > 256) {
      throw const ApiException(
        'invalid_input',
        'Lengkapi nama usaha dan token setup yang valid.',
      );
    }
    final claimRequest =
        http.Request('POST', Uri.parse('${workspace.origin}/v1/setup/owner'))
          ..followRedirects = false
          ..headers.addAll(const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode({
            'setupToken': setupToken,
            'name': name.trim(),
            'username': username.trim(),
            'password': password,
            'workspaceName': workspaceName.trim(),
          });
    final response = await _client
        .send(claimRequest)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 45));
    if (response.isRedirect) {
      throw const ApiException(
        'workspace_redirect',
        'Ruang kerja mengalihkan permintaan. Periksa kembali alamatnya.',
      );
    }
    final result = _decode(http.Response(response.body, response.statusCode));
    try {
      final user = AppUser.fromJson(result['user'] as Map<String, dynamic>);
      final token = result['token'];
      if (user.role != 'owner' ||
          !user.active ||
          token is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
        throw const FormatException();
      }
      return (user, token);
    } on (TypeError, FormatException) {
      throw const ApiException(
        'invalid_response',
        'Pendaftaran ruang kerja belum dapat dikonfirmasi.',
        uncertain: true,
      );
    }
  }

  Future<void> acceptSession(
    AppUser user,
    String token, {
    String? workspaceId,
  }) async {
    if (!isConfigured ||
        !user.active ||
        user.role != 'owner' && user.role != 'employee' ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      throw const ApiException(
        'invalid_session',
        'Sesi workspace tidak valid.',
      );
    }
    if (_workspaceId == null && workspaceId == null) {
      throw const ApiException(
        'workspace_required',
        'Verifikasi workspace sebelum masuk.',
      );
    }
    _workspaceId ??= workspaceId;
    if (_workspaceId == null) {
      throw const ApiException(
        'workspace_required',
        'Pilih workspace sebelum masuk.',
      );
    }
    _workspaceReady = true;
    _userId = user.id;
    _pending = await _loadPending(user.id);
  }

  Future<void> clearWorkspace() async {
    if (_token != null || _pending != null) {
      throw const ApiException(
        'workspace_switch_confirmation',
        'Keluar dari akun sebelum menghapus workspace.',
      );
    }
    _baseUrl = '';
    _workspaceId = null;
    _workspaceReady = false;
    _token = null;
    _userId = null;
    _pending = null;
    _revision++;
  }

  Future<void> switchWorkspace(WorkspaceConnection workspace) async {
    final check = await inspectWorkspace(workspace.origin);
    if (check.workspaceId != workspace.workspaceId) {
      throw const ApiException(
        'workspace_mismatch',
        'Ruang kerja berbeda dengan kode pemasangan.',
      );
    }
    if (_token != null || _pending != null) {
      throw const ApiException(
        'workspace_switch_confirmation',
        'Keluar dari ruang kerja saat ini sebelum berpindah ke ruang kerja lain.',
      );
    }
    _baseUrl = check.origin;
    _workspaceId = check.workspaceId;
    _workspaceReady = check.ready;
    if (!check.ready) {
      throw const ApiException(
        'workspace_unclaimed',
        'Workspace belum diklaim pemilik.',
      );
    }
    _token = null;
    _userId = null;
    _pending = null;
    _revision++;
  }

  Future<void> restoreWorkspace() async {
    if (_initialBaseUrl.trim().isEmpty) return;
    try {
      await switchWorkspace(await inspectWorkspace(_initialBaseUrl.trim()));
    } catch (_) {
      _baseUrl = '';
      _workspaceId = null;
      _workspaceReady = false;
      _token = null;
      _userId = null;
      _pending = null;
      _revision++;
    }
  }

  final http.Client _client;
  final PendingStore _pendingStore;
  String? _token;
  String? _userId;
  PendingRequest? _pending;
  bool _writing = false;
  int _revision = 0;
  int get revision => _revision;
  bool get hasPendingRequest => _pending != null;
  int? attendanceNextOffset;
  int? bonNextOffset;
  int? employeesNextOffset;
  bool get isConfigured {
    final uri = Uri.tryParse(baseUrl);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  Uri _uri(String path) {
    if (!hasVerifiedWorkspace) {
      throw const ApiException(
        'configuration',
        'Layanan belum dikonfigurasi. Hubungi pengelola aplikasi.',
      );
    }
    return Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');
  }

  Map<String, String> _headers({String? requestId}) => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
    if (requestId != null) 'Idempotency-Key': requestId,
  };

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? requestId,
  }) async {
    final request = http.Request(method, _uri(path))
      ..headers.addAll(_headers(requestId: requestId));
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 30));
      return _decode(response);
    } on TimeoutException {
      throw ApiException(
        'timeout',
        requestId == null
            ? 'Layanan terlalu lama merespons. Coba lagi.'
            : 'Status pengiriman belum diketahui. Coba lagi dengan data yang sama untuk memeriksa hasil.',
        uncertain: requestId != null,
      );
    } on http.ClientException {
      throw ApiException(
        'connection',
        requestId == null
            ? 'Tidak dapat terhubung. Periksa koneksi internet.'
            : 'Koneksi terputus. Status pengiriman belum diketahui; coba lagi dengan data yang sama.',
        uncertain: requestId != null,
      );
    } on SocketException {
      throw ApiException(
        'connection',
        'Tidak dapat terhubung. Periksa koneksi lalu coba lagi.',
        uncertain: requestId != null,
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const ApiException(
        'invalid_response',
        'Respons layanan tidak valid. Data belum dapat dikonfirmasi.',
        uncertain: true,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(
        'invalid_response',
        'Respons layanan tidak valid.',
        uncertain: true,
      );
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['ok'] != true) {
      final error = decoded['error'];
      throw ApiException(
        response.statusCode == 401
            ? 'unauthorized'
            : error is Map && error['code'] is String
            ? error['code'] as String
            : 'server',
        error is Map && error['message'] is String
            ? error['message'] as String
            : 'Permintaan tidak dapat diproses.',
        uncertain:
            response.statusCode >= 500 ||
            response.statusCode == 401 ||
            (response.statusCode >= 200 &&
                response.statusCode < 300 &&
                decoded['ok'] != false),
      );
    }
    return decoded;
  }

  Future<PendingRequest?> _loadPending(String userId) async {
    try {
      return await _pendingStore.load(baseUrl, userId, _workspaceId);
    } catch (_) {
      throw const ApiException(
        'pending_storage',
        'Data pengiriman belum dapat dibaca. Coba lagi.',
      );
    }
  }

  void _requireSession() {
    if (_token == null || _userId == null) {
      throw const ApiException(
        'unauthorized',
        'Masuk kembali sebelum mengirim data.',
      );
    }
  }

  Never _conflict() => throw const ApiException(
    'pending_request',
    'Selesaikan pemeriksaan pengiriman sebelumnya terlebih dahulu.',
    uncertain: true,
  );

  Future<T> _write<T>(Future<T> Function() operation) async {
    if (_writing) {
      throw const ApiException('busy', 'Tunggu pengiriman selesai.');
    }
    _writing = true;
    try {
      return await operation();
    } finally {
      _writing = false;
    }
  }

  T _parseReceipt<T>(T Function() parse) {
    try {
      return parse();
    } on TypeError {
      throw const ApiException(
        'invalid_response',
        'Bukti pengiriman belum dapat dikonfirmasi.',
        uncertain: true,
      );
    } on FormatException {
      throw const ApiException(
        'invalid_response',
        'Bukti pengiriman belum dapat dikonfirmasi.',
        uncertain: true,
      );
    }
  }

  Future<void> _clearPending(String userId) async {
    try {
      await _pendingStore.clear(baseUrl, userId, _workspaceId);
    } catch (_) {
      throw const ApiException(
        'pending_storage',
        'Bukti pengiriman belum dapat disimpan. Periksa kembali pengiriman.',
        uncertain: true,
      );
    }
    if (_userId == userId) _pending = null;
  }

  Future<T> _mutate<T>(
    PendingRequest request,
    T Function(Map<String, dynamic>) parse,
  ) => _write(() async {
    _requireSession();
    final userId = _userId!;
    _pending = await _loadPending(userId);
    if (_pending != null && !_pending!.matches(request)) _conflict();
    try {
      await _pendingStore.save(baseUrl, userId, request, _workspaceId);
    } catch (_) {
      throw const ApiException(
        'pending_storage',
        'Pengiriman belum dilakukan karena data belum dapat disimpan. Coba lagi.',
      );
    }
    _pending = request;
    try {
      final result = request.photoBase64 == null
          ? await _request(
              'POST',
              request.path,
              body: request.payload,
              requestId: request.requestId,
            )
          : await _sendAttendance(request);
      final receipt = _parseReceipt(() => parse(result));
      await _clearPending(userId);
      _revision++;
      return receipt;
    } on ApiException catch (error) {
      if (!error.uncertain && error.code != 'unauthorized') {
        await _clearPending(userId);
      }
      rethrow;
    }
  });

  Future<String> recoverPending() async {
    _requireSession();
    final pending = _pending;
    if (pending == null) {
      throw const ApiException(
        'no_pending_request',
        'Tidak ada pengiriman yang perlu diperiksa.',
      );
    }
    if (pending.path == '/v1/attendance') {
      final receipt = await _mutate(
        pending,
        (result) =>
            AttendanceRecord.fromJson(result['record'] as Map<String, dynamic>),
      );
      return 'Absensi terkonfirmasi (${receipt.id}).';
    }
    final receipt = await _mutate(
      pending,
      (result) => BonRecord.fromJson(result['record'] as Map<String, dynamic>),
    );
    return 'Bon terkonfirmasi (${receipt.id}).';
  }

  int? _nextOffset(Map<String, dynamic> response) {
    final pagination = response['pagination'];
    return pagination is Map && pagination['hasMore'] == true
        ? (pagination['nextOffset'] as num?)?.toInt()
        : null;
  }

  Future<AppUser> login(String username, String password) async {
    if (!hasVerifiedWorkspace) {
      throw const ApiException(
        'configuration',
        'Pilih workspace sebelum masuk.',
      );
    }
    final result = await _request(
      'POST',
      '/v1/auth/login',
      body: {'username': username.trim(), 'password': password},
    );
    final token = result['token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException('invalid_response', 'Sesi login tidak valid.');
    }
    final user = AppUser.fromJson(result['user'] as Map<String, dynamic>);
    if (!user.active || !['owner', 'employee'].contains(user.role)) {
      throw const ApiException(
        'invalid_response',
        'Akun tidak dapat digunakan.',
      );
    }
    if (_writing) {
      throw const ApiException('busy', 'Tunggu pengiriman selesai.');
    }
    final pending = await _loadPending(user.id);
    _token = token;
    _userId = user.id;
    _pending = pending;
    return user;
  }

  Future<void> logout() async {
    try {
      await _request('POST', '/v1/auth/logout');
    } on ApiException catch (error) {
      if (error.code != 'unauthorized') rethrow;
    }
    clearSession();
  }

  void clearSession() {
    _token = null;
    _userId = null;
    _pending = null;
  }

  void close() => _client.close();

  Future<DashboardData> dashboard() async =>
      DashboardData.fromJson(await _request('GET', '/v1/dashboard'));
  Future<List<AppUser>> employees({int offset = 0}) async {
    final result = await _request(
      'GET',
      '/v1/employees?limit=100&offset=$offset',
    );
    employeesNextOffset = _nextOffset(result);
    return (result['employees'] as List)
        .map((v) => AppUser.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveEmployee({
    String? id,
    required String name,
    required String username,
    String? password,
    bool? active,
  }) async {
    await _write(() async {
      _requireSession();
      _pending = await _loadPending(_userId!);
      if (_pending != null) _conflict();
      final result = await _request(
        id == null ? 'POST' : 'PATCH',
        id == null
            ? '/v1/employees'
            : '/v1/employees/${Uri.encodeComponent(id)}',
        body: {
          'name': name.trim(),
          if (id == null) 'username': username.trim(),
          if (password != null && password.isNotEmpty) 'password': password,
          if (active != null) 'active': active,
        },
      );
      _parseReceipt(
        () => AppUser.fromJson(result['user'] as Map<String, dynamic>),
      );
      _revision++;
    });
  }

  Future<List<AttendanceRecord>> attendance({int offset = 0}) async {
    final result = await _request(
      'GET',
      '/v1/attendance?limit=100&offset=$offset',
    );
    attendanceNextOffset = _nextOffset(result);
    return (result['attendance'] as List)
        .map((v) => AttendanceRecord.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  Future<AttendanceRecord> submitAttendance({
    required String kind,
    required File photo,
    required String requestId,
  }) async {
    _requireSession();
    if (await photo.length() > 2 * 1024 * 1024) {
      throw const ApiException(
        'image_too_large',
        'Foto maksimal 2 MB. Ambil ulang foto.',
      );
    }
    final bytes = await photo.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      throw const ApiException(
        'image_too_large',
        'Foto maksimal 2 MB. Ambil ulang foto.',
      );
    }
    return _mutate(
      PendingRequest(
        path: '/v1/attendance',
        requestId: requestId,
        payload: {'kind': kind},
        photoBase64: base64Encode(bytes),
      ),
      (result) =>
          AttendanceRecord.fromJson(result['record'] as Map<String, dynamic>),
    );
  }

  Future<Map<String, dynamic>> _sendAttendance(PendingRequest pending) async {
    final request = http.MultipartRequest('POST', _uri(pending.path))
      ..headers.addAll({
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
        'Idempotency-Key': pending.requestId,
      })
      ..fields['kind'] = pending.payload['kind'] as String
      ..files.add(
        http.MultipartFile.fromBytes(
          'photo',
          base64Decode(pending.photoBase64!),
          filename: 'photo.jpg',
        ),
      );
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 60));
      return _decode(response);
    } on TimeoutException {
      throw const ApiException(
        'timeout',
        'Status absensi belum diketahui. Periksa kembali pengiriman.',
        uncertain: true,
      );
    } on http.ClientException {
      throw const ApiException(
        'connection',
        'Koneksi terputus. Periksa kembali pengiriman.',
        uncertain: true,
      );
    } on SocketException {
      throw const ApiException(
        'connection',
        'Koneksi terputus. Periksa kembali pengiriman.',
        uncertain: true,
      );
    }
  }

  Future<Uint8List> attendancePhoto(String id) async {
    final response = await _client
        .get(
          _uri('/v1/attendance/${Uri.encodeComponent(id)}/photo'),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      _decode(response);
    }
    return response.bodyBytes;
  }

  Future<List<BonRecord>> bon({int offset = 0}) async {
    final result = await _request('GET', '/v1/bon?limit=100&offset=$offset');
    bonNextOffset = _nextOffset(result);
    return (result['bon'] as List)
        .map((v) => BonRecord.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  Future<BonRecord> submitBon({
    required int amount,
    required String note,
    required String requestId,
  }) async {
    return _mutate(
      PendingRequest(
        path: '/v1/bon',
        requestId: requestId,
        payload: {'amount': amount, 'note': note.trim()},
      ),
      (result) => BonRecord.fromJson(result['record'] as Map<String, dynamic>),
    );
  }

  Future<BonRecord> bonAction(
    String id,
    String action, {
    int? amount,
    required String requestId,
  }) async {
    return _mutate(
      PendingRequest(
        path: '/v1/bon/${Uri.encodeComponent(id)}/actions',
        requestId: requestId,
        payload: {'action': action, if (amount != null) 'amount': amount},
      ),
      (result) => BonRecord.fromJson(result['record'] as Map<String, dynamic>),
    );
  }
}

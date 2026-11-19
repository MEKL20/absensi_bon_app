import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class WorkspaceConnection {
  const WorkspaceConnection({
    required this.origin,
    required this.workspaceId,
    required this.name,
    this.ready = false,
  });

  final String origin;
  final String workspaceId;
  final String name;
  final bool ready;

  static Future<WorkspaceConnection> verifyOrigin(
    String value, {
    http.Client? client,
  }) async {
    final origin = parseWorkspaceOrigin(value);
    final ownClient = client == null;
    final active = client ?? http.Client();
    try {
      final request = http.Request('GET', origin.replace(path: '/v1/workspace'))
        ..followRedirects = false
        ..headers['Accept'] = 'application/json';
      final response = await active
          .send(request)
          .timeout(const Duration(seconds: 12));
      final body = await response.stream.bytesToString().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode != 200) {
        throw const FormatException(
          'Endpoint workspace tidak dapat diverifikasi.',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 3 ||
          decoded['id'] is! String ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(decoded['id'] as String) ||
          decoded['name'] is! String ||
          (decoded['name'] as String).trim().isEmpty ||
          (decoded['name'] as String).length > 100 ||
          decoded['ready'] is! bool) {
        throw const FormatException(
          'Layanan belum siap atau identitas workspace tidak valid.',
        );
      }
      return WorkspaceConnection(
        origin: origin.toString(),
        workspaceId: decoded['id'] as String,
        name: decoded['name'] as String,
        ready: decoded['ready'] as bool,
      );
    } finally {
      if (ownClient) active.close();
    }
  }

  String toQr() => Uri(
    scheme: 'absensi-bon',
    host: 'workspace',
    queryParameters: {'v': '1', 'url': origin, 'id': workspaceId, 'name': name},
  ).toString();

  factory WorkspaceConnection.fromQr(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'absensi-bon' ||
        uri.host != 'workspace' ||
        uri.path.isNotEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.authority.contains('@') ||
        uri.fragment.isNotEmpty ||
        uri.queryParametersAll.length != 4 ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        uri.queryParameters['v'] != '1') {
      throw const FormatException('Kode workspace tidak valid.');
    }
    final result = WorkspaceConnection(
      origin: uri.queryParameters['url'] ?? '',
      workspaceId: uri.queryParameters['id'] ?? '',
      name: uri.queryParameters['name'] ?? '',
    );
    if (parseWorkspaceOrigin(result.origin).toString() != result.origin ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(result.workspaceId) ||
        result.name.trim().isEmpty ||
        result.name.length > 100) {
      throw const FormatException('Kode workspace tidak valid.');
    }
    return result;
  }
}

Uri parseWorkspaceOrigin(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.authority.contains('@') ||
      uri.host.isEmpty ||
      uri.hasPort ||
      uri.path.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException(
      'Masukkan origin HTTPS tanpa kredensial, port, path, atau parameter.',
    );
  }
  final host = uri.host.toLowerCase();
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      RegExp(r'^[0-9.]+$').hasMatch(host) ||
      InternetAddress.tryParse(host) != null ||
      host.length > 253) {
    throw const FormatException(
      'Gunakan nama host DNS publik, bukan alamat lokal atau IP.',
    );
  }
  final labels = host.split('.');
  if (labels.length < 2 ||
      !RegExp(r'[a-z]').hasMatch(labels.last) ||
      labels.any(
        (label) =>
            label.isEmpty ||
            label.length > 63 ||
            !RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label),
      )) {
    throw const FormatException('Nama host DNS tidak valid.');
  }
  return Uri(scheme: 'https', host: host);
}

class WorkspaceStore {
  WorkspaceStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _listKey = 'workspace_connections_v1';
  static const _selectedKey = 'workspace_selected_id_v1';
  final FlutterSecureStorage _storage;

  Future<List<WorkspaceConnection>> list() async {
    final raw = await _storage.read(key: _listKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Data workspace tidak valid.');
    }
    return decoded.map((row) {
      if (row is! Map ||
          row.keys.toSet().difference({'origin', 'id', 'name'}).isNotEmpty ||
          row['origin'] is! String ||
          row['id'] is! String ||
          row['name'] is! String) {
        throw const FormatException('Data workspace tidak valid.');
      }
      final value = WorkspaceConnection(
        origin: row['origin'] as String,
        workspaceId: row['id'] as String,
        name: row['name'] as String,
      );
      parseWorkspaceOrigin(value.origin);
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(value.workspaceId) ||
          value.name.trim().isEmpty ||
          value.name.length > 100) {
        throw const FormatException('Data workspace tidak valid.');
      }
      return value;
    }).toList();
  }

  Future<void> add(WorkspaceConnection value) async {
    parseWorkspaceOrigin(value.origin);
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(value.workspaceId) ||
        value.name.trim().isEmpty ||
        value.name.length > 100) {
      throw const FormatException('Data workspace tidak valid.');
    }
    final values = await list();
    values.removeWhere((item) => item.workspaceId == value.workspaceId);
    values.add(value);
    await _write(values);
  }

  Future<void> remove(String workspaceId) async {
    final values = await list();
    values.removeWhere((item) => item.workspaceId == workspaceId);
    await _write(values);
    if (await _storage.read(key: _selectedKey) == workspaceId) {
      await _storage.delete(key: _selectedKey);
    }
  }

  Future<void> select(WorkspaceConnection value) async {
    final saved = await list();
    if (!saved.any(
      (item) =>
          item.workspaceId == value.workspaceId && item.origin == value.origin,
    )) {
      throw StateError('Workspace belum disimpan.');
    }
    await _storage.write(key: _selectedKey, value: value.workspaceId);
  }

  Future<WorkspaceConnection?> selected() async {
    final id = await _storage.read(key: _selectedKey);
    for (final value in await list()) {
      if (value.workspaceId == id) return value;
    }
    return null;
  }

  Future<void> _write(List<WorkspaceConnection> values) => _storage.write(
    key: _listKey,
    value: jsonEncode(
      values
          .map(
            (item) => {
              'origin': item.origin,
              'id': item.workspaceId,
              'name': item.name,
            },
          )
          .toList(),
    ),
  );
}

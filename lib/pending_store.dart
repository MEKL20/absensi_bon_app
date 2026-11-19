import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class PendingRequest {
  PendingRequest({
    required this.path,
    required this.requestId,
    required Map<String, dynamic> payload,
    this.photoBase64,
  }) : payload = Map.unmodifiable(payload);

  final String path;
  final String requestId;
  final Map<String, dynamic> payload;
  final String? photoBase64;

  factory PendingRequest.fromJson(Map<String, dynamic> json) => PendingRequest(
    path: json['path'] as String,
    requestId: json['requestId'] as String,
    payload: json['payload'] as Map<String, dynamic>,
    photoBase64: json['photoBase64'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'path': path,
    'requestId': requestId,
    'payload': payload,
    if (photoBase64 != null) 'photoBase64': photoBase64,
  };

  bool matches(PendingRequest other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());
}

class PendingStore {
  PendingStore();
  PendingStore.memory() : _memory = {};
  PendingStore.file(File file) : _file = file;

  File? _file;
  Map<String, dynamic>? _memory;
  // Share the lock across clients so a read/modify/rename cannot lose a scope.
  static Future<void> _tail = Future.value();

  Future<T> _locked<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  String _scope(String baseUrl, String userId, [String? workspaceId]) =>
      jsonEncode([baseUrl.replaceAll(RegExp(r'/+$'), ''), workspaceId, userId]);

  Future<Map<String, dynamic>> _read() async {
    if (_memory != null) return Map.of(_memory!);
    final file = _file ??= File(
      '${(await getApplicationSupportDirectory()).path}/pending_requests.json',
    );
    if (!await file.exists()) return {};
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  Future<void> _write(Map<String, dynamic> entries) async {
    if (_memory != null) {
      _memory = entries;
      return;
    }
    final file = _file!;
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(entries), flush: true);
    await temporary.rename(file.path);
  }

  Future<PendingRequest?> load(
    String baseUrl,
    String userId, [
    String? workspaceId,
  ]) => _locked(() async {
    final json = (await _read())[_scope(baseUrl, userId, workspaceId)];
    return json == null
        ? null
        : PendingRequest.fromJson(json as Map<String, dynamic>);
  });

  Future<void> save(
    String baseUrl,
    String userId,
    PendingRequest request, [
    String? workspaceId,
  ]) => _locked(() async {
    final entries = await _read();
    final scope = _scope(baseUrl, userId, workspaceId);
    final previous = entries[scope];
    if (previous != null) {
      if (!PendingRequest.fromJson(
        previous as Map<String, dynamic>,
      ).matches(request)) {
        throw StateError('A different mutation is still pending.');
      }
      return;
    }
    entries[scope] = request.toJson();
    await _write(entries);
  });

  Future<void> clear(String baseUrl, String userId, [String? workspaceId]) =>
      _locked(() async {
        final entries = await _read();
        entries.remove(_scope(baseUrl, userId, workspaceId));
        await _write(entries);
      });
}

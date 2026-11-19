import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:absensi_bon_app/workspace_store.dart';

class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  group('workspace origin validation', () {
    test('accepts a public HTTPS DNS origin', () {
      expect(
        parseWorkspaceOrigin('https://absensi.example.com').toString(),
        'https://absensi.example.com',
      );
    });
    test(
      'rejects HTTP, credentials, paths, query, ports, local hosts, and IPs',
      () {
        for (final value in [
          'http://absensi.example.com',
          'https://owner:password@example.com',
          'https://example.com/path',
          'https://example.com?next=https://evil.example',
          'https://example.com:8443',
          'https://localhost',
          'https://service.localhost',
          'https://127.0.0.1',
          'https://10.0.0.2',
          'https://172.16.0.3',
          'https://192.168.1.4',
          'https://169.254.10.2',
        ]) {
          expect(
            () => parseWorkspaceOrigin(value),
            throwsFormatException,
            reason: value,
          );
        }
      },
    );
    test('rejects malformed workspace ids', () {
      for (final id in [
        'bad',
        '0123456789abcdef0123456789abcdeZ',
        '0123456789abcdef0123456789abcdef0',
      ]) {
        final qr = Uri(
          scheme: 'absensi-bon',
          host: 'workspace',
          queryParameters: {
            'v': '1',
            'url': 'https://example.com',
            'id': id,
            'name': 'Usaha',
          },
        );
        expect(
          () => WorkspaceConnection.fromQr(qr.toString()),
          throwsFormatException,
        );
      }
    });
    test('QR fields cannot inject a second origin', () {
      const workspace = WorkspaceConnection(
        origin: 'https://example.com',
        workspaceId: '0123456789abcdef0123456789abcdef',
        name: 'Usaha & keluarga',
      );
      final parsed = WorkspaceConnection.fromQr(workspace.toQr());
      expect(parsed.origin, workspace.origin);
      expect(parsed.workspaceId, workspace.workspaceId);
      expect(parsed.name, workspace.name);
      final originInjection = workspace.toQr().replaceFirst(
        'https%3A%2F%2Fexample.com',
        'https%3A%2F%2Fexample.com%26url%3Dhttps%253A%252F%252Fevil.example',
      );
      expect(
        () => WorkspaceConnection.fromQr(originInjection),
        throwsFormatException,
      );
      final duplicate =
          'absensi-bon://workspace?v=1&url=https%3A%2F%2Fexample.com&id=${workspace.workspaceId}&name=Safe&url=https%3A%2F%2Fevil.example';
      expect(
        () => WorkspaceConnection.fromQr(duplicate),
        throwsFormatException,
      );
      expect(workspace.toQr(), isNot(contains('token')));
    });
  });
  test(
    'secure storage saves only origin, id, name, and selection id',
    () async {
      final platform = _MemoryStorage();
      final store = WorkspaceStore(storage: platform);
      const workspace = WorkspaceConnection(
        origin: 'https://example.com',
        workspaceId: '0123456789abcdef0123456789abcdef',
        name: 'Usaha',
      );
      await store.add(workspace);
      await store.select(workspace);
      expect((await store.list()).single.origin, workspace.origin);
      final storedList =
          jsonDecode(platform.values['workspace_connections_v1']!) as List;
      expect(storedList.single.keys.toSet(), {'origin', 'id', 'name'});
      expect(
        platform.values['workspace_selected_id_v1'],
        workspace.workspaceId,
      );
      final serialized = platform.values.values.join(' ');
      expect(serialized, isNot(contains('raw-setup-token')));
      expect(serialized, isNot(contains('password')));
      expect(serialized, isNot(contains('session-token')));
      expect(serialized, isNot(contains('sessionToken')));
    },
  );
}

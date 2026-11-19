import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:absensi_bon_app/api_client.dart';
import 'package:absensi_bon_app/login_page.dart';
import 'package:absensi_bon_app/main.dart';
import 'package:absensi_bon_app/workspace_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _EmptyStorage extends FlutterSecureStorage {
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
  testWidgets('sign in validates empty fields without sending requests', (
    tester,
  ) async {
    final api = ApiClient(
      baseUrl: 'https://example.test',
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'id': '0123456789abcdef0123456789abcdef',
            'name': 'Usaha Uji',
            'ready': true,
          }),
          200,
        ),
      ),
    );
    await api.switchWorkspace(
      const WorkspaceConnection(
        origin: 'https://example.test',
        workspaceId: '0123456789abcdef0123456789abcdef',
        name: 'Usaha Uji',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: LoginPage(api: api),
      ),
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pump();
    expect(find.text('Isi username Anda.'), findsOneWidget);
    expect(find.text('Isi password Anda.'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('missing workspace disables login with actionable message', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: LoginPage(api: ApiClient(baseUrl: '')),
      ),
    );
    expect(
      find.text('Layanan belum dikonfigurasi. Hubungi pengelola aplikasi.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Masuk'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('first launch opens the customer workspace gate', (tester) async {
    await tester.pumpWidget(
      MyApp(
        api: ApiClient(baseUrl: ''),
        workspaceStore: WorkspaceStore(storage: _EmptyStorage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hubungkan usaha Anda'), findsOneWidget);
    expect(find.text('Buat atau gabung workspace'), findsOneWidget);
  });
}

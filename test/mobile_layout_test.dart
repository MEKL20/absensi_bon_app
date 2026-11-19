import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:absensi_bon_app/api_client.dart';
import 'package:absensi_bon_app/home_page.dart';
import 'package:absensi_bon_app/main.dart';
import 'package:absensi_bon_app/models.dart';
import 'package:absensi_bon_app/workspace_store.dart';

class LayoutApi extends ApiClient {
  LayoutApi() : super(baseUrl: 'https://example.test');
  int dashboardLoads = 0;
  bool pending = false;
  @override
  bool get hasPendingRequest => pending;
  @override
  Future<String> recoverPending() async {
    pending = false;
    return 'Pengiriman terkonfirmasi.';
  }

  @override
  Future<List<AttendanceRecord>> attendance({int offset = 0}) async => [];
  @override
  Future<List<BonRecord>> bon({int offset = 0}) async => [];
  @override
  Future<List<AppUser>> employees({int offset = 0}) async => [];
  @override
  Future<WorkspaceConnection> inspectWorkspace(String origin) async =>
      const WorkspaceConnection(
        origin: 'https://example.test',
        workspaceId: '0123456789abcdef0123456789abcdef',
        name: 'Usaha Uji',
        ready: true,
      );

  @override
  Future<DashboardData> dashboard() async {
    dashboardLoads++;
    return const DashboardData(
      employeeCount: 0,
      checkedInCount: 0,
      pendingBonCount: 0,
      outstandingAmount: 0,
      attendance: [],
      bon: [],
    );
  }
}

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

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_PREVIEWS')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('docs/previews');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'role navigation preserves bon draft and renders narrow large-text screens',
    (tester) async {
      final font = File(
        '.tools/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      );
      if (font.existsSync()) {
        final loader = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
        await loader.load();
      }
      final icons = File(
        '.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      );
      if (icons.existsSync()) {
        final loader = FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
        await loader.load();
      }
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = LayoutApi();
      addTearDown(api.close);
      final store = WorkspaceStore(storage: _MemoryStorage());
      const paired = WorkspaceConnection(
        origin: 'https://example.test',
        workspaceId: '0123456789abcdef0123456789abcdef',
        name: 'Usaha Uji',
        ready: true,
      );
      await store.add(paired);
      await store.select(paired);
      await tester.pumpWidget(
        RepaintBoundary(
          child: MyApp(api: api, workspaceStore: store),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'sign-in');
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomePage(
            api: api,
            user: const AppUser(
              id: 'employee',
              name: 'Karyawan',
              username: 'employee',
              role: 'employee',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'employee-home');
      final initialLoads = api.dashboardLoads;
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '125000');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture(tester, 'employee-bon');
      await tester.tap(find.byType(NavigationDestination).at(0));
      await tester.pumpAndSettle();
      expect(api.dashboardLoads, greaterThan(initialLoads));
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      expect(find.text('125000'), findsOneWidget);
      api.pending = true;
      await tester.tap(find.byType(NavigationDestination).at(0));
      await tester.pumpAndSettle();
      await capture(tester, 'pending-recovery');
      expect(
        find.text(
          'Ada pengiriman yang belum terkonfirmasi. Periksa hasil sebelum membuat pengiriman baru.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(api.pending, false);
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.physicalSize = const Size(390, 844);
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomePage(
            api: api,
            user: const AppUser(
              id: 'owner',
              name: 'Pemilik',
              username: 'owner',
              role: 'owner',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'owner-home');
      expect(find.text('Ringkasan'), findsWidgets);
      expect(find.text('Karyawan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

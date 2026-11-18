import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:absensi_bon_app/absensi_page.dart';
import 'package:absensi_bon_app/api_client.dart';
import 'package:absensi_bon_app/bon_page.dart';
import 'package:absensi_bon_app/models.dart';

const employee = AppUser(
  id: 'employee-1',
  name: 'Sari',
  username: 'sari',
  role: 'employee',
);
const owner = AppUser(
  id: 'owner-1',
  name: 'Pemilik',
  username: 'owner',
  role: 'owner',
);

BonRecord bonRecord(
  String id,
  String status, {
  int amount = 100000,
  int repaid = 0,
}) => BonRecord(
  id: id,
  employeeId: employee.id,
  employeeName: employee.name,
  amount: amount,
  note: '',
  status: status,
  repaidAmount: repaid,
  createdAt: DateTime.utc(2026, 11, 17, 8),
);

class FormsApi extends ApiClient {
  List<BonRecord> records = [];
  final List<String> requestIds = [];
  bool failSubmission = false;

  @override
  Future<List<AttendanceRecord>> attendance({int offset = 0}) async => [];

  @override
  Future<List<BonRecord>> bon({int offset = 0}) async => [...records];

  @override
  Future<BonRecord> submitBon({
    required int amount,
    required String note,
    required String requestId,
  }) async {
    requestIds.add(requestId);
    if (failSubmission) {
      throw const ApiException(
        'timeout',
        'Status belum diketahui.',
        uncertain: true,
      );
    }
    final record = bonRecord(
      'bon-${requestIds.length}',
      'pending',
      amount: amount,
    );
    records.insert(0, record);
    return record;
  }

  @override
  Future<AttendanceRecord> submitAttendance({
    required String kind,
    required File photo,
    required String requestId,
  }) async {
    throw UnimplementedError();
  }
}

Future<void> showBon(
  WidgetTester tester,
  FormsApi api, {
  AppUser user = employee,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: BonPage(api: api, user: user),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> submitBon(WidgetTester tester) async {
  final button = find.text('Kirim pengajuan').evaluate().isNotEmpty
      ? find.text('Kirim pengajuan')
      : find.text('Periksa pengiriman');
  if (button.evaluate().isEmpty) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(
    button,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Bon is photo-free and rejects zero before API submission', (
    tester,
  ) async {
    final api = FormsApi();
    addTearDown(api.close);
    await showBon(tester, api);
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    expect(find.text('Ambil selfie'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, '0');
    await submitBon(tester);
    expect(find.text('Masukkan jumlah lebih dari nol.'), findsOneWidget);
    expect(api.requestIds, isEmpty);
  });

  testWidgets(
    'Bon locks uncertain draft and reuses request ID until confirmed',
    (tester) async {
      final api = FormsApi()..failSubmission = true;
      addTearDown(api.close);
      await showBon(tester, api);
      await tester.enterText(find.byType(TextFormField).first, '100000');
      await submitBon(tester);
      expect(find.text('100000'), findsOneWidget);
      await submitBon(tester);
      expect(api.requestIds.length, 2);
      expect(api.requestIds[0], api.requestIds[1]);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
        false,
      );
      api.failSubmission = false;
      await submitBon(tester);
      expect(api.requestIds[2], api.requestIds[1]);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
        true,
      );
    },
  );

  testWidgets('Bon can submit consecutive entries without clearing identity', (
    tester,
  ) async {
    final api = FormsApi();
    addTearDown(api.close);
    await showBon(tester, api);
    await tester.enterText(find.byType(TextFormField).first, '100000');
    await submitBon(tester);
    expect(find.text('Pengajuan bon tercatat'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextFormField).first);
    await tester.enterText(find.byType(TextFormField).first, '200000');
    await submitBon(tester);
    expect(api.requestIds.length, 2);
    expect(api.records.map((item) => item.amount), [200000, 100000]);
  });

  testWidgets('Owner debt excludes unapproved and approved amounts', (
    tester,
  ) async {
    final api = FormsApi()
      ..records = [
        bonRecord('pending', 'pending', amount: 500000),
        bonRecord('approved', 'approved', amount: 300000),
        bonRecord('disbursed', 'disbursed', amount: 100000, repaid: 25000),
      ];
    addTearDown(api.close);
    await showBon(tester, api, user: owner);
    expect(find.text('Total sisa utang karyawan Rp 75.000'), findsOneWidget);
    expect(find.text('Ajukan bon'), findsNothing);
    expect(find.text('Setujui'), findsOneWidget);
    expect(find.text('Tolak'), findsOneWidget);
    expect(find.text('Catat pencairan'), findsOneWidget);
    expect(find.text('Catat pembayaran'), findsOneWidget);
  });

  testWidgets('Attendance requires selfie before submission', (tester) async {
    final api = FormsApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: AbsensiPage(api: api, user: employee),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ambil selfie'), findsOneWidget);
    final submit = find.text('Kirim absensi masuk');
    await tester.scrollUntilVisible(
      submit,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final button = tester.widget<FilledButton>(
      find
          .ancestor(
            of: submit,
            matching: find.byWidgetPredicate(
              (widget) => widget is FilledButton,
            ),
          )
          .first,
    );
    expect(button.onPressed, isNull);
  });
}

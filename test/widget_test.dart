import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:absensi_bon_app/api_client.dart';
import 'package:absensi_bon_app/main.dart';

void main() {
  testWidgets('sign in validates empty fields without sending requests', (
    tester,
  ) async {
    await tester.pumpWidget(
      MyApp(api: ApiClient(baseUrl: 'https://example.test')),
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pump();
    expect(find.text('Isi username Anda.'), findsOneWidget);
    expect(find.text('Isi password Anda.'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('missing endpoint disables login with actionable message', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(api: ApiClient(baseUrl: '')));
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
}

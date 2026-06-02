import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viberadar/services/secure_storage_service.dart';
import 'package:viberadar/ui/mobile/mobile_settings_sheet.dart';

void main() {
  Future<void> pumpSection(
    WidgetTester tester,
    SecureStorageService svc,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OpenAiKeySection(storage: svc)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('prefills the field and shows saved indicator when a key exists',
      (tester) async {
    final backend = InMemorySecureStorageBackend();
    await backend.write(key: kOpenAiApiKey, value: 'sk-existing');
    await pumpSection(tester, SecureStorageService(backend: backend));

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    final field = tester
        .widget<TextField>(find.byKey(const Key('openai_key_field')));
    expect(field.controller!.text, 'sk-existing');
  });

  testWidgets('saving a key writes it to the keychain', (tester) async {
    final backend = InMemorySecureStorageBackend();
    await pumpSection(tester, SecureStorageService(backend: backend));

    await tester.enterText(
        find.byKey(const Key('openai_key_field')), 'sk-new-key');
    await tester.tap(find.byKey(const Key('save_openai_key_button')));
    await tester.pumpAndSettle();

    expect(backend.snapshot[kOpenAiApiKey], 'sk-new-key');
    expect(find.text('OpenAI key saved'), findsOneWidget);
  });

  testWidgets('saving an empty value clears the stored key', (tester) async {
    final backend = InMemorySecureStorageBackend();
    await backend.write(key: kOpenAiApiKey, value: 'sk-old');
    await pumpSection(tester, SecureStorageService(backend: backend));

    await tester.enterText(
        find.byKey(const Key('openai_key_field')), '   ');
    await tester.tap(find.byKey(const Key('save_openai_key_button')));
    await tester.pumpAndSettle();

    expect(backend.snapshot.containsKey(kOpenAiApiKey), isFalse);
    expect(find.text('OpenAI key cleared'), findsOneWidget);
  });
}

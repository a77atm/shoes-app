// Smoke test.
//
// The real app widget (ShoeStoreApp) cannot be pumped here: it builds a
// GoRouter that talks to Firebase Auth on the first frame, and Firebase is not
// initialised in a plain widget test. So we test the one screen in main.dart
// that is pure UI with no Firebase dependency.
//
// (The previous version of this file was still the untouched Flutter counter
// template and referenced a MyApp class that does not exist, so the whole test
// suite failed to compile.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoe_store/main.dart';

void main() {
  testWidgets('Firebase init error screen renders the error', (tester) async {
    await tester.pumpWidget(const FirebaseInitErrorApp(error: 'boom'));

    expect(find.text('تعذّر بدء تشغيل Firebase'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}

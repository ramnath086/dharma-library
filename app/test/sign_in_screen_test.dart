import 'package:dharma_library/core/auth/auth_actions.dart';
import 'package:dharma_library/core/offline/local_store.dart';
import 'package:dharma_library/core/providers.dart';
import 'package:dharma_library/core/theme/app_theme.dart';
import 'package:dharma_library/features/settings/sign_in_screen.dart';
import 'package:dharma_library/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() {
    AppTheme.useGoogleFonts = false;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('rejects invalid email; send + verify use the gateway; reading is not required', timeout: const Timeout(Duration(minutes: 1)), (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await tester.runAsync(() => LocalStore.inMemory());
    String? sentEmail;
    String? verifiedToken;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store!),
        prefsProvider.overrideWithValue(prefs),
        connectivityProvider.overrideWith((ref) => Stream.value(false)),
        authActionsProvider.overrideWith((ref) => AuthActions(
          sendOtp: (email, redirect) async {
            sentEmail = email;
            expect(redirect, 'dharmalibrary://auth-callback');
          },
          verifyOtp: (email, token) async {
            verifiedToken = token;
          },
        )),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SignInScreen(),
      ),
    ));
    await _settle(tester);

    expect(find.textContaining('without signing in'), findsOneWidget);
    expect(find.textContaining('Continue without an account'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await tester.tap(find.text('Send sign-in link'));
    await _settle(tester);
    expect(find.textContaining('does not look like an email'), findsOneWidget);
    expect(sentEmail, isNull);

    await tester.enterText(find.byType(TextField).first, 'reader@example.com');
    await tester.tap(find.text('Send sign-in link'));
    await _settle(tester);
    expect(sentEmail, 'reader@example.com');
    expect(find.textContaining('Check your email'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Verify'));
    await _settle(tester);
    expect(verifiedToken, '123456');
  });
}

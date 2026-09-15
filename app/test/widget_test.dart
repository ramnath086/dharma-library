import 'package:dharma_library/core/providers.dart';
import 'package:dharma_library/core/theme/app_theme.dart';
import 'package:dharma_library/main.dart';
import 'package:dharma_library/core/offline/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert';
import 'dart:io';

Future<void> _settle(WidgetTester tester) async {
  // pumpAndSettle can hang on indefinite animations/streams; pump a bounded amount instead.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() {
    AppTheme.useGoogleFonts = false;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('home renders work title and chapter list from bundle; Malayalam locale switches UI', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await LocalStore.inMemory();
    await store.importBundle((jsonDecode(File('assets/bundles/bhagavata-purana.json').readAsStringSync()) as Map).cast<String, dynamic>());

    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        prefsProvider.overrideWithValue(prefs),
        connectivityProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: const DharmaLibraryApp(),
    ));
    await _settle(tester);

    expect(find.text('Dharma Library'), findsWidgets);
    expect(find.textContaining('Bhāgavata'), findsWidgets);
    expect(find.textContaining('10 verses'), findsWidgets);

    // switch to Malayalam
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await _settle(tester);
    await tester.tap(find.text('മലയാളം'));
    await _settle(tester);
    expect(find.text('ഗ്രന്ഥശാല'), findsWidgets);
  });
}

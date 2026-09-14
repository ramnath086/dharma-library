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
    await store.importBundle(jsonDecode(File('assets/bundles/bhagavata-purana.json').readAsStringSync()));

    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store), prefsProvider.overrideWithValue(prefs)],
      child: const DharmaLibraryApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Śrīmad Bhāgavata Purāṇa'), findsOneWidget);
    expect(find.textContaining('10 verses'), findsOneWidget);

    // switch to Malayalam
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('മലയാളം'));
    await tester.pumpAndSettle();
    expect(find.text('ഗ്രന്ഥശാല'), findsOneWidget);
  });
}

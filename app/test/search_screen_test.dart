import 'dart:convert';
import 'dart:io';

import 'package:dharma_library/core/db/repository.dart';
import 'package:dharma_library/core/offline/local_store.dart';
import 'package:dharma_library/core/providers.dart';
import 'package:dharma_library/core/theme/app_theme.dart';
import 'package:dharma_library/features/search/search_screen.dart';
import 'package:dharma_library/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() {
    AppTheme.useGoogleFonts = false;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> pumpSearch(WidgetTester tester, LocalStore store, SharedPreferences prefs) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(Repository(store: store)),
        prefsProvider.overrideWithValue(prefs),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SearchScreen(),
      ),
    ));
    await _settle(tester);
  }

  Future<LocalStore> bundleStore(WidgetTester tester) async {
    final store = await tester.runAsync(() => LocalStore.inMemory());
    await tester.runAsync(() =>
        store!.importBundle((jsonDecode(File('assets/bundles/bhagavata-purana.json').readAsStringSync()) as Map).cast<String, dynamic>()));
    return store!;
  }

  testWidgets('successful searches are remembered, replayed, and cleared', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await bundleStore(tester);
    await pumpSearch(tester, store, prefs);

    // empty state starts with the tip, no recents
    expect(find.textContaining('diacritics are optional'), findsOneWidget);
    expect(find.text('Recent searches'), findsNothing);

    // a query with results is persisted
    await tester.enterText(find.byType(TextField), 'naimisa');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);
    expect(prefs.getStringList('recentSearches'), ['naimisa']);

    // a query with no results is NOT remembered
    await tester.enterText(find.byType(TextField), 'zzzz-nothing');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);
    expect(prefs.getStringList('recentSearches'), ['naimisa']);

    // clear the field -> recents surface with header + clear-all action
    await tester.enterText(find.byType(TextField), '');
    await _settle(tester);
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('naimisa'), findsOneWidget);

    // re-pumping (new screen instance) keeps recents from prefs
    await pumpSearch(tester, store, prefs);
    expect(find.text('naimisa'), findsOneWidget);

    // tapping the chip fills the field and re-runs the search
    await tester.tap(find.text('naimisa'));
    await _settle(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'naimisa');
    expect(find.text('SB 1.1.4'), findsWidgets); // result tile(s) for the Naimisha hit

    // clear-all empties the list and the prefs
    await tester.enterText(find.byType(TextField), '');
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.clear_all));
    await _settle(tester);
    expect(find.text('Recent searches'), findsNothing);
    expect(prefs.getStringList('recentSearches'), isNull);
  });
}

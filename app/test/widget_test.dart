import 'package:dharma_library/core/db/repository.dart';
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

/// sqflite_ffi does real I/O on a background isolate, which never completes
/// inside the widget test's fake-async zone. Run pumps under [runAsync] so
/// those futures can resolve, with a bounded number of frames.
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

  testWidgets('home renders work title and chapter list from bundle; Malayalam locale switches UI', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await tester.runAsync(() => LocalStore.inMemory());
    await tester.runAsync(() => store!.importBundle((jsonDecode(File('assets/bundles/bhagavata-purana.json').readAsStringSync()) as Map).cast<String, dynamic>()));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store!),
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

  testWidgets('dashboard: study progress reflects reading history; quick actions switch tabs', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await tester.runAsync(() => LocalStore.inMemory());
    await tester.runAsync(() => store!.importBundle((jsonDecode(File('assets/bundles/bhagavata-purana.json').readAsStringSync()) as Map).cast<String, dynamic>()));

    // read three verses first so the dashboard has something to report
    final repo = Repository(store: store!);
    await tester.runAsync(() async {
      final toc = await repo.toc('bhagavata-purana');
      final ch = await repo.chapter(toc.chapters.first.id);
      for (var i = 0; i < 3; i++) {
        await repo.recordProgress(workId: toc.work.id, verse: ch.verses[i], sectionId: ch.id, totalVerses: 10, position: i + 1);
      }
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        prefsProvider.overrideWithValue(prefs),
        connectivityProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: const DharmaLibraryApp(),
    ));
    await _settle(tester);

    expect(find.text('3 of 10 verses explored'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(find.widgetWithText(ActionChip, 'Search'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Ask'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Bookmarks'), findsOneWidget);

    // quick action chips switch shell branches (find the chip, not the nav label)
    final askChip = find.widgetWithText(ActionChip, 'Ask');
    await tester.ensureVisible(askChip);
    await _settle(tester);
    await tester.tap(askChip);
    await _settle(tester);
    expect(find.text('Ask the Bhāgavatam'), findsOneWidget);
  });

  testWidgets('daily verse card shows a corpus verse; tapping records the streak day', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await tester.runAsync(() => LocalStore.inMemory());
    await tester.runAsync(() => store!.importBundle((jsonDecode(File('assets/bundles/bhagavata-purana.json').readAsStringSync()) as Map).cast<String, dynamic>()));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store!),
        prefsProvider.overrideWithValue(prefs),
        connectivityProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: const DharmaLibraryApp(),
    ));
    await _settle(tester);

    // the card shows today's pick from the published corpus (any SB ref)
    expect(find.textContaining('Daily verse · SB '), findsOneWidget);
    expect(prefs.getStringList('dailyReadDates'), isNull);

    // tapping it records today and navigates to the verse
    await tester.tap(find.textContaining('Daily verse · SB '));
    await _settle(tester);
    final days = prefs.getStringList('dailyReadDates');
    expect(days, isNotNull);
    expect(days!.length, 1);
    expect(days.single, isNotEmpty);
  });
}

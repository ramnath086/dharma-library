import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:dharma_library/core/offline/local_store.dart';
import 'package:dharma_library/core/providers.dart';
import 'package:dharma_library/core/theme/app_theme.dart';
import 'package:dharma_library/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _settleUntil(WidgetTester tester, Finder finder, {int frames = 40}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
}

/// Tiny second-work bundle so the catalogue test does not import the 3.5 MB Gītā JSON.
Map<String, dynamic> _stubGitaBundle() {
    const chapterCounts = [47, 72, 43, 42, 29, 47, 30, 28, 34, 42, 55, 20, 34, 27, 20, 24, 28, 78];
  assert(chapterCounts.reduce((a, b) => a + b) == 700);
  return {
    'toc': {
      'work': {
        'id': 'work-bhagavad-gita',
        'slug': 'bhagavad-gita',
        'short_code': 'BG',
        'title_iast': 'Śrīmad Bhagavad Gītā',
        'title_sa': 'श्रीमद्भगवद्गीता',
        'original_language': 'sa',
        'original_script': 'Deva',
        'structure': const [],
        'metadata': const {'total_chapters': 18, 'total_verses': 700},
      },
      'sections': [
        for (var i = 0; i < chapterCounts.length; i++)
          {
            'id': 'gita-ch-${i + 1}',
            'ref': '${i + 1}',
            'level': 1,
            'ordinal': i + 1,
            'verse_count': chapterCounts[i],
            'title_iast': 'Adhyāya ${i + 1}',
            'children': const [],
          },
      ],
    },
    'editions': const [],
    'people': const [],
    'places': const [],
    'topics': const [],
    'stories': const [],
    'mentions': const [],
    'entity_names': const [],
    'cross_references': const [],
    'sections': const [],
    'generated_at': '2026-09-22T00:00:00Z',
  };
}

void main() {
  setUpAll(() {
    AppTheme.useGoogleFonts = false;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('Home lists every bundled work without hard-coded slugs', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await tester.runAsync(() => LocalStore.inMemory());
    await tester.runAsync(() async {
      await store!.importBundle((jsonDecode(File('test/fixtures/mini_bhagavata_bundle.json').readAsStringSync()) as Map).cast<String, dynamic>());
      await store.importBundle(_stubGitaBundle());
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store!),
        prefsProvider.overrideWithValue(prefs),
        connectivityProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: const DharmaLibraryApp(),
    ));
    await _settleUntil(tester, find.textContaining('Published works'));
    await _settleUntil(tester, find.textContaining('Gītā'));

    expect(find.textContaining('Bhāgavata'), findsWidgets);
    expect(find.textContaining('Gītā'), findsWidgets);
    final nBhagavata = ((jsonDecode(File('test/fixtures/mini_bhagavata_bundle.json').readAsStringSync()) as Map)['sections'] as List)
        .fold<int>(0, (n, s) => n + ((s as Map)['verses'] as List).length);
    expect(find.textContaining('$nBhagavata verses'), findsWidgets);
    expect(find.textContaining('700 verses'), findsWidgets);
    expect(find.textContaining('18 chapters'), findsWidgets);
    expect(find.textContaining('Published works'), findsOneWidget);
  });
}

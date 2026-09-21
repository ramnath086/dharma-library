import 'dart:convert';
import 'dart:io';

import 'package:dharma_library/core/offline/local_store.dart';
import 'package:dharma_library/core/providers.dart';
import 'package:dharma_library/core/theme/app_theme.dart';
import 'package:dharma_library/main.dart';
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

  testWidgets('Home lists every bundled work without hard-coded slugs', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await tester.runAsync(() => LocalStore.inMemory());
    await tester.runAsync(() async {
      await store!.importBundle((jsonDecode(File('assets/bundles/bhagavata-purana.json').readAsStringSync()) as Map).cast<String, dynamic>());
      await store.importBundle((jsonDecode(File('assets/bundles/bhagavad-gita.json').readAsStringSync()) as Map).cast<String, dynamic>());
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store!),
        prefsProvider.overrideWithValue(prefs),
        connectivityProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: const DharmaLibraryApp(),
    ));
    await _settle(tester);

    expect(find.textContaining('Bhāgavata'), findsWidgets);
    expect(find.textContaining('Bhagavad Gītā'), findsWidgets);
    final nBhagavata = ((jsonDecode(File('assets/bundles/bhagavata-purana.json').readAsStringSync()) as Map)['sections'] as List)
        .fold<int>(0, (n, s) => n + ((s as Map)['verses'] as List).length);
    expect(find.textContaining('$nBhagavata verses'), findsWidgets);
    expect(find.textContaining('700 verses'), findsWidgets);
    expect(find.textContaining('18 chapters'), findsWidgets);
    expect(find.textContaining('Published works'), findsOneWidget);
  });
}

import 'package:dharma_library/core/db/models.dart';
import 'package:dharma_library/core/db/repository.dart';
import 'package:dharma_library/core/offline/local_store.dart';
import 'package:dharma_library/core/providers.dart';
import 'package:dharma_library/core/theme/app_theme.dart';
import 'package:dharma_library/features/reader/verse_card.dart';
import 'package:dharma_library/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The verse bodies the card renders (mūla, IAST, translation) — read straight
/// off the widgets so the assertion does not depend on finder heuristics.
Iterable<String> _bodies(WidgetTester tester) =>
    tester.widgetList<SelectableText>(find.byType(SelectableText)).map((w) => w.data ?? '');

/// sqflite_ffi does real I/O on a background isolate; pump under runAsync.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _devaBody = 'जन्माद्यस्य यतोऽन्वयादितरतश्चार्थेष्वभिज्ञः स्वराट्';
const _iastBody = 'janmādy asya yato ’nvayād itaratas cārtheṣv abhijñaḥ svarāṭ';

/// The published pilot translation (1.1.1, en) — must render verbatim.
const _pilotTranslation =
    'Oṁ. Obeisance to the blessed Lord Vāsudeva.\nWe meditate upon the supreme truth.';

/// The published pilot translation of 1.1.2 — the verse just after the first.
const _secondTranslation =
    'Here is set forth the highest dharma, free of every ulterior motive, for the good who are without envy; '
    'here the real substance is to be known — that which grants well-being and uproots the threefold misery. '
    'In this Śrīmad Bhāgavata, composed by the great sage, what need is there of any other scripture? '
    'The Lord is at once captured in the heart of those who are fortunate enough to wish to hear it — in that very moment.';

/// Published word meanings of 1.1.2 (subset, verbatim from the bundle).
const _secondMeanings = [
  {'word': 'dharmaḥ', 'meaning': 'dharma, religion'},
  {'word': 'projjhita-kaitavaḥ', 'meaning': 'from which all deceit / ulterior motive is cast out'},
];

Map<String, dynamic> _rendering(String kind, String body, {String lang = 'sa', String script = 'Deva', String id = 'ed-1', List<Map<String, dynamic>>? wm}) => {
      'edition_id': id,
      'kind': kind,
      'language_code': lang,
      'script_code': script,
      'body': body,
      if (wm != null) 'word_meanings': wm,
    };

Map<String, dynamic> _edition(String id, String kind, String lang, String script) => {
      'id': id,
      'work_id': 'w1',
      'slug': 'ed-$id',
      'kind': kind,
      'language_code': lang,
      'script_code': script,
      'title': '$kind $lang',
      'rights_status': 'original',
      'attribution_text': 'Dharma Library',
    };

/// A verse as published today: mūla + IAST always, and translation / word
/// meanings only for the 1.1.1–1.1.10 pilot.
Verse _verse({
  required bool withTranslation,
  required bool withWordMeanings,
  String ref = '1.1.1',
  String translation = _pilotTranslation,
  List<Map<String, dynamic>> meanings = const [
    {'word': 'janma-ādi', 'meaning': 'birth and the rest (sustenance, dissolution)'},
  ],
}) => Verse.fromJson({
      'id': 'v-$ref',
      'ref': ref,
      'kind': 'verse',
      'ordinal': 1,
      'meter': 'anuṣṭubh',
      'renderings': [
        _rendering('base_text', _devaBody),
        _rendering('transliteration', _iastBody, script: 'Latn', id: 'ed-2'),
        if (withTranslation) _rendering('translation', translation, lang: 'en', script: 'Latn', id: 'ed-3'),
        if (withWordMeanings)
          _rendering(
            'word_meanings',
            meanings.map((m) => '${m['word']} — ${m['meaning']}').join('\n'),
            lang: 'en',
            script: 'Latn',
            id: 'ed-4',
            wm: meanings,
          ),
      ],
    });

Future<void> _pump(
  WidgetTester tester, {
  required Verse verse,
  bool withWordMeanings = false,
  String locale = 'en',
}) async {
  SharedPreferences.setMockInitialValues({
    'showTranslation': true,
    'showWordMeanings': withWordMeanings,
    'locale': locale,
  });
  final prefs = await SharedPreferences.getInstance();
  final store = await tester.runAsync(() => LocalStore.inMemory());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(Repository(store: store!)),
      prefsProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: VerseCard(verse: verse, editions: [
        Edition.fromJson(_edition('ed-1', 'base_text', 'sa', 'Deva')),
        Edition.fromJson(_edition('ed-2', 'transliteration', 'sa', 'Latn')),
        Edition.fromJson(_edition('ed-3', 'translation', 'en', 'Latn')),
        Edition.fromJson(_edition('ed-4', 'word_meanings', 'en', 'Latn')),
      ], workSlug: 'bhagavata-purana'))),
    ),
  ));
  await _settle(tester);
}

void main() {
  setUpAll(() {
    AppTheme.useGoogleFonts = false;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('a verse without a published translation says so explicitly', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    await _pump(tester, verse: _verse(withTranslation: false, withWordMeanings: false));

    expect(
      find.text('No translation is available for this verse yet — Sanskrit text only.'),
      findsOneWidget,
    );
    // the mūla and IAST still render — only the missing part is disclosed
    expect(_bodies(tester), contains(_devaBody));
    expect(_bodies(tester), contains(_iastBody));
  });

  testWidgets('a verse without word meanings says so explicitly when they are enabled', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    await _pump(tester, verse: _verse(withTranslation: false, withWordMeanings: false), withWordMeanings: true);

    expect(find.text('No word meanings are available for this verse yet.'), findsOneWidget);
    expect(find.text('Word meanings'), findsNothing); // no empty expander
  });

  testWidgets('word-meanings disclosure is silent while the section is off', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    await _pump(tester, verse: _verse(withTranslation: false, withWordMeanings: false));

    expect(find.text('No word meanings are available for this verse yet.'), findsNothing);
  });

  testWidgets('published pilot content renders unchanged and shows no disclosure', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    await _pump(tester, verse: _verse(withTranslation: true, withWordMeanings: true), withWordMeanings: true);

    expect(_bodies(tester), contains(_devaBody));
    expect(_bodies(tester), contains(_pilotTranslation)); // verbatim, unmodified
    expect(find.text('Word meanings'), findsOneWidget);
    expect(find.text('No translation is available for this verse yet — Sanskrit text only.'), findsNothing);
    expect(find.text('No word meanings are available for this verse yet.'), findsNothing);
  });

  testWidgets(
    'a later pilot verse (1.1.2) renders its translation and word meanings too',
    timeout: const Timeout(Duration(minutes: 2)),
    (tester) async {
      // Regression: the Bhāgavata pilot covers 1.1.1–1.1.10, so the reader must
      // show translation + word meanings for 1.1.2 exactly as for 1.1.1.
      await _pump(
        tester,
        verse: _verse(
          withTranslation: true,
          withWordMeanings: true,
          ref: '1.1.2',
          translation: _secondTranslation,
          meanings: _secondMeanings,
        ),
        withWordMeanings: true,
      );

      expect(_bodies(tester), contains(_secondTranslation)); // verbatim, unmodified
      expect(find.text('Word meanings'), findsOneWidget);
      expect(find.text('No translation is available for this verse yet — Sanskrit text only.'), findsNothing);
      expect(find.text('No word meanings are available for this verse yet.'), findsNothing);
    },
  );

  testWidgets('the disclosure is localized in Malayalam', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    await _pump(
      tester,
      verse: _verse(withTranslation: false, withWordMeanings: false),
      withWordMeanings: true,
      locale: 'ml',
    );

    expect(find.text('ഈ ശ്ലോകത്തിന് ഇതുവരെ പരിഭാഷ ലഭ്യമല്ല — സംസ്കൃത മൂലം മാത്രമേയുള്ളൂ.'), findsOneWidget);
    expect(find.text('ഈ ശ്ലോകത്തിന് ഇതുവരെ പദാർത്ഥം ലഭ്യമല്ല.'), findsOneWidget);
    expect(find.textContaining('No translation is available'), findsNothing);
  });
}

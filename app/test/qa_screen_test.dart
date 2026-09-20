import 'package:dharma_library/core/db/models.dart';
import 'package:dharma_library/core/db/repository.dart';
import 'package:dharma_library/core/offline/local_store.dart';
import 'package:dharma_library/core/providers.dart';
import 'package:dharma_library/core/theme/app_theme.dart';
import 'package:dharma_library/features/qa/ask_screen.dart';
import 'package:dharma_library/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// sqflite_ffi does real I/O on a background isolate; pump under runAsync.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A backend-backed repository stub: suggestion starters and a canned answer,
/// no network. `isSignedIn` stays false (auth needs a real client).
class _FakeRepo extends Repository {
  _FakeRepo({required super.store});
  bool limitReached = false;

  @override
  bool get hasBackend => true;
  @override
  bool get online => true;

  @override
  Future<List<String>> askSuggestedQuestions(String locale) async =>
      ['Who compiled the Vedas, and why?', 'What is the highest truth?'];

  @override
  Future<QaAnswer> ask(String question, {String language = 'en', String? workSlug, String? sessionId}) async {
    if (limitReached) throw QaLimitException(30);
    return QaAnswer.fromJson({
      'answer': 'Test answer text',
      'citations': [
        {'verse_id': 'v1', 'ref': '1.1.1', 'quote': 'quoted text', 'work_slug': 'bhagavata-purana'}
      ],
      'grounded': true,
      'model': 'test-model',
      'session_id': 'session-1',
      'message_id': 'message-1',
    });
  }
}

void main() {
  setUpAll(() {
    AppTheme.useGoogleFonts = false;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('models', () {
    test('QaAnswer parses continuity + feedback ids from the ask response', () {
      final a = QaAnswer.fromJson({
        'answer': 'a',
        'citations': [
          {'verse_id': 'v', 'ref': '1.1.2', 'quote': 'q'}
        ],
        'grounded': true,
        'model': 'm',
        'session_id': 'sid-9',
        'message_id': 'mid-7',
      });
      expect(a.sessionId, 'sid-9');
      expect(a.messageId, 'mid-7');
      expect(a.citations.single.ref, '1.1.2');
      // older responses without the new fields stay valid
      final old = QaAnswer.fromJson({'answer': '', 'citations': const [], 'grounded': false});
      expect(old.sessionId, isNull);
      expect(old.messageId, isNull);
    });

    test('QaSession / QaMessage parse stored rows', () {
      final s = QaSession.fromJson({'id': 's1', 'language': 'ml', 'title': 'T', 'created_at': '2026-09-17T10:00:00Z'});
      expect(s.language, 'ml');
      expect(s.createdAt, isNotNull);
      final m = QaMessage.fromJson({
        'id': 'm1', 'role': 'assistant', 'content': 'hello',
        'citations': const [], 'grounded': true, 'feedback': 1, 'created_at': '2026-09-17T10:01:00Z',
      });
      expect(m.isUser, isFalse);
      expect(m.feedback, 1);
      expect(m.grounded, isTrue);
    });

    test('QaLimitException carries the cap', () {
      expect(QaLimitException(30).dailyCap, 30);
      expect(QaLimitException(null).message, contains('cap'));
    });
  });

  group('AskScreen', () {
    Future<void> pumpAsk(WidgetTester tester, Repository repo) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          prefsProvider.overrideWithValue(prefs),
          connectivityProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AskScreen(),
        ),
      ));
      await _settle(tester);
    }

    testWidgets('without a backend the input is gated and the disclaimer shows', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
      final store = await tester.runAsync(() => LocalStore.inMemory());
      await pumpAsk(tester, Repository(store: store!));
      expect(find.textContaining('not a substitute for a teacher'), findsOneWidget);
      expect(find.text('Ask needs an internet connection.'), findsOneWidget);
      expect(find.byIcon(Icons.send), findsNothing); // input row replaced by the offline note
    });

    testWidgets('empty thread shows suggested questions; tapping one fills the field', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
      final store = await tester.runAsync(() => LocalStore.inMemory());
      final repo = _FakeRepo(store: store!);
      await pumpAsk(tester, repo);
      expect(find.text('Try asking'), findsOneWidget);
      expect(find.text('Who compiled the Vedas, and why?'), findsOneWidget);
      await tester.tap(find.text('Who compiled the Vedas, and why?'));
      await _settle(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Who compiled the Vedas, and why?');
    });

    testWidgets('sending renders the answer citations and adopts the server session', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
      final store = await tester.runAsync(() => LocalStore.inMemory());
      final repo = _FakeRepo(store: store!);
      await pumpAsk(tester, repo);
      await tester.enterText(find.byType(TextField), 'What is the highest truth?');
      await tester.tap(find.byIcon(Icons.send));
      await _settle(tester);
      expect(find.text('What is the highest truth?'), findsOneWidget); // user bubble
      expect(find.text('SB 1.1.1'), findsOneWidget); // citation chip
      expect(find.byIcon(Icons.add_comment_outlined), findsOneWidget); // new-chat action appears
    });

    testWidgets('a 429 surfaces the daily-cap message instead of a raw error', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
      final store = await tester.runAsync(() => LocalStore.inMemory());
      final repo = _FakeRepo(store: store!)..limitReached = true;
      await pumpAsk(tester, repo);
      await tester.enterText(find.byType(TextField), 'One more question?');
      await tester.tap(find.byIcon(Icons.send));
      await _settle(tester);
      expect(find.textContaining('daily'), findsNothing); // no raw English blob from the exception
      expect(find.textContaining('answer limit'), findsOneWidget);
    });
  });
}

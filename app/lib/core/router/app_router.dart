import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/admin_screen.dart';
import '../../features/bookmarks/bookmarks_screen.dart';
import '../../features/graph/entity_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/home/shell_scaffold.dart';
import '../../features/qa/ask_screen.dart';
import '../../features/qa/qa_history_screen.dart';
import '../../features/reader/chapter_screen.dart';
import '../../features/reader/verse_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/sign_in_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => ShellScaffold(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/search', builder: (_, s) => SearchScreen(initialQuery: s.uri.queryParameters['q']))]),
          StatefulShellBranch(routes: [GoRoute(path: '/bookmarks', builder: (_, __) => const BookmarksScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/ask', builder: (_, __) => const AskScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen())]),
        ],
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/read/:work/chapter/:sectionId',
        builder: (_, s) => ChapterScreen(workSlug: s.pathParameters['work']!, sectionId: s.pathParameters['sectionId']!, scrollToRef: s.uri.queryParameters['v']),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/read/:work/verse/:ref',
        builder: (_, s) => VerseScreen(workSlug: s.pathParameters['work']!, verseRef: s.pathParameters['ref']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/entity/:kind/:slug',
        builder: (_, s) => EntityScreen(kind: s.pathParameters['kind']!, slug: s.pathParameters['slug']!),
      ),
      GoRoute(parentNavigatorKey: _rootKey, path: '/ask/history', builder: (_, __) => const QaHistoryScreen()),
      GoRoute(parentNavigatorKey: _rootKey, path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(parentNavigatorKey: _rootKey, path: '/admin', builder: (_, __) => const AdminScreen()),
    ],
  );
});

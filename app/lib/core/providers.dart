import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'daily/daily.dart';
import 'db/models.dart';
import 'db/repository.dart';
import 'offline/local_store.dart';

// ------------------------------------------------------------ bootstrap
final localStoreProvider = Provider<LocalStore>((ref) => throw UnimplementedError('override in main'));
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main'));

final supabaseProvider = Provider<SupabaseClient?>((ref) => AppConfig.hasBackend ? Supabase.instance.client : null);

final repositoryProvider = Provider<Repository>((ref) {
  final repo = Repository(store: ref.watch(localStoreProvider), client: ref.watch(supabaseProvider));
  ref.listen(connectivityProvider, (_, next) => repo.setOnline(next.value ?? true));
  return repo;
});

final connectivityProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  bool up(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);
  yield up(await c.checkConnectivity());
  yield* c.onConnectivityChanged.map(up);
});

final isOnlineProvider = Provider<bool>((ref) => ref.watch(connectivityProvider).value ?? true);

// ------------------------------------------------------------ auth
final authStateProvider = StreamProvider<AuthState?>((ref) {
  final c = ref.watch(supabaseProvider);
  if (c == null) return Stream.value(null);
  return c.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider)?.auth.currentUser;
});

final userRoleProvider = FutureProvider<String>((ref) async {
  final c = ref.watch(supabaseProvider);
  final u = ref.watch(currentUserProvider);
  if (c == null || u == null) return 'reader';
  try {
    final r = await c.from('profiles').select('role').eq('id', u.id).maybeSingle();
    return (r?['role'] as String?) ?? 'reader';
  } catch (_) {
    return 'reader';
  }
});

// ------------------------------------------------------------ settings
class Settings {
  const Settings({
    this.locale = 'en',
    this.script = 'Deva',
    this.fontScale = 1.0,
    this.themeMode = 'system',
    this.showBaseText = true,
    this.showTransliteration = true,
    this.showTranslation = true,
    this.showWordMeanings = false,
    this.translationLang,
  });
  final String locale, script, themeMode;
  final double fontScale;
  final bool showBaseText, showTransliteration, showTranslation, showWordMeanings;
  final String? translationLang; // null => follow locale

  String get effectiveTranslationLang => translationLang ?? locale;

  Settings copyWith({String? locale, String? script, double? fontScale, String? themeMode, bool? showBaseText,
      bool? showTransliteration, bool? showTranslation, bool? showWordMeanings, String? translationLang, bool clearTranslationLang = false}) =>
      Settings(
        locale: locale ?? this.locale,
        script: script ?? this.script,
        fontScale: fontScale ?? this.fontScale,
        themeMode: themeMode ?? this.themeMode,
        showBaseText: showBaseText ?? this.showBaseText,
        showTransliteration: showTransliteration ?? this.showTransliteration,
        showTranslation: showTranslation ?? this.showTranslation,
        showWordMeanings: showWordMeanings ?? this.showWordMeanings,
        translationLang: clearTranslationLang ? null : (translationLang ?? this.translationLang),
      );

  static Settings load(SharedPreferences p) => Settings(
        locale: p.getString('locale') ?? 'en',
        script: p.getString('script') ?? 'Deva',
        fontScale: p.getDouble('fontScale') ?? 1.0,
        themeMode: p.getString('themeMode') ?? 'system',
        showBaseText: p.getBool('showBaseText') ?? true,
        showTransliteration: p.getBool('showTransliteration') ?? true,
        showTranslation: p.getBool('showTranslation') ?? true,
        showWordMeanings: p.getBool('showWordMeanings') ?? false,
        translationLang: p.getString('translationLang'),
      );

  Future<void> save(SharedPreferences p) async {
    await p.setString('locale', locale);
    await p.setString('script', script);
    await p.setDouble('fontScale', fontScale);
    await p.setString('themeMode', themeMode);
    await p.setBool('showBaseText', showBaseText);
    await p.setBool('showTransliteration', showTransliteration);
    await p.setBool('showTranslation', showTranslation);
    await p.setBool('showWordMeanings', showWordMeanings);
    if (translationLang == null) {
      await p.remove('translationLang');
    } else {
      await p.setString('translationLang', translationLang!);
    }
  }

  ThemeMode get materialThemeMode => switch (themeMode) { 'light' || 'sepia' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };
}

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() => Settings.load(ref.watch(prefsProvider));

  Future<void> update(Settings Function(Settings) f) async {
    state = f(state);
    await state.save(ref.read(prefsProvider));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

// ------------------------------------------------------------ content
/// The work currently shown by the reader.  It is a preference rather than a
/// compile-time constant so the same app can open any bundled/published work.
class SelectedWorkSlugNotifier extends Notifier<String> {
  @override
  String build() => ref.watch(prefsProvider).getString('selectedWorkSlug') ?? AppConfig.defaultWorkSlug;

  Future<void> select(String slug) async {
    state = slug;
    await ref.read(prefsProvider).setString('selectedWorkSlug', slug);
  }
}

final selectedWorkSlugProvider = NotifierProvider<SelectedWorkSlugNotifier, String>(SelectedWorkSlugNotifier.new);
final workSlugProvider = Provider<String>((ref) => ref.watch(selectedWorkSlugProvider));

/// The local library catalogue, populated by LocalStore.importAllAssetBundles.
/// Network-only works can still be loaded by their slug, but shipped bundles
/// are what make a work available to offline reading and search.
final bundledWorksProvider = FutureProvider<List<Toc>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  final slugs = await repo.store.bundleSlugs();
  final works = <Toc>[];
  for (final slug in slugs) {
    try {
      works.add(await repo.toc(slug));
    } catch (_) {/* ignore a stale or incomplete local entry */}
  }
  works.sort((a, b) => a.work.slug.compareTo(b.work.slug));
  return works;
});

final tocProvider = FutureProvider.family<Toc, String>((ref, slug) => ref.watch(repositoryProvider).toc(slug));
final editionsProvider = FutureProvider.family<List<Edition>, String>((ref, slug) => ref.watch(repositoryProvider).editions(slug));
final chapterProvider = FutureProvider.family<Chapter, String>((ref, sectionId) => ref.watch(repositoryProvider).chapter(sectionId));
final verseProvider = FutureProvider.family<VerseDetail, ({String work, String ref})>((ref, k) => ref.watch(repositoryProvider).verse(k.work, k.ref));
final entityProvider = FutureProvider.family<Map<String, dynamic>, ({String kind, String slug})>((ref, k) => ref.watch(repositoryProvider).entity(k.kind, k.slug));

final bookmarksProvider = FutureProvider<List<Bookmark>>((ref) => ref.watch(repositoryProvider).bookmarks());
final progressProvider = FutureProvider.family<ReadingProgress?, String>((ref, workId) => ref.watch(repositoryProvider).progress(workId));
final downloadedProvider = FutureProvider.family<bool, String>((ref, slug) => ref.watch(repositoryProvider).isDownloaded(slug));

/// How many distinct verses the reader has opened (local reading history).
final versesReadCountProvider = FutureProvider<int>((ref) async {
  ref.watch(userDataVersionProvider);
  return (await ref.watch(repositoryProvider).store.readVerseIds()).length;
});

/// Full reading history, newest first. Rows: {verse_id, verse_ref, read_at}.
final readingHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(userDataVersionProvider);
  return ref.watch(repositoryProvider).store.readingHistory();
});

/// Transient bookmark tag filter (null = all).
final bookmarkTagFilterProvider = StateProvider<String?>((_) => null);

// ------------------------------------------------------------ daily verse
/// A verse picked deterministically from the published corpus for today.
typedef DailyPick = ({Chapter chapter, Verse verse});

final dailyVerseProvider = FutureProvider<DailyPick?>((ref) async {
  final repo = ref.watch(repositoryProvider);
  final slug = ref.watch(workSlugProvider);
  try {
    final toc = await repo.toc(slug);
    final total = toc.chapters.fold<int>(0, (n, c) => n + c.verseCount);
    var idx = dailyVerseIndex(DateTime.now(), total);
    for (final ch in toc.chapters) {
      if (idx < ch.verseCount) {
        final chapter = await repo.chapter(ch.id);
        if (chapter.verses.isEmpty) return null;
        return (chapter: chapter, verse: chapter.verses[idx.clamp(0, chapter.verses.length - 1)]);
      }
      idx -= ch.verseCount;
    }
  } catch (_) {/* content not cached yet */}
  return null;
});

/// Dates (yyyy-MM-dd) on which the reader opened the daily verse; powers
/// the current streak. Persisted in prefs.
class DailyReadsNotifier extends Notifier<Set<String>> {
  static const _key = 'dailyReadDates';
  @override
  Set<String> build() => {...ref.watch(prefsProvider).getStringList(_key) ?? const <String>[]};

  Future<void> markToday() async {
    final next = {...state, isoDay(DateTime.now())};
    state = next;
    await ref.read(prefsProvider).setStringList(_key, next.toList()..sort());
  }
}

final dailyReadsProvider = NotifierProvider<DailyReadsNotifier, Set<String>>(DailyReadsNotifier.new);

/// Whether the daily-verse reminder is opted in (persisted immediately).
/// The actual system-notification scheduling lands with the store build;
/// this pref is what that wiring will read.
final dailyReminderProvider = StateProvider<bool>((ref) => ref.watch(prefsProvider).getBool('dailyReminder') ?? false);

// ------------------------------------------------------------ analytics
/// Opt-in usage analytics (default OFF). When on, the app logs content-free
/// action counts to analytics_events; see migration 0010.
final analyticsOptInProvider = StateProvider<bool>((ref) => ref.watch(prefsProvider).getBool('analyticsOptIn') ?? false);

/// Increment to invalidate user-data providers after a local write.
final userDataVersionProvider = StateProvider<int>((_) => 0);

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/locale.dart';
import 'core/offline/local_store.dart';
import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/audio/launch_chime.dart';
import 'l10n/generated/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.hasBackend) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      // ignore: deprecated_member_use  (publishableKey requires newer key format; anonKey still supported)
      anonKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
        detectSessionInUri: true,
      ),
    );
  }

  final store = await LocalStore.open();
  final prefs = await SharedPreferences.getInstance();

  // First launch: Malayalam-first — follow the device language when no UI
  // language preference has been saved yet (nested locales like ml_IN count).
  if (!prefs.containsKey('locale')) {
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    await prefs.setString('locale', firstRunLocale(null, device.languageCode));
  }

  // Seed the cache from every bundle shipped in the app.  The asset manifest
  // is discovered at runtime, so a new published work is available offline
  // without another hard-coded slug here (and without regressing the pilot).
  try {
    final imported = await store.importAllAssetBundles();
    // Bundle assets are optional in a backend-only build; retain the old
    // default fallback for development builds whose manifest is empty.
    if (imported.isEmpty && !await store.hasBundle(AppConfig.defaultWorkSlug)) {
      try {
        await store.importAssetBundle(AppConfig.defaultWorkSlug);
      } catch (_) {/* bundle optional */}
    }
  } catch (_) {
    // A missing manifest is also fine for a backend-only build.
    if (!await store.hasBundle(AppConfig.defaultWorkSlug)) {
      try {
        await store.importAssetBundle(AppConfig.defaultWorkSlug);
      } catch (_) {/* bundle optional */}
    }
  }

  // On-device diagnostics: keep a small local log of framework/platform
  // errors for Settings → Diagnostics. Never sends anything anywhere.
  FlutterError.onError = (details) {
    unawaited(store.appendErrorLog('flutter', details.exceptionAsString()));
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(store.appendErrorLog('platform', error.toString()));
    return false;
  };

  runApp(ProviderScope(
    overrides: [localStoreProvider.overrideWithValue(store), prefsProvider.overrideWithValue(prefs)],
    child: const DharmaLibraryApp(),
  ));
}

class DharmaLibraryApp extends ConsumerWidget {
  const DharmaLibraryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: Locale(settings.locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(sepia: settings.themeMode == 'sepia'),
      darkTheme: AppTheme.dark(),
      themeMode: settings.materialThemeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(settings.fontScale)),
        child: LaunchChime(child: child!),
      ),
    );
  }
}

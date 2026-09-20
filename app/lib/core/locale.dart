/// Malayalam-first locale seeding (pure, unit-tested).
///
/// On the very first launch (no saved preference) the app follows the device
/// language when it's one of the supported UI locales; otherwise it falls
/// back to English. Anything the user picks later in Settings wins — this
/// only applies when no preference exists yet.
library;

/// Supported UI locales (kept in sync with AppLocalizations.supportedLocales).
const supportedUiLocales = <String>['en', 'ml'];

String firstRunLocale(String? savedPreference, String deviceLanguageCode) {
  if (savedPreference != null && supportedUiLocales.contains(savedPreference)) return savedPreference;
  return supportedUiLocales.contains(deviceLanguageCode) ? deviceLanguageCode : 'en';
}

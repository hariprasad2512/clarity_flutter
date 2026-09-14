/// Supabase + Google OAuth configuration. Port of native `SupabaseConfig`
/// (Supabase/SupabaseConfig.swift).
///
/// Values come from `--dart-define` (or `--dart-define-from-file=.env`).
/// When missing/empty the app runs local-only: Hive + notifications keep
/// working, cloud sync is off — same contract as native, so fresh clones
/// and CI build with zero secrets.
abstract final class AppConfig {
  /// Custom URL scheme shared by OAuth callbacks on every platform.
  /// Matches native `callbackScheme` so both apps share the Supabase
  /// redirect allow-list entry.
  static const callbackScheme = 'com.harry.Clarity';
  static const callbackUrl = 'com.harry.Clarity://oauth-callback';

  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static String get supabaseUrl => _url.trim();
  static String get supabaseAnonKey => _anonKey.trim();

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      !supabaseUrl.contains('YOUR-');

  /// Reversed iOS client ID for the Google redirect scheme
  /// (`com.googleusercontent.apps.<id>`). Derived — no plist needed.
  /// Empty when no iOS client is configured.
  static String get iosReversedClientId {
    final id = iosClientId.trim();
    if (id.isEmpty || !id.contains('.')) return '';
    return id.split('.').reversed.join('.');
  }
}

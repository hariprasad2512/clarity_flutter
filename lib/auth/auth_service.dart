import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_store.dart';

/// Google sign-in + Supabase session. Port of native `AuthService`
/// (Supabase/AuthService.swift).
///
/// Two flows (same Supabase project, same `public.tasks`):
/// * Mobile (iOS/Android): native Google SDK (`google_sign_in`) → ID token
///   → `signInWithIdToken`. No browser, no plist needed (client IDs are
///   passed programmatically).
/// * Desktop + Web: Supabase-hosted OAuth (`signInWithOAuth`) → system
///   browser → custom-scheme redirect, exchanged automatically by
///   supabase_flutter's deep-link handler. No Google SDK involved, so the
///   iOS/Android client registrations don't matter here.
///
/// Session persistence + auto-refresh come free with `Supabase.initialize`.
/// Sign-out wipes the local store (native privacy parity).
class AuthService {
  // ignore: prefer_initializing_formals — field is private, param is public API.
  AuthService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _c => _client ?? Supabase.instance.client;

  bool _googleInit = false;

  Stream<AuthState> get authStates => _c.auth.onAuthStateChange;

  User? get currentUser => _c.auth.currentUser;
  String? get accountEmail => currentUser?.email;

  /// Native-SDK flow for iOS/Android. Returns the signed-in email, or null
  /// when the user cancels. Throws [AuthException] on real failures.
  Future<String?> signInWithGoogleNative() async {
    await _ensureGoogleInit();
    final account = await GoogleSignIn.instance.authenticate();
    final auth = account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw const AuthException('Google sign-in returned no ID token.');
    }
    final res = await _c.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
    return res.user?.email;
  }

  /// Browser flow for macOS/Windows/Linux/Web. Returns immediately; the
  /// result arrives via [authStates] after the redirect round-trip.
  Future<void> signInWithOAuthBrowser() async {
    final ok = await _c.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : AppConfig.callbackUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
    if (!ok) throw const AuthException('Could not open the sign-in page.');
  }

  Future<void> signOut(WidgetRef ref) async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Best-effort: native SDK may never have signed in (desktop flow).
    }
    try {
      await _c.auth.signOut();
    } catch (_) {
      // Continue to the privacy wipe regardless.
    }
    // Privacy wipe: local tasks must not linger after sign-out (native).
    await ref.read(taskListProvider.notifier).clearAll();
    await ref.read(settingsProvider.notifier).setOfflineMode(true);
  }

  Future<void> _ensureGoogleInit() async {
    if (_googleInit) return;
    final iosId =
        AppConfig.iosClientId.trim().isEmpty ? null : AppConfig.iosClientId;
    final webId =
        AppConfig.webClientId.trim().isEmpty ? null : AppConfig.webClientId;
    await GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS || Platform.isMacOS ? iosId : null,
      serverClientId: webId,
    );
    _googleInit = true;
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Current Supabase user; null when signed out. Drives the auth gate.
final authUserProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(authServiceProvider);
  if (!AppConfig.isConfigured) return Stream.value(null);
  return auth.authStates.map((s) => s.session?.user);
});

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import '../core/app_config.dart';
import '../core/app_store.dart';
import 'clarity_logo.dart';

/// Login gate. Mirrors native `AuthView`: Google sign-in first, offline
/// escape hatch second. When Supabase is unconfigured (fresh clones, CI,
/// tests) only the local explanation + offline entry show.
class AuthView extends ConsumerStatefulWidget {
  const AuthView({super.key});

  @override
  ConsumerState<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends ConsumerState<AuthView> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    ref.read(authErrorProvider.notifier).set(null);
    try {
      final auth = ref.read(authServiceProvider);
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android)) {
        await auth.signInWithGoogleNative();
      } else {
        await auth.signInWithOAuthBrowser();
      }
      // Success path: auth stream flips → _Bootstrap clears offline mode
      // and pulls. Nothing to do here.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlySignInError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Translates raw `google_sign_in` / network failures into actionable text.
  ///
  /// Play-signed builds most commonly fail with
  /// `GoogleSignInException(canceled, [16] Account reauth failed)` when the
  /// final Play App Signing SHA-1 is not registered as an Android OAuth
  /// client in Google Cloud Console. That looks like a user-cancel but is a
  /// server-side config mismatch — surface it as such instead of the raw
  /// exception.
  String _friendlySignInError(Object e) {
    final raw = e.toString();
    final lower = raw.toLowerCase();
    final isReauthFailure = lower.contains('reauth failed') ||
        lower.contains('[16]') ||
        lower.contains('sign_in_failed') ||
        lower.contains('api: 16');
    if (isReauthFailure) {
      return 'Google sign-in blocked: this build\'s Android signing key (SHA-1) '
          'is not registered for com.harry.Clarity in Google Cloud Console. '
          'Add the Play App Signing SHA-1 as an Android OAuth client, then retry. ($raw)';
    }
    if (lower.contains('canceled') && lower.contains('googlesignin')) {
      return 'Sign-in was cancelled. Tap “Sign in with Google” to try again.';
    }
    if (lower.contains('network') || lower.contains('failed to connect')) {
      return 'No network connection. Check internet and try again. ($raw)';
    }
    return 'Sign-in failed: $raw';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remoteError = ref.watch(authErrorProvider);
    final shownError = _error ?? remoteError;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ClarityMark(size: 96),
            const SizedBox(height: 8),
            Text(
              'Clarity',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'A minimal todo app.\nYour tasks, everywhere.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 20),
            if (AppConfig.isConfigured) ...[
              SizedBox(
                width: 300,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login, size: 20),
                  label: const Text('Sign in with Google',
                      style: TextStyle(fontSize: 16)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (shownError != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: 300,
                  child: Text(
                    shownError,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref
                    .read(settingsProvider.notifier)
                    .setOfflineMode(true),
                child: const Text('Continue offline'),
              ),
            ] else ...[
              Container(
                constraints: const BoxConstraints(maxWidth: 380),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Cloud sync isn't set up in this build.\n"
                  'This copy is local-first: tasks stay on this device.\n'
                  'Add Supabase + Google keys to unlock sync.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 300,
                child: FilledButton(
                  onPressed: () => ref
                      .read(settingsProvider.notifier)
                      .setOfflineMode(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Continue offline',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Local tasks always work — sync just makes them follow you.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

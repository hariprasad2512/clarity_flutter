import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_store.dart';

/// Login gate. Phase 1: Supabase is never configured, so this explains
/// setup and offers the offline entry — mirrors native `AuthView`
/// unconfigured branch. Google sign-in arrives in Phase 3.
class AuthView extends ConsumerWidget {
  const AuthView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle,
              size: 64,
              color: Colors.green,
            ),
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
            Container(
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "Cloud sync isn't set up in this build.\n"
                'Phase 1 is local-first: tasks stay on this device.\n'
                'Google sign-in arrives in Phase 3.',
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_store.dart';
import 'auth_view.dart';
import 'quick_add_dialog.dart';
import 'settings_view.dart';
import 'sidebar.dart';
import 'task_list.dart';

/// Shell: login gate when cloud is configured + signed out (Phase 3),
/// otherwise the sidebar + list workspace. Mirrors native `ContentView`.
///
/// Phase 1: Supabase is never configured, so the gate shows until the
/// user taps "Continue offline" (persisted via [SettingsNotifier]).
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _isCloudConfigured = false; // Phase 3 flips this on

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    if (_isCloudConfigured && !settings.offlineMode) {
      return const Scaffold(body: AuthView());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return _WideLayout(onQuickAdd: () => showQuickAdd(context));
        }
        return _NarrowLayout(onQuickAdd: () => showQuickAdd(context));
      },
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.onQuickAdd});
  final VoidCallback onQuickAdd;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 230,
            child: Sidebar(onQuickAdd: onQuickAdd),
          ),
          const VerticalDivider(width: 1),
          const Expanded(child: TaskList()),
        ],
      ),
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({required this.onQuickAdd});
  final VoidCallback onQuickAdd;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clarity'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const SettingsView(),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Sidebar(
            onQuickAdd: () {
              Navigator.of(context).pop();
              onQuickAdd();
            },
            onNavigate: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: const TaskList(),
      floatingActionButton: FloatingActionButton(
        onPressed: onQuickAdd,
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        tooltip: 'Quick Add',
        child: const Icon(Icons.bolt),
      ),
    );
  }
}

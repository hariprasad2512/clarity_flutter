import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import '../core/app_config.dart';
import '../core/app_store.dart';
import '../desktop/desktop.dart';
import '../desktop/quick_add_host.dart';
import 'auth_view.dart';
import 'settings_view.dart';
import 'sidebar.dart';
import 'task_composer_sheet.dart';
import 'task_list.dart';

/// Shell: sign-in gate when cloud is configured + signed out + not
/// explicitly offline, otherwise the sidebar + list workspace.
/// Mirrors native `ContentView` (login gate → workspace).
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final signedIn = AppConfig.isConfigured &&
        ref.watch(authUserProvider).maybeWhen(
              data: (u) => u != null,
              orElse: () => false,
            );
    if (AppConfig.isConfigured && !signedIn && !settings.offlineMode) {
      return const Scaffold(body: AuthView());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Desktop summons the floating Spotlight-style panel; mobile/web
        // open the bottom-sheet composer (Google-Tasks style).
        void quickAdd() {
          if (isDesktopApp) {
            ref.read(quickAddHostProvider).summon();
          } else {
            showTaskComposer(context);
          }
        }

        if (constraints.maxWidth >= 760) {
          return _WideLayout(onQuickAdd: quickAdd);
        }
        return _NarrowLayout(onQuickAdd: quickAdd);
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
        tooltip: 'New task',
        // Desktop keeps the bolt (Quick Add); mobile gets the + composer.
        child: Icon(isDesktopApp ? Icons.bolt : Icons.add),
      ),
    );
  }
}

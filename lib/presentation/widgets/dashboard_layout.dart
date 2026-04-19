import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'sidebar.dart';

/// Responsive breakpoints used across the app.
class AppBreakpoints {
  static const double compact = 600; // phone / very narrow window
  static const double medium = 900; // tablet / narrow desktop
  static const double expanded = 1200; // wide desktop
}

class DashboardLayout extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const DashboardLayout({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // ── Compact (< 600px): drawer-based navigation ──
        if (width < AppBreakpoints.compact) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Rider ERP'),
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
            ),
            drawer: Drawer(
              child: Sidebar(
                navigationShell: navigationShell,
                isCollapsed: false,
                isDrawer: true,
              ),
            ),
            body: navigationShell,
          );
        }

        // ── Medium (600–900px): collapsed rail sidebar (icons only, 72px) ──
        if (width < AppBreakpoints.medium) {
          return Scaffold(
            body: Row(
              children: [
                Sidebar(
                  navigationShell: navigationShell,
                  isCollapsed: true,
                ),
                Expanded(child: navigationShell),
              ],
            ),
          );
        }

        // ── Expanded (≥ 900px): full sidebar (260px) ──
        return Scaffold(
          body: Row(
            children: [
              Sidebar(
                navigationShell: navigationShell,
                isCollapsed: false,
              ),
              Expanded(child: navigationShell),
            ],
          ),
        );
      },
    );
  }
}

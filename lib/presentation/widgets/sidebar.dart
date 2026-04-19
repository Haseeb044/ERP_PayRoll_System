import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';

import '../../logic/auth/auth_bloc.dart';
import '../../logic/actions/action_bloc.dart';
import '../../data/models/user_model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class Sidebar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final bool isCollapsed;
  final bool isDrawer;

  const Sidebar({
    super.key,
    required this.navigationShell,
    this.isCollapsed = false,
    this.isDrawer = false,
  });

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final userRole = authState is AuthAuthenticated
        ? authState.user.role
        : UserRole.pro;

    final sidebarWidth = isCollapsed ? 72.0 : 260.0;

    return Container(
      width: sidebarWidth,
      color: AppTheme.primaryColor,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              height: isCollapsed ? 64 : 80,
              alignment: isCollapsed ? Alignment.center : Alignment.centerLeft,
              padding: isCollapsed
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 20),
              child: isCollapsed
                  ? const Icon(Icons.electric_bike, color: Colors.white, size: 28)
                  : Text(
                      'Rider ERP',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
            ),

            // Menu Items
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isCollapsed ? 8 : 12,
                ),
                child: Column(
                  crossAxisAlignment: isCollapsed
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    if (!isCollapsed) _buildSectionHeader("MENU"),
                    if (isCollapsed) const SizedBox(height: 8),
                    _buildMenuItem(
                      context,
                      index: userRole == UserRole.accountant ? 0 : 1,
                      label: "Dashboard",
                      icon: Icons.home_filled,
                    ),
                    if (userRole == UserRole.accountant) ...[
                      _buildMenuItem(
                        context,
                        index: 3,
                        label: "Riders",
                        icon: Icons.person,
                      ),
                      _buildMenuItem(
                        context,
                        index: 4,
                        label: "Payroll",
                        icon: Icons.attach_money,
                      ),
                    ] else ...[
                      _buildMenuItem(
                        context,
                        index: 2,
                        label: "Add Rider",
                        icon: Icons.person_add,
                      ),
                      _buildMenuItem(
                        context,
                        index: 5,
                        label: "Expenses",
                        icon: Icons.credit_card,
                      ),
                    ],

                    if (userRole == UserRole.accountant) ...[
                      SizedBox(height: isCollapsed ? 12 : 20),
                      if (!isCollapsed) _buildSectionHeader("FINANCIAL"),
                      if (isCollapsed)
                        const Divider(color: Colors.white24, height: 1),
                      if (isCollapsed) const SizedBox(height: 12),
                      _buildMenuItem(
                        context,
                        index: 5,
                        label: "Expenses",
                        icon: Icons.credit_card,
                      ),
                      _buildMenuItem(
                        context,
                        index: 6,
                        label: "Fines",
                        icon: Icons.receipt_long,
                        onTap: () => _navigate(context, '/fines'),
                      ),
                      _buildMenuItem(
                        context,
                        index: 7,
                        label: "Ledger",
                        icon: Icons.book,
                        onTap: () => _navigate(context, '/ledger'),
                      ),
                      _buildMenuItem(
                        context,
                        index: 8,
                        label: "Treasury",
                        icon: Icons.account_balance_wallet,
                        onTap: () => _navigate(context, '/drawers'),
                      ),
                      BlocBuilder<ActionBloc, ActionState>(
                        builder: (context, state) {
                          int count = 0;
                          if (state is ActionLoaded) {
                            count = state.actions.length;
                          }
                          return _buildMenuItem(
                            context,
                            index: 9,
                            label: "Actions",
                            icon: Icons.notifications_none,
                            onTap: () => _navigate(context, '/actions'),
                            badgeCount: count,
                          );
                        },
                      ),
                      _buildMenuItem(
                        context,
                        index: 10,
                        label: "Reports",
                        icon: Icons.bar_chart,
                        onTap: () => _navigate(context, '/reports'),
                      ),
                      _buildMenuItem(
                        context,
                        index: 11,
                        label: "Fleet and Assets",
                        icon: Icons.two_wheeler,
                        onTap: () => _navigate(context, '/assets'),
                      ),
                      if (!isCollapsed)
                        const Divider(color: Colors.white24, height: 24),
                      if (isCollapsed) const SizedBox(height: 8),
                      _buildMenuItem(
                        context,
                        index: 12,
                        label: "Audit Log",
                        icon: Icons.history,
                        onTap: () => _navigate(context, '/audit-log'),
                      ),
                      _buildMenuItem(
                        context,
                        index: 13,
                        label: "Journals",
                        icon: Icons.menu_book,
                        onTap: () => _navigate(context, '/journals'),
                      ),
                      _buildMenuItem(
                        context,
                        index: 14,
                        label: "Vendors & Suppliers",
                        icon: Icons.storefront,
                        onTap: () => _navigate(context, '/vendor-supplier-management'),
                      ),

                    ],

                    SizedBox(height: isCollapsed ? 12 : 20),
                    if (!isCollapsed) _buildSectionHeader("TOOLS"),
                    if (isCollapsed)
                      const Divider(color: Colors.white24, height: 1),
                    if (isCollapsed) const SizedBox(height: 12),
                    _buildMenuItem(
                      context,
                      index: 15,
                      label: "Profile",
                      icon: Icons.person_outline,
                      onTap: () => _navigate(context, '/profile'),
                    ),
                    _buildMenuItem(
                      context,
                      index: 99,
                      label: "Logout",
                      icon: Icons.logout,
                      onTap: () {
                        context.read<AuthBloc>().add(SignOutRequested());
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Footer — only in expanded mode
            if (!isCollapsed)
              Container(
                margin: const EdgeInsets.all(12),
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, color: AppTheme.secondaryColor, size: 8),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "System Status: Online",
                        style:
                            TextStyle(color: Colors.white70, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Navigate and close drawer if in drawer mode
  void _navigate(BuildContext context, String path) {
    if (isDrawer) Navigator.of(context).pop();
    context.go(path);
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required int index,
    required String label,
    required IconData icon,
    bool enabled = true,
    VoidCallback? onTap,
    int badgeCount = 0,
  }) {
    final isSelected =
        navigationShell.currentIndex == index && enabled && onTap == null;

    return Tooltip(
      message: isCollapsed ? label : '',
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled
              ? (onTap ??
                  () {
                    if (isDrawer) Navigator.of(context).pop();
                    navigationShell.goBranch(index);
                  })
              : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: isSelected
                ? BoxDecoration(
                    color: AppTheme.secondaryColor,
                    borderRadius: BorderRadius.circular(10),
                  )
                : null,
            padding: EdgeInsets.symmetric(
              vertical: isCollapsed ? 12 : 10,
              horizontal: isCollapsed ? 0 : 12,
            ),
            child: isCollapsed
                ? _buildCollapsedItem(icon, isSelected, enabled, badgeCount)
                : _buildExpandedItem(
                    icon, label, isSelected, enabled, badgeCount),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedItem(
      IconData icon, bool isSelected, bool enabled, int badgeCount) {
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            icon,
            color: isSelected || !enabled ? Colors.white : Colors.white70,
            size: 22,
          ),
          if (badgeCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandedItem(
    IconData icon,
    String label,
    bool isSelected,
    bool enabled,
    int badgeCount,
  ) {
    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              icon,
              color: isSelected || !enabled ? Colors.white : Colors.white70,
              size: 20,
            ),
            if (badgeCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected || !enabled
                        ? Colors.white
                        : Colors.white70,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

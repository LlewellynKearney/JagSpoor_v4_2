import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Enum identifying the three role contexts an admin/superuser can switch
/// between instantly.
enum AdminMode { hunter, outfitter, admin }

/// A compact instant mode-switcher for platform superusers/admins.
///
/// Renders a three-segment control bar that lets an admin seamlessly toggle
/// between Hunter Mode, Outfitter Mode, and the Admin / Superuser Portal
/// without signing out or re-entering credentials. Each tap issues a
/// `Navigator.pushReplacementNamed` to the corresponding named route so the
/// navigation stack is rebuilt immediately for the new role context.
///
/// [activeMode] highlights the segment the user is currently viewing so the
/// switcher reflects live state.
class AdminModeSwitcher extends StatelessWidget {
  const AdminModeSwitcher({
    super.key,
    required this.theme,
    this.activeMode = AdminMode.admin,
  });

  final ThemeController theme;
  final AdminMode activeMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.textColor.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 6, bottom: 8),
            child: Row(
              children: [
                Icon(Icons.swap_horiz_rounded,
                    color: theme.accentColor, size: 18),
                const SizedBox(width: 6),
                Text(
                  'INSTANT MODE SWITCHER',
                  style: TextStyle(
                    color: theme.accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Text(
                  'Superuser',
                  style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _segment(
                  context,
                  mode: AdminMode.hunter,
                  icon: Icons.gps_fixed_sharp,
                  label: 'Hunter',
                ),
              ),
              Expanded(
                child: _segment(
                  context,
                  mode: AdminMode.outfitter,
                  icon: Icons.business_center_sharp,
                  label: 'Outfitter',
                ),
              ),
              Expanded(
                child: _segment(
                  context,
                  mode: AdminMode.admin,
                  icon: Icons.admin_panel_settings_sharp,
                  label: 'Admin',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required AdminMode mode,
    required IconData icon,
    required String label,
  }) {
    final isActive = activeMode == mode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: isActive ? theme.accentColor : theme.backgroundColor,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: isActive ? null : () => _switchTo(context, mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive
                    ? theme.accentColor
                    : theme.textColor.withAlpha(25),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 20,
                    color: isActive ? Colors.white : theme.textColor),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? Colors.white : theme.subtitleColor,
                    fontWeight:
                        isActive ? FontWeight.bold : FontWeight.normal,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _switchTo(BuildContext context, AdminMode mode) {
    final route = switch (mode) {
      AdminMode.hunter => '/hunter_dashboard',
      AdminMode.outfitter => '/outfitter_dashboard',
      AdminMode.admin => '/admin_dashboard',
    };
    // pushReplacementNamed rebuilds the navigation stack for the new role
    // context immediately — no sign-out or credential re-entry required.
    Navigator.pushReplacementNamed(context, route);
  }
}

/// A single AppBar action button that opens the mode switcher as a modal
/// bottom sheet. Drop this onto the Hunter / Outfitter dashboards' AppBars so
/// an admin viewing those modes can jump to another role without leaving the
/// app flow.
class AdminModeSwitcherButton extends StatelessWidget {
  const AdminModeSwitcherButton({
    super.key,
    required this.theme,
    this.activeMode = AdminMode.admin,
  });

  final ThemeController theme;
  final AdminMode activeMode;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.swap_horiz_rounded),
      tooltip: 'Switch mode',
      onPressed: () => _showSheet(context),
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Switch Operational Mode',
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Instantly toggle between profiles — no sign-out required.',
              style: TextStyle(color: theme.subtitleColor, fontSize: 12),
            ),
            const SizedBox(height: 16),
            AdminModeSwitcher(theme: theme, activeMode: activeMode),
          ],
        ),
      ),
    );
  }
}


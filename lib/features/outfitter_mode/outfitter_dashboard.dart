import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_screen.dart';
import 'presentation/manual_invoice_screen.dart';
import 'presentation/slaghuis_matrix_screen.dart';

class OutfitterDashboard extends StatelessWidget {
  final ThemeController theme;

  const OutfitterDashboard({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: theme,
      builder: (context, child) {
        String conceptLabel = _getConceptLabel(theme.currentConcept);

        return Scaffold(
          backgroundColor: theme.backgroundColor,
          appBar: _buildAppBar(context, theme, conceptLabel),
          body: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.8, -0.6),
                radius: 1.2,
                colors: [
                  theme.accentColor.withAlpha(60),
                  Colors.transparent,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildStatusBanner(theme),
                  const SizedBox(height: 16),
                  Text(
                    'OUTFITTER OPERATIONS',
                    style: TextStyle(
                      color: theme.textColor.withAlpha(180),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Lodge Booking Manager
                  _buildFeatureCard(
                    icon: Icons.calendar_month_rounded,
                    title: 'Lodge Booking Manager',
                    description: 'Schedule client arrivals, room layouts, and hunting permits',
                    theme: theme,
                    onTap: () => _showComingSoon(context, 'Lodge Booking Manager', theme),
                  ),
                  const SizedBox(height: 12),

                  // Client Price Catalog & Invoicing
                  _buildFeatureCard(
                    icon: Icons.receipt_long_rounded,
                    title: 'Price Catalog & Invoicing',
                    description: 'Manage animal rates, packages, and generate client invoices',
                    theme: theme,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ManualInvoiceScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // Slaghuis Matrix
                  _buildFeatureCard(
                    icon: Icons.inventory_2_rounded,
                    title: 'Slaghuis Matrix',
                    description: 'Track carcass weights and processing status',
                    theme: theme,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SlaghuisMatrixScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // Fleet & Inventory Log
                  _buildFeatureCard(
                    icon: Icons.directions_car_rounded,
                    title: 'Fleet & Inventory Log',
                    description: 'Manage vehicles, field supplies, and radio channel sync',
                    theme: theme,
                    onTap: () => _showComingSoon(context, 'Fleet Manager', theme),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _getConceptLabel(HuntingConcept concept) {
    switch (concept) {
      case HuntingConcept.thermalGlow:
        return 'THERMAL OUTFIT';
      case HuntingConcept.walnutLuxury:
        return 'WALNUT OUTFIT';
      case HuntingConcept.neonShock:
        return 'NEON OUTFIT';
    }
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ThemeController theme, String label) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Jagspoor Outfitter',
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 1.0,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: theme.accentColor,
              fontWeight: FontWeight.w500,
              fontSize: 12,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      actions: [
        IconButton(
          icon: Icon(Icons.settings_rounded, color: theme.accentColor),
          onPressed: () => _showSettingsBottomSheet(context, theme),
        ),
        IconButton(
          icon: Icon(Icons.lock_reset_rounded, color: theme.accentColor),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => AuthScreen(themedata: theme)),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatusBanner(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.accentColor.withAlpha(40), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.villa_rounded, color: theme.accentColor, size: 32),
              const SizedBox(width: 16),
              Text(
                'LODGE GATEWAY ONLINE',
                style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Outfitter Control Center loaded. Dashboard sync active.',
            style: TextStyle(color: theme.textColor.withAlpha(160), fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required ThemeController theme,
    required VoidCallback onTap,
  }) {
    return Card(
      color: theme.cardColor,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.textColor.withAlpha(15), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        splashColor: theme.accentColor.withAlpha(30),
        highlightColor: theme.accentColor.withAlpha(10),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.accentColor.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: theme.accentColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: theme.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: theme.textColor.withAlpha(180),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: theme.textColor.withAlpha(60), size: 14),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String title, ThemeController theme) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title coming soon...'),
        backgroundColor: theme.accentColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSettingsBottomSheet(BuildContext context, ThemeController theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'OUTFITTER SETTINGS',
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: Icon(Icons.dark_mode, color: theme.accentColor),
              title: Text('Dark Mode', style: TextStyle(color: theme.textColor)),
              trailing: Switch(
                value: theme.isDarkMode,
                onChanged: (_) => theme.toggleThemeMode(),
                activeTrackColor: theme.accentColor,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

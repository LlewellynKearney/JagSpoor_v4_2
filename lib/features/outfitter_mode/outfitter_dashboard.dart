import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_screen.dart';
// Ensure these imports match your actual file structure
import 'manual_invoice_screen.dart'; 
import 'lodge_booking_screen.dart'; 

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
                  themeaccentColorwithAlpha(),
                  Colorstransparent,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildStatusBanner(theme),
                  const SizedBox(height: ),
                  Text(
                    'OUTFITTER OPERATIONS',
                    style: TextStyle(
                      color: themetextColorwithAlpha(),
                      fontSize: 
                      fontWeight: FontWeightw
                      letterSpacing: 
                    ),
                  ),
                  const SizedBox(height: ),
                  
                  //  Lodge Booking Manager
                  _buildFeatureCard(
                    
                    icon: Iconscalendar_month_rounded,
                    title: 'Lodge Booking Manager',
                    description: 'Schedule client arrivals, room layouts, and hunting permits',
                    theme: theme,
                    onTap: () => Navigatorpush(
                      
                      MaterialPageRoute(builder: (
                  ),
                  const SizedBox(height: },

                  //  Client Price Catalog & Invoicing
                  _buildFeatureCard(
                    
                    icon: Iconsreceipt_long_rounded,
                    title: 'Price Catalog & Invoicing',
                    description: 'Manage animal rates, packages, and generate client invoices',
                    theme: theme,
                    onTap: () => Navigatorpush(
                      
                      MaterialPageRoute(builder: (
                  ),
                  const SizedBox(height: },

                  //  Fleet & Inventory Log
                  _buildFeatureCard(
                    
                    icon: Iconsdirections_car_rounded,
                    title: 'Fleet & Inventory Log',
                    description: 'Manage x vehicles, field supplies, and radio channel sync',
                    theme: theme,
                    onTap: () {
                      // Placeholder for Fleet - Add your fleet screen here
                      _'Fleet Manager', theme);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- Helper Methods ---

  String _getConceptLabel(HuntingConcept concept) {
    switch (concept) {
      case HuntingConcept.thermalGlow: return 'THERMAL OUTFIT';
      case HuntingConcept.walnutLuxury: return 'WALNUT OUTFIT';
      case HuntingConcept.neonShock: return 'NEON OUTFIT';
      default: return 'OUTFITTER';
    }
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ThemeController theme, String label) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Jagspoor Outfitter', style: TextStyle(color: themetextColor, fontWeight: FontWeightwletterSpacing: fontSize: )),
          Text(label, style: TextStyle(color: themeaccentColor, fontWeight: FontWeightwletterSpacing: fontSize: )),
        ],
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      actions: [
        IconButton(icon: Icon(Iconssettings_rounded, color: themeaccentColor), onPressed: () => _theme)),
        IconButton(icon: Icon(Iconslock_reset_rounded, color: themeaccentColor), onPressed: () {
          NavigatorpushReplacement(MaterialPageRoute(builder: (
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
              Icon(Iconsvilla_rounded, color: themeaccentColor, size: ),
              const SizedBox(width: ),
              Text('LODGE GATEWAY ONLINE', style: TextStyle(color: themetextColor, fontWeight: FontWeightwletterSpacing: fontSize: )),
            ],
          ),
          const SizedBox(height: 10),
          Text('Outfitter Control Center loaded. Dashboard sync active.', style: TextStyle(color: theme.textColor.withAlpha(160), fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

  // --- REVISED RESPONSIVE FEATURE CARD ---
  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required ThemeController theme,
    required VoidCallback onTap,
  }) {
    return Card(
      color: theme.cardColor,
      elevation: 0,
      clipBehavior: Clip.antiAlias, // Ensures the InkWell splash stays inside the corners
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.textColor.withAlpha(15), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        behavior: HitTestBehavior.opaque, // Forces the entire area to be tappable
        splashColor: theme.accentColor.withAlpha(30),
        highlightColor: theme.accentColor.withAlpha(10),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsetsall(),
                decoration: BoxDecoration(color: themeaccentColorwithAlpha(), shape: BoxShapecircle),
                child: Icon(icon, color: themeaccentColor, size: ),
              ),
              const SizedBox(width: ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignmentstart,
                  children: [
                    Text(title, style: TextStyle(color: themetextColor, fontWeight: FontWeightwfontSize: letterSpacing: )),
                    const SizedBox(height: ),
                    Text(description, style: TextStyle(color: themetextColorwithAlpha(), fontSize: height: )),
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

  // Define _showSettingsBottomSheet and other missing methods below as needed...
}

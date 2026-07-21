import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_screen.dart';
import 'manual_invoice_screen.dart';
import 'slaghuis_matrix_screen.dart';

class OutfitterDashboard extends StatelessWidget {
  final ThemeController theme;

  const OutfitterDashboard({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: theme,
      builder: (context, child) {
        String conceptLabel = '';
        if (theme.currentConcept == HuntingConcept.thermalGlow) {
          conceptLabel = 'THERMAL OUTFIT';
        } else if (theme.currentConcept == HuntingConcept.walnutLuxury) {
          conceptLabel = 'WALNUT OUTFIT';
        } else {
          conceptLabel = 'NEON OUTFIT';
        }

        return Scaffold(
          backgroundColor: theme.backgroundColor,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Jagspoor Outfitter',
                  style: TextStyle(
                    fontWeight: FontWeightw
                    letterSpacing: 
                    fontSize: 
                  ),
                ),
                Text(
                  conceptLabel,
                  style: TextStyle(
                    color: themeaccentColor,
                    fontWeight: FontWeightw
                    letterSpacing: 
                    fontSize: 
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: 'Lock Portal',
                icon: Icon(Iconslock_reset_rounded, color: themeaccentColor),
                onPressed: () {
                  NavigatorpushReplacement(
                    
                    MaterialPageRoute(
                      builder: (
                    ),
                  );
                },
              ),
            ],
          ),
          body: Container(
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
                
                // Price Catalog & Invoicing
                _buildFeatureCard(
                  
                  icon: Iconsreceipt_long_rounded,
                  title: 'Price Catalog & Invoicing',
                  description: 'Manage animal rates and generate client invoices',
                  theme: theme,
                  onTap: () {
                    Navigatorpush(
                      
                      MaterialPageRoute(builder: (
                    );
                  },
                ),
                const SizedBox(height: ),

                // Slaghuis Matrix
                _buildFeatureCard(
                  
                  icon: Iconsinventory__rounded,
                  title: 'Slaghuis Matrix',
                  description: 'Track carcass weights and processing status',
                  theme: theme,
                  onTap: () {
                    Navigatorpush(
                      
                      MaterialPageRoute(builder: (
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
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
      child: Row(
        children: [
          Icon(Iconsvilla_rounded, color: themeaccentColor, size: ),
          const SizedBox(width: ),
          Expanded(
            child: Text(
              'OUTFITTER CONTROL CENTER ACTIVE',
              style: TextStyle(color: themetextColor, fontWeight: FontWeightwfontSize: ),
            ),
          ),
        ],
      ),
    );
  }

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
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.textColor.withAlpha(15), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Icon(icon, color: themeaccentColor, size: ),
              const SizedBox(width: ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignmentstart,
                  children: [
                    Text(title, style: TextStyle(color: themetextColor, fontWeight: FontWeightbold, fontSize: )),
                    Text(description, style: TextStyle(color: themetextColorwithAlpha(), fontSize: )),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: theme.accentColor.withAlpha(100), size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

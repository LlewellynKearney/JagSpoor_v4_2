import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/auth_screen.dart';
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
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    fontSize: 18,
                  ),
                ),
                Text(
                  conceptLabel,
                  style: TextStyle(
                    color: theme.accentColor,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.0,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: 'Lock Portal',
                icon: Icon(Icons.lock_reset_rounded, color: theme.accentColor),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AuthScreen(themedata: theme),
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
                
                // Price Catalog & Invoicing
                _buildFeatureCard(
                  icon: Icons.receipt_long_rounded,
                  title: 'Price Catalog & Invoicing',
                  description: 'Manage animal rates and generate client invoices',
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
          Icon(Icons.villa_rounded, color: theme.accentColor, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'OUTFITTER CONTROL CENTER ACTIVE',
              style: TextStyle(color: theme.textColor, fontWeight: FontWeight.w700, fontSize: 14),
            ),
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
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Icon(icon, color: theme.accentColor, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(description, style: TextStyle(color: theme.textColor.withAlpha(180), fontSize: 13)),
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

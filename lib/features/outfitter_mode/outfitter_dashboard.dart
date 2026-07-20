import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_screen.dart';

class OutfitterDashboard extends StatelessWidget {
  final ThemeController theme;

  const OutfitterDashboard({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: theme,
      builder: (context, child) {
        String conceptLabel = '';
        switch (theme.currentConcept) {
          case HuntingConcept.thermalGlow:
            conceptLabel = 'THERMAL OUTFIT';
            break;
          case HuntingConcept.walnutLuxury:
            conceptLabel = 'WALNUT OUTFIT';
            break;
          case HuntingConcept.neonShock:
            conceptLabel = 'NEON OUTFIT';
            break;
        }

        return Scaffold(
          backgroundColor: theme.backgroundColor,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Jagspoor Outfitter',
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    fontSize: 20,
                  ),
                ),
                Text(
                  conceptLabel,
                  style: TextStyle(
                    color: theme.accentColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: 'Visual Settings',
                icon: Icon(Icons.settings_rounded, color: theme.accentColor),
                onPressed: () => _showSettingsBottomSheet(context, theme),
              ),
              IconButton(
                tooltip: 'Lock Portal',
                icon: Icon(Icons.lock_reset_rounded, color: theme.accentColor),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AuthScreen(themedata: theme),
                    ),
                  );
                },
              ),
            ],
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.8, -0.6),
                radius: 1.2,
                colors: [
                  theme.accentColor.withAlpha(20),
                  Colors.transparent,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  // Atmospheric Status Banner
                  _buildStatusBanner(theme),
                  const SizedBox(height: 24),

                  // Feature Section Title
                  Text(
                    'OUTFITTER OPERATIONS',
                    style: TextStyle(
                      color: theme.textColor.withAlpha(140),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Operations placeholder cards
                  _buildFeatureCard(
                    context,
                    icon: Icons.calendar_month_rounded,
                    title: 'Lodge Booking Manager',
                    description: 'Schedule client arrivals, room layouts, and hunting permits.',
                    theme: theme,
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureCard(
                    context,
                    icon: Icons.people_alt_rounded,
                    title: 'Client Profile Registry',
                    description: 'Access medical records, rifle licensing, and shooting logs.',
                    theme: theme,
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureCard(
                    context,
                    icon: Icons.directions_car_rounded,
                    title: 'Fleet & Inventory Log',
                    description: 'Manage 4x4 vehicles, field supplies, and radio channel sync.',
                    theme: theme,
                  ),
                ],
              ),
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
        border: Border.all(
          color: theme.accentColor.withAlpha(40),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.accentColor.withAlpha(10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.villa_rounded, color: theme.accentColor, size: 24),
              const SizedBox(width: 10),
              Text(
                'LODGE GATEWAY ONLINE',
                style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Outfitter Control Center loaded. Dashboard widgets and analytics logs are synchronizing.',
            style: TextStyle(
              color: theme.textColor.withAlpha(160),
              fontSize: 13,
              height: 1.4,
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
  }) {
    return Card(
      color: theme.cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.textColor.withAlpha(15),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.construction_rounded, color: theme.backgroundColor, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    '$title coming soon...',
                    style: TextStyle(
                      color: theme.backgroundColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              backgroundColor: theme.accentColor,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.accentColor.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: theme.accentColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.textColor.withAlpha(140),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Align(
                alignment: Alignment.center,
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: theme.accentColor.withAlpha(128),
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsBottomSheet(BuildContext context, ThemeController theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(128),
      builder: (context) {
        return AnimatedBuilder(
          animation: theme,
          builder: (context, _) {
            return ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.all(28.0),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    border: Border.all(
                      color: theme.accentColor.withAlpha(30),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'HUD VISUAL SETTINGS',
                            style: TextStyle(
                              color: theme.textColor,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                              fontSize: 14,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded, color: theme.textColor.withAlpha(150)),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const Divider(height: 16, thickness: 0.5),
                      const SizedBox(height: 12),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                theme.isDarkMode ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                                color: theme.accentColor,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Dark Mode Ambient',
                                style: TextStyle(
                                  color: theme.textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          Switch.adaptive(
                            value: theme.isDarkMode,
                            activeThumbColor: theme.accentColor,
                            onChanged: (val) => theme.toggleThemeMode(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      
                      Text(
                        'HUD COLOR CONCEPT',
                        style: TextStyle(
                          color: theme.textColor.withAlpha(128),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      
                      Row(
                        children: HuntingConcept.values.map((concept) {
                          final isSelected = theme.currentConcept == concept;
                          String name = '';
                          IconData icon = Icons.circle;

                          switch (concept) {
                            case HuntingConcept.thermalGlow:
                              name = 'Thermal';
                              icon = Icons.thermostat_rounded;
                              break;
                            case HuntingConcept.walnutLuxury:
                              name = 'Walnut';
                              icon = Icons.brush_rounded;
                              break;
                            case HuntingConcept.neonShock:
                              name = 'Neon';
                              icon = Icons.bolt_rounded;
                              break;
                          }

                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: InkWell(
                                onTap: () => theme.setConcept(concept),
                                borderRadius: BorderRadius.circular(10),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? theme.accentColor.withAlpha(31)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected ? theme.accentColor : theme.textColor.withAlpha(20),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        icon,
                                        size: 18,
                                        color: isSelected ? theme.accentColor : theme.textColor.withAlpha(100),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          color: isSelected ? theme.textColor : theme.textColor.withAlpha(150),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

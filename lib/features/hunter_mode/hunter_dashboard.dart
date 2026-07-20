import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/firearm_safe_screen.dart';
import 'package:jagspoor/screens/animal_list_screen.dart';
import 'trophy_room_screen.dart';
import 'weather/weather_tracker_screen.dart';
import 'package:jagspoor/features/track/presentation/spoor_detection_hud_screen.dart';
import 'hunter_profile_screen.dart';
import 'package:jagspoor/features/game_guide/presentation/field_estimate_screen.dart';
import 'package:jagspoor/features/ballistics/presentation/ballistic_calc_screen.dart';
import 'package:jagspoor/features/ballistics/presentation/ammunition_screen.dart';

class HunterDashboard extends StatefulWidget {
  final ThemeController theme;
  const HunterDashboard({super.key, required this.theme});

  @override
  State<HunterDashboard> createState() => _HunterDashboardState();
}

class _HunterDashboardState extends State<HunterDashboard> {
  static const _favoritePrefKey = 'favorited_dashboard_features';
  final List<String> favoriteIds = [];

  @override
  void initState() {
    super.initState();
    _loadFavoriteIds();
  }

  Future<void> _loadFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      favoriteIds.clear();
      favoriteIds.addAll(prefs.getStringList(_favoritePrefKey) ?? <String>[]);
    });
  }

  Future<void> _saveFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritePrefKey, favoriteIds);
  }

  void _toggleFavorite(String featureId) {
    setState(() {
      if (favoriteIds.contains(featureId)) {
        favoriteIds.remove(featureId);
      } else {
        favoriteIds.add(featureId);
      }
      _saveFavoriteIds();
    });
  }

  int _sortFeatures(DashboardFeature a, DashboardFeature b) {
    final bool aFav = favoriteIds.contains(a.id);
    final bool bFav = favoriteIds.contains(b.id);
    if (aFav && !bFav) return -1;
    if (!aFav && bFav) return 1;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final List<DashboardFeature> features = [
      DashboardFeature(
        id: 'weather',
        icon: Icons.wb_sunny_rounded,
        title: 'Weather & Wind Tracker',
        description: 'Live wind direction and solunar cycles.',
        onTap: (context, theme) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WeatherTrackerScreen(theme: theme),
          ),
        ),
      ),
      DashboardFeature(
        id: 'spoor_tracker',
        icon: Icons.visibility_rounded,
        title: 'Track (Spoor) Identifier',
        description: 'Scan footprints with AI matching and GPS logging.',
        onTap: (context, theme) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SpoorDetectionHudScreen(theme: theme),
          ),
        ),
      ),
      DashboardFeature(
        id: 'game_guide',
        icon: Icons.eco_rounded,
        title: 'SA Game Guide',
        description: 'Species profiles and photos — works offline.',
        onTap: (context, theme) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AnimalListScreen(theme: theme),
          ),
        ),
      ),
      DashboardFeature(
        id: 'firearm_safe',
        icon: Icons.security_rounded,
        title: '🔒 Digital Firearm Safe',
        description: 'Manage rifle licenses and barrel twist profiles.',
        onTap: (context, theme) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FirearmSafeScreen(theme: theme),
          ),
        ),
      ),
      DashboardFeature(
        id: 'ammunition',
        icon: Icons.grain_rounded,
        title: 'Ammunition Manager',
        description: 'Manage factory ammunition and custom loads.',
        onTap: (context, theme) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AmmunitionScreen(theme: theme),
          ),
        ),
      ),
      DashboardFeature(
        id: 'trophy_room',
        icon: Icons.menu_book_rounded,
        title: 'Digital Trophy Room',
        description: 'Log sightings and shot placements.',
        onTap: (context, theme) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TrophyRoomScreen(theme: theme),
          ),
        ),
      ),
      DashboardFeature(
        id: 'field_estimate',
        icon: Icons.remove_red_eye_rounded,
        title: 'Field Estimate Verification',
        description: 'Estimate horn length from visual ear-to-horn ratios.',
        onTap: (context, theme) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FieldEstimateScreen(theme: theme),
          ),
        ),
      ),
      DashboardFeature(
        id: 'ballistic_calculator',
        icon: Icons.calculate_rounded,
        title: 'Ballistic Calculator',
        description: 'Quick bullet drop and velocity tracking.',
        onTap: (context, theme) => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const BallisticCalcScreen()),
        ),
      ),
    ];

    features.sort(_sortFeatures);

    return AnimatedBuilder(
      animation: theme,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: theme.backgroundColor,
          appBar: AppBar(
            title: Text(
              'Jagspoor: Hunter Mode',
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: theme.backgroundColor,
            iconTheme: IconThemeData(color: theme.accentColor),
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(Icons.settings_rounded, color: theme.accentColor),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HunterProfileScreen(theme: theme),
                  ),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              Card(
                color: theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: theme.accentColor.withValues(alpha: 0.2),
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    Icons.radar_rounded,
                    color: theme.accentColor,
                    size: 28,
                  ),
                  title: Text(
                    'SYSTEM ACTIVE',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.textColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                  subtitle: Text(
                    'GPS Link Established. All tracking modules ready.',
                    style: TextStyle(color: theme.subtitleColor, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'TACTICAL MODULES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.subtitleColor,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < features.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                _buildCard(context, theme, features[i]),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    ThemeController theme,
    DashboardFeature feature,
  ) {
    final bool isFavorite = favoriteIds.contains(feature.id);
    return Card(
      color: theme.cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Stack(
        children: [
          InkWell(
            onTap: () => feature.onTap(context, widget.theme),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Icon(feature.icon, color: theme.accentColor, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feature.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          feature.description,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.subtitleColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 12,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                splashRadius: 24,
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? theme.accentColor : theme.subtitleColor,
                ),
                onPressed: () => _toggleFavorite(feature.id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardFeature {
  final String id;
  final IconData icon;
  final String title;
  final String description;
  final void Function(BuildContext, ThemeController) onTap;

  DashboardFeature({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });
}

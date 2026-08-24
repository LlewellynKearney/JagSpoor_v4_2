import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/features/hunter_mode/firearm_safe_screen.dart';
import 'package:jagspoor/screens/animal_list_screen.dart';
import 'trophy_room_screen.dart';
import 'weather/weather_tracker_screen.dart';
import 'package:jagspoor/features/track/presentation/spoor_detection_hud_screen.dart';
import 'hunter_profile_screen.dart';
import 'services/hunter_profile_completeness.dart';
import 'package:jagspoor/features/game_guide/presentation/field_estimate_screen.dart';
import 'package:jagspoor/features/ballistics/presentation/ballistic_calc_screen.dart';
import 'package:jagspoor/features/ballistics/presentation/ammunition_screen.dart';
import 'package:jagspoor/features/ballistics/presentation/scope_tools_bottom_sheet.dart';
import 'presentation/bug_report_modal.dart';
import 'presentation/feature_suggestion_modal.dart';
import 'presentation/saps_tracker_screen.dart';
import 'screens/mesh_radar_screen.dart';
import 'screens/carcass_matrix_screen.dart';
import 'screens/offline_navigation_screen.dart';
import 'screens/shot_group_analyzer_screen.dart';
import 'screens/hunter_package_marketplace_screen.dart';
import 'screens/hunter_trophy_browser_screen.dart';
import 'screens/custom_package_farm_selection_screen.dart';
import '../admin/services/admin_auth_guard.dart';
import '../admin/services/usage_analytics_service.dart';
import '../admin/widgets/admin_mode_switcher.dart';
import '../shared/widgets/hunter_media_card.dart';
import '../shared/widgets/jagspoor_dashboard_header.dart';
import '../subscription/subscription_screen.dart';
import 'widgets/network_diagnostic_hud.dart';
import 'widgets/hunter_scaffold.dart';
import 'widgets/dashboard_feature_folder.dart';

class HunterDashboard extends StatefulWidget {
  final ThemeController theme;
  const HunterDashboard({super.key, required this.theme});

  @override
  State<HunterDashboard> createState() => _HunterDashboardState();
}

class _HunterDashboardState extends State<HunterDashboard> {
  static const _favoritePrefKey = 'favorited_dashboard_features';
  final List<String> favoriteIds = [];
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadFavoriteIds();
    _resolveAdmin();
    _enforceProfileOnboarding();
    UsageAnalyticsService.instance.trackScreenView('Hunter Dashboard');
  }

  /// Defense-in-depth onboarding gate: if a hunter somehow reaches the
  /// dashboard with an incomplete mandatory profile (e.g. a stale route
  /// stack, a deep link, or a profile edit that cleared a mandatory field),
  /// redirect them to the Hunter Profile screen to complete onboarding
  /// before they can use any main app features. Admins are not gated.
  ///
  /// Best-effort: a Firestore/auth failure (offline, or an uninitialized
  /// Firebase app in a cold-launch/test environment) is swallowed so the
  /// dashboard always renders instead of crashing.
  Future<void> _enforceProfileOnboarding() async {
    try {
      final isAdmin = await AdminAuthGuard.instance.isCurrentUserAdmin();
      if (isAdmin) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final status =
          await HunterProfileCompleteness.instance.statusFor(uid);
      if (!status.isComplete && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => HunterProfileScreen(theme: widget.theme),
          ),
          (_) => false,
        );
      }
    } catch (_) {
      // Auth/Firestore unavailable (offline or test env) — do not gate.
    }
  }

  /// Resolves admin flag; wrapped in try/catch so an unavailable
  /// auth/Firestore (offline or test env) never hangs or crashes the
  /// dashboard — it simply renders with a non-admin flag.
  Future<void> _resolveAdmin() async {
    bool admin = false;
    try {
      admin = await AdminAuthGuard.instance.isCurrentUserAdmin();
    } catch (_) {
      admin = false;
    }
    if (!mounted) return;
    setState(() => _isAdmin = admin);
  }

  Future<void> _loadFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
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

  /// A single frosted circular header action (the shared rich-media chip
  /// used across both portal dashboards).
  Widget _headerAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return HunterFrostedCircleButton(
      icon: icon,
      iconColor: kHunterMediaAmber,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    // HUNTER MODE - Field & Tracking Tools
    final List<DashboardFeature> hunterFeatures = [
      DashboardFeature(
        id: 'weather',
        icon: Icons.wb_sunny_rounded,
        title: 'Weather & Wind Tracker',
        description: 'Live wind direction and solunar cycles.',
        onTap:
            (context, theme) => Navigator.push(
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
        onTap:
            (context, theme) => Navigator.push(
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
        onTap:
            (context, theme) => Navigator.push(
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
        onTap:
            (context, theme) => Navigator.push(
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
        onTap:
            (context, theme) => Navigator.push(
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
        onTap:
            (context, theme) => Navigator.push(
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
        onTap:
            (context, theme) => Navigator.push(
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
        onTap:
            (context, theme) => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const BallisticCalcScreen(),
              ),
            ),
      ),
      DashboardFeature(
        id: 'scope_settings',
        icon: Icons.center_focus_strong_rounded,
        title: '🎯 Scope Settings & Tools',
        description: 'Configure reticle, turrets, and parallax settings.',
        onTap: (context, theme) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (sheetContext) => const ScopeToolsBottomSheet(),
          );
        },
      ),
      // REMOVED: ScopeCalibrationHud DashboardFeature(
      //   id: 'scope_calibration_hud',
      //   icon: Icons.gps_fixed,
      //   title: '🎯 Rifle Scope Ballistic HUD',
      //   description: 'Advanced turret dial calibration with MOA/MRAD click calculator and rangefinder integration.',
      //   onTap: (context, theme) => Navigator.push(
      //     context,
      //     MaterialPageRoute(builder: (context) => ScopeCalibrationScreen(theme: theme)),
      //   ),
      // ),
      DashboardFeature(
        id: 'saps_tracker',
        icon: Icons.badge_rounded,
        title: '💳 SAPS Tracker & Competency',
        description:
            'Monitor firearm license and competency application statuses via daily automated scrapers.',
        onTap: (context, theme) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SapsTrackerScreen()),
          );
        },
      ),
      DashboardFeature(
        id: 'shot_group_analyzer',
        icon: Icons.center_focus_strong_rounded,
        title: '🎯 Shot Group Target Analyzer',
        description:
            'Capture a target, calibrate scale against a coin or 1-inch grid, '
            'and compute true extreme spread, mean radius & center of impact in MOA/MIL.',
        onTap: (context, theme) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShotGroupAnalyzerScreen(theme: theme),
          ),
        ),
      ),
      DashboardFeature(
        id: 'offgrid_mesh_sync',
        icon: Icons.radar_rounded,
        title: '📡 Off-Grid Mesh Sync',
        description:
            'P2P Bluetooth telemetry and team radar without cell service.',
        onTap:
            (context, theme) => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const MeshRadarScreen()),
            ),
      ),
      DashboardFeature(
        id: 'carcass_matrix',
        icon: Icons.inventory_2_rounded,
        title: '🥩 Slaughterhouse Carcass Matrix',
        description:
            'Track hanging game, cold storage positions, and field-to-hanging weight ratios.',
        onTap:
            (context, theme) => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CarcassMatrixScreen(theme: theme),
              ),
            ),
      ),
      DashboardFeature(
        id: 'offline_map',
        icon: Icons.map_rounded,
        title: '🗺️ Off-Grid Topographic Map',
        description:
            'OpenTopoMap contours cached for complete offline navigation in the field.',
        onTap:
            (context, theme) => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => OfflineNavigationScreen(theme: theme),
              ),
            ),
      ),
      DashboardFeature(
        id: 'subscription',
        icon: Icons.workspace_premium_rounded,
        title: '💎 Subscription',
        description:
            'Manage your plan — 30-day free trial, then R19.99/month.',
        onTap:
            (context, theme) => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SubscriptionScreen(theme: theme),
              ),
            ),
      ),
      DashboardFeature(
        id: 'report_bug',
        icon: Icons.bug_report_rounded,
        title: '🪲 Report Bug',
        description:
            'Encountered a glitch in the bush? Log to cloud and alert support.',
        onTap: (context, theme) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (sheetContext) => const BugReportModal(),
          );
        },
      ),
      DashboardFeature(
        id: 'suggest_feature',
        icon: Icons.lightbulb_outline_rounded,
        title: '💡 Suggest New Feature',
        description:
            'Have an idea for a tactical tracking tool? Inform our engineering team.',
        onTap: (context, theme) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (sheetContext) => const FeatureSuggestionModal(),
          );
        },
      ),
    ];

    // MARKETPLACE - Consumer Booking Actions
    final List<DashboardFeature> marketplaceFeatures = [
      DashboardFeature(
        id: 'marketplace',
        icon: Icons.shopping_bag_rounded,
        title: '🎯 Package Marketplace',
        description:
            'Browse and book hunting packages from verified outfitters.',
        onTap:
            (context, theme) => Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (context) => HunterPackageMarketplaceScreen(theme: theme),
              ),
            ),
      ),
      DashboardFeature(
        id: 'trophy_browser',
        icon: Icons.pets_rounded,
        title: '🦌 Trophy Registry & Booking',
        description:
            'View trophy species from outfitters and add to your booking log.',
        onTap:
            (context, theme) => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => HunterTrophyBrowserScreen(theme: theme),
              ),
            ),
      ),
      DashboardFeature(
        id: 'custom_package_builder',
        icon: Icons.construction_rounded,
        title: '🦌 Custom Package Builder',
        description:
            'Build a custom hunting package from an outfitter farm\'s active '
            'price list — pick dates, party size, species & lodging, then '
            'request it from the outfitter.',
        onTap:
            (context, theme) => Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (context) => CustomPackageFarmSelectionScreen(theme: theme),
              ),
            ),
      ),
    ];

    // Combine all features; the three collapsible folders pull their members
    // by id, and the remaining features render flat below (favorites first).
    final allFeatures = [...hunterFeatures, ...marketplaceFeatures];
    final byId = {for (final f in allFeatures) f.id: f};

    const folderFeatureIds = <String>{
      'firearm_safe', 'ammunition',
      'marketplace', 'custom_package_builder', 'trophy_browser',
      'ballistic_calculator', 'field_estimate', 'spoor_tracker',
      'scope_settings', 'shot_group_analyzer',
    };
    final remainingFeatures =
        allFeatures.where((f) => !folderFeatureIds.contains(f.id)).toList()
          ..sort(_sortFeatures);

    Widget buildFolder({
      required IconData icon,
      required String title,
      required String subtitle,
      required List<String> ids,
    }) {
      return DashboardFeatureFolder(
        theme: theme,
        icon: icon,
        title: title,
        subtitle: subtitle,
        children: [
          for (final id in ids)
            _buildCard(context, theme, byId[id]!, compact: true),
        ],
      );
    }

    return AnimatedBuilder(
      animation: theme,
      builder: (context, _) {
        return HunterScaffold(
          theme: theme,
          appBar: JagSpoorDashboardHeader(
            modeBadgeText: 'HUNTER MODE',
            actionButtons: [
              if (_isAdmin) ...[
                AdminModeSwitcherButton(
                  theme: theme,
                  activeMode: AdminMode.hunter,
                  buttonBuilder: (icon, tooltip, onPressed) =>
                      _headerAction(
                    icon: icon,
                    tooltip: tooltip,
                    onPressed: onPressed,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              _headerAction(
                tooltip: theme.isDarkMode
                    ? 'Switch to Day Mode'
                    : 'Switch to Night Mode',
                icon: theme.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                onPressed: () => theme.toggleThemeMode(),
              ),
              const SizedBox(width: 8),
              _headerAction(
                tooltip: 'Hunter Profile',
                icon: Icons.settings_rounded,
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
              MediaQuery.of(context).padding.top + kToolbarHeight + 8,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              // 🎯 Network Diagnostic HUD Status Bar
              const NetworkDiagnosticHud(),
              const SizedBox(height: 16),
              Card(
                color: HunterUi.cardColor(theme),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: HunterUi.cardBorderColor(theme),
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
                      color: HunterUi.titleColor(theme),
                      letterSpacing: 1.2,
                    ),
                  ),
                  subtitle: Text(
                    'GPS Link Established. All tracking modules ready.',
                    style: TextStyle(
                        color: HunterUi.subtitleColor(theme), fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'TACTICAL MODULES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: HunterUi.subtitleColor(theme),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              buildFolder(
                icon: Icons.gps_fixed_rounded,
                title: 'All things guns',
                subtitle: 'Firearm safe & ammunition management',
                ids: const ['firearm_safe', 'ammunition'],
              ),
              const SizedBox(height: 16),
              buildFolder(
                icon: Icons.storefront_rounded,
                title: 'Market place',
                subtitle: 'Packages, custom builds & trophy bookings',
                ids: const [
                  'marketplace',
                  'custom_package_builder',
                  'trophy_browser',
                ],
              ),
              const SizedBox(height: 16),
              buildFolder(
                icon: Icons.handyman_rounded,
                title: 'Tools',
                subtitle: 'Ballistics, field estimates & tracking utilities',
                ids: const [
                  'ballistic_calculator',
                  'field_estimate',
                  'spoor_tracker',
                  'scope_settings',
                  'shot_group_analyzer',
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'MORE MODULES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: HunterUi.subtitleColor(theme),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < remainingFeatures.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                _buildCard(context, theme, remainingFeatures[i]),
              ],
              const CopyrightFooter(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    ThemeController theme,
    DashboardFeature feature, {
    bool compact = false,
  }) {
    final bool isFavorite = favoriteIds.contains(feature.id);
    return Card(
      color: HunterUi.cardColor(theme),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: HunterUi.cardBorderColor(theme)),
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: () {
              UsageAnalyticsService.instance
                  .trackFeatureUsage(feature.title);
              feature.onTap(context, widget.theme);
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(compact ? 14.0 : 20.0),
              child: Row(
                children: [
                  Icon(feature.icon,
                      color: theme.accentColor, size: compact ? 22 : 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feature.title,
                          style: TextStyle(
                            fontSize: compact ? 15 : 16,
                            fontWeight: FontWeight.bold,
                            color: HunterUi.titleColor(theme),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          feature.description,
                          style: TextStyle(
                            fontSize: 13,
                            color: HunterUi.subtitleColor(theme),
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
                  color: isFavorite
                      ? theme.accentColor
                      : HunterUi.subtitleColor(theme),
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

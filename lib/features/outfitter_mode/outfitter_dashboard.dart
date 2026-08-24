import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:jagspoor/shared/widgets/app_info_modal.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/copyright_footer.dart';
import '../../core/widgets/safe_bottom_inset.dart';
import '../auth/auth_screen.dart';
import '../auth/change_password_dialog.dart';
import '../hunter_mode/screens/outfitter_enterprise_panel_screen.dart';
import '../hunter_mode/screens/outfitter_trophy_stock_screen.dart';
import '../hunter_mode/screens/outfitter_package_creator_screen.dart';
import '../hunter_mode/screens/outfitter_package_manager_screen.dart';
import '../hunter_mode/screens/outfitter_price_list_screen.dart';
import '../hunter_mode/screens/outfitter_booking_dashboard_screen.dart';
import '../hunter_mode/screens/outfitter_revenue_screen.dart';
import '../hunter_mode/screens/venison_permit_list_screen.dart';
import '../hunter_mode/services/user_role_resolver.dart';
import '../hunter_mode/services/feedback_firebase_service.dart';
import '../hunter_mode/presentation/bug_report_modal.dart';
import '../hunter_mode/presentation/feature_suggestion_modal.dart';
import '../admin/services/admin_auth_guard.dart';
import '../admin/services/usage_analytics_service.dart';
import '../admin/widgets/admin_mode_switcher.dart';
import '../subscription/subscription_screen.dart';
import 'widgets/outfitter_scaffold.dart';

class OutfitterDashboard extends StatefulWidget {
  final ThemeController theme;

  /// Bushveld landscape shown full-screen behind the dashboard content.
  /// Alias of the shared [OutfitterBushveldBackground] constant, kept so any
  /// consumer referencing the dashboard-level name (tests) still compiles.
  static const String kBackgroundImageUrl =
      OutfitterBushveldBackground.kBackgroundImageUrl;

  /// Local asset fallback when the network image is unavailable (offline /
  /// off-grid). Alias of the shared constant.
  static const String kBackgroundFallbackAsset =
      OutfitterBushveldBackground.kBackgroundFallbackAsset;

  const OutfitterDashboard({super.key, required this.theme});

  @override
  State<OutfitterDashboard> createState() => _OutfitterDashboardState();
}

class _OutfitterDashboardState extends State<OutfitterDashboard> {
  bool _isManager = false;
  String? _assignedFarmId;
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _resolveUserRole();
    UsageAnalyticsService.instance
        .trackScreenView('Outfitter Dashboard');
  }

  Future<void> _resolveUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await UserRoleResolver.instance.resolveCurrentUserRole(user.uid);
        final admin = await AdminAuthGuard.instance.isCurrentUserAdmin();
        if (!mounted) return;
        setState(() {
          _isManager = UserRoleResolver.instance.isManager;
          _assignedFarmId = UserRoleResolver.instance.assignedFarmId;
          _isAdmin = admin;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      // Firebase not yet initialized (cold-launch race / widget test) — the
      // dashboard still renders with default (non-manager) role flags; the
      // route guard upstream already vetted the caller's role.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.theme,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: widget.theme.backgroundColor,
          // Full-bleed the bushveld background + scrim behind the (transparent)
          // AppBar; the content's top inset is added to the ListView padding.
          extendBodyBehindAppBar: true,
          appBar: _buildAppBar(context, widget.theme),
          body: Stack(
            fit: StackFit.expand,
            children: [
              OutfitterBushveldBackground.backgroundImage(
                fallbackColor: widget.theme.backgroundColor,
              ),
              OutfitterBushveldBackground.scrim(),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.8, -0.6),
                        radius: 1.2,
                        colors: [
                          widget.theme.accentColor.withAlpha(60),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Center(
                      // Constrain the feature-card column on wide / tablet
                      // screens so cards don't stretch edge-to-edge (smooth
                      // scrolling + readable line lengths across mobile ratios).
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 560,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20.0,
                          ),
                          child: ListView(
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.only(
                                top: MediaQuery.of(context).padding.top +
                                    kToolbarHeight +
                                    12,
                                bottom: SafeBottomInset.of(context)),
                            children: [
                              _buildStatusBanner(widget.theme),
                              const SizedBox(height: 16),
                          // Section label wrapped to avoid overflow on narrow
                          // screens (the manager label is long + tracked-out).
                          Text(
                            _isManager
                                ? 'FARM MANAGEMENT HUD (MANAGER ACCESS)'
                                : 'OUTFITTER OPERATIONS',
                            softWrap: true,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              // Dark espresso in Day mode (high-contrast on
                              // the bright photo), white in Night mode over
                              // the dark scrim.
                              color: widget.theme.isDarkMode
                                  ? Colors.white.withAlpha(210)
                                  : OutfitterUi.lightTitle,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Manage Farms & Managers - HIDDEN for managers
                          if (!_isManager) ...[
                            _buildFeatureCard(
                              icon: Icons.landscape_rounded,
                              title: 'Manage Farms & Managers',
                              description:
                                  'Register farms, concessions, and assign managers to your properties.',
                              theme: widget.theme,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => OutfitterEnterprisePanelScreen(
                                          theme: widget.theme,
                                        ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Trophy Stock Inventory
                          _buildFeatureCard(
                            icon: Icons.pets_rounded,
                            title: 'Trophy Stock Inventory',
                            description:
                                _isManager
                                    ? 'Manage trophy availability for your assigned farm.'
                                    : 'Load trophy species availability and pricing per farm location.',
                            theme: widget.theme,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => OutfitterTrophyStockScreen(
                                        theme: widget.theme,
                                      ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),

                          // Publish Hunting Package - Hidden for managers
                          if (!_isManager) ...[
                            _buildFeatureCard(
                              icon: Icons.storefront_rounded,
                              title: 'Publish Hunting Package',
                              description:
                                  'Create and list hunting packages with pricing and inclusions.',
                              theme: widget.theme,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => OutfitterPackageCreatorScreen(
                                          theme: widget.theme,
                                        ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),

                            // Manage My Packages - lifecycle + deletion
                            _buildFeatureCard(
                              icon: Icons.inventory_2_rounded,
                              title: 'Manage My Packages',
                              description:
                                  'Activate, draft, archive, edit, or delete your published packages.',
                              theme: widget.theme,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => OutfitterPackageManagerScreen(
                                      theme: widget.theme,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),

                            // Price List - per-farm game species pricing
                            _buildFeatureCard(
                              icon: Icons.request_quote_rounded,
                              title: 'Price List',
                              description:
                                  'Manage per-farm game species pricing '
                                  '(qty + ZAR) for your market listings.',
                              theme: widget.theme,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => OutfitterPriceListScreen(
                                      theme: widget.theme,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Incoming Booking Requests
                          _buildFeatureCard(
                            icon: Icons.assignment_rounded,
                            title: 'Incoming Booking Requests',
                            description:
                                'Review and approve/decline hunter booking transactions.',
                            theme: widget.theme,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => OutfitterBookingDashboardScreen(
                                        theme: widget.theme,
                                      ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),

                          // Financial Revenue Summary - HIDDEN for managers
                          if (!_isManager) ...[
                            _buildFeatureCard(
                              icon: Icons.bar_chart_rounded,
                              title: 'Financial Revenue Summary',
                              description:
                                  'View gross earnings and net disbursed revenue.',
                              theme: widget.theme,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => OutfitterRevenueScreen(
                                          theme: widget.theme,
                                        ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),

                          // Subscription — PayFast billing management.
                          _buildFeatureCard(
                            icon: Icons.workspace_premium_rounded,
                            title: 'Subscription',
                            description:
                                'Manage your plan — 30-day free trial, then R199.99/month.',
                            theme: widget.theme,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SubscriptionScreen(
                                    theme: widget.theme,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),

                          // Venison Permit Log & Manager — single consolidated
                          // entry for issuing + viewing venison transport
                          // permits. The standalone "Issue Game Transport
                          // Permit" screen and the direct form entry have been
                          // removed; creation now happens via the list screen's
                          // "New Permit" action.
                          _buildFeatureCard(
                            icon: Icons.list_alt_rounded,
                            title: 'Permit Log & Manager',
                            description:
                                'Issue, view, search, and manage venison transport permits in one place.',
                            theme: widget.theme,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VenisonPermitListScreen(
                                    theme: widget.theme,
                                    isOutfitterMode: true,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                          const SizedBox(height: 12),

                          // Report Bug — the shared feedback pipeline (same
                          // modal + Firestore collections as Hunter Mode),
                          // tagged with the 'Outfitter' mode. Visible to
                          // managers too (feedback is universal).
                          _buildFeatureCard(
                            icon: Icons.bug_report_rounded,
                            title: 'Report Bug',
                            description:
                                'Encountered a glitch? Log it to support with device diagnostics.',
                            theme: widget.theme,
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (sheetContext) =>
                                    const BugReportModal(
                                  mode: FeedbackMode.outfitter,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),

                          // Suggest New Feature — the same shared submission
                          // pipeline, tagged with the 'Outfitter' mode.
                          _buildFeatureCard(
                            icon: Icons.lightbulb_outline_rounded,
                            title: 'Suggest New Feature',
                            description:
                                'Have an idea to improve the outfitter toolkit? Inform our engineering team.',
                            theme: widget.theme,
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (sheetContext) =>
                                    const FeatureSuggestionModal(
                                  mode: FeedbackMode.outfitter,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          const CopyrightFooter(),
                        ],
                      ),
                        ), // Padding
                      ), // ConstrainedBox
                    ), // Center
                  ), // Container
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeController theme,
  ) {
    return AppBar(
      title: Text(
        _isManager ? 'Farm Manager' : 'JagSpoor Outfitter',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          // Dark espresso in Day mode (readable on the bright sunrise
          // region), white in Night mode over the dark scrim.
          color: OutfitterUi.titleColor(theme),
          fontWeight: FontWeight.w800,
          fontSize: 24,
          letterSpacing: 1.2,
        ),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      actions: [
        // Universal help: opens the theme-aware info modal for this screen.
        OutfitterActionChip(
          icon: Icons.info_outline_rounded,
          tooltip: 'Screen info',
          iconColor: theme.accentColor,
          onPressed: () =>
              showAppInfoModal(context, AppScreenHelpScripts.outfitterDashboard),
        ),
        if (_isAdmin)
          AdminModeSwitcherButton(
            theme: theme,
            activeMode: AdminMode.outfitter,
          ),
        // High-contrast chip keeps the icon readable against the bright
        // sunrise region of the bushveld background in both Day/Night modes.
        OutfitterActionChip(
          icon: Icons.settings_rounded,
          tooltip: 'Outfitter settings',
          iconColor: theme.accentColor,
          onPressed: () => _showSettingsBottomSheet(context, theme),
        ),
        OutfitterActionChip(
          icon: Icons.lock_reset_rounded,
          tooltip: 'Sign out',
          iconColor: theme.accentColor,
          onPressed: () {
            UserRoleResolver.instance.reset();
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
        color: OutfitterUi.cardColor(theme),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: OutfitterUi.cardBorderColor(theme), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.villa_rounded, color: theme.accentColor, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _isManager ? 'FARM GATEWAY ONLINE' : 'LODGE GATEWAY ONLINE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _isManager
                ? 'Farm Manager access active. Restricted to ${_assignedFarmId ?? 'N/A'}.'
                : 'Outfitter Control Center loaded. Dashboard sync active.',
            softWrap: true,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.isDarkMode
                  ? theme.textColor.withAlpha(160)
                  : OutfitterUi.lightBody,
              fontSize: 13,
              height: 1.4,
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
      color: OutfitterUi.cardColor(theme),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: OutfitterUi.cardBorderColor(theme), width: 1),
      ),
      child: InkWell(
        onTap: () {
          UsageAnalyticsService.instance.trackFeatureUsage(title);
          onTap();
        },
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.isDarkMode
                            ? theme.textColor.withAlpha(180)
                            : OutfitterUi.lightBody,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: theme.textColor.withAlpha(60),
                size: 14,
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
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isManager ? 'FARM MANAGER SETTINGS' : 'OUTFITTER SETTINGS',
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
                  title: Text(
                    'Dark Mode',
                    style: TextStyle(color: theme.textColor),
                  ),
                  trailing: Switch(
                    value: theme.isDarkMode,
                    onChanged: (v) => theme.setDarkMode(v),
                    activeTrackColor: theme.accentColor,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Icon(Icons.lock_person_outlined, color: theme.accentColor),
                  title: Text(
                    'Change Password',
                    style: TextStyle(color: theme.textColor),
                  ),
                  subtitle: Text(
                    'Re-authenticate and set a new password.',
                    style: TextStyle(color: theme.subtitleColor, fontSize: 12),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: theme.subtitleColor,
                  ),
                  onTap: () => ChangePasswordDialog.show(context),
                ),
                const SizedBox(height: 16),
                const CopyrightFooter(),
              ],
            ),
          ),
    );
  }
}

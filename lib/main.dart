// ADDED
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ADDED
import 'package:connectivity_plus/connectivity_plus.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/splash_screen.dart';
import 'core/services/firestore_bootstrap.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/role_selection_screen.dart';
import 'features/auth/widgets/role_guarded_route.dart';
import 'features/hunter_mode/hunter_dashboard.dart';
import 'features/hunter_mode/add_firearm_manual_form.dart';
import 'features/hunter_mode/license_scanner_screen.dart';
import 'features/hunter_mode/trophy_detail_screen.dart';
import 'features/hunter_mode/add_trophy_screen.dart';
import 'features/hunter_mode/edit_trophy_screen.dart';
import 'features/outfitter_mode/outfitter_dashboard.dart';
import 'features/admin/screens/admin_dashboard_screen.dart';
import 'features/ballistics/data/services/ballistics_seeder.dart';
import 'utils/animal_seeder.dart';
import 'features/hunter_mode/services/offline_sync_queue.dart';
import 'core/utils/measurement_formatter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use the process-wide singleton so any out-of-tree consumer (e.g. the
  // Optical Suite's Firearm-Safe shim) reads the SAME controller driving the
  // app's MaterialApp — one source of truth for the Day/Night preference.
  final themeController = ThemeController.instance;
  // Load persisted Day/Night preference before runApp so the first frame
  // uses the user's saved mode (no flash of the default on cold start).
  await themeController.init();

  // Load persisted Metric/Imperial unit preference before runApp so screens
  // format measurements with the user's saved system on the first frame.
  await MeasurementFormatter.instance.init();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // --- Firebase Crashlytics: real-time error logging ---
    // Route all uncaught Flutter framework (fatal) errors to Crashlytics so
    // they are reported instead of swallowed by the framework dump routine.
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    // Route all uncaught asynchronous errors (outside the Flutter framework,
    // e.g. thrown in isolated zones / Future error callbacks) to Crashlytics.
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    // --- Firebase Analytics: user session & screen event tracking ---
    // A single instance is created here; the navigator observer below feeds
    // automatic screen_view events for every route push/pop.
    final analytics = FirebaseAnalytics.instance;
    await analytics.logAppOpen();

    // Initialize Firebase App Check with debug provider
    // NOTE: For production, register your debug token in Firebase Console > App Check > Debug tokens
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: AppleProvider.debug,
    );

    // Force App Check token pipeline registration to sync Firestore and Auth clients
    try {
      await FirebaseAppCheck.instance.getToken(true);
      debugPrint('App Check token handshake completed successfully');
    } catch (e) {
      debugPrint('App Check fallback handshake completed: $e');
    }

    // --- Global Firestore offline persistence (Item #22) ---
    // Enables a bounded on-device/IndexedDB cache so every primary Firestore
    // stream (Marketplace, Firearms, Permits, Processing Orders, Client
    // Roster, Guided Hunt Logs) keeps serving cached data when the network
    // drops, and queued writes flush on reconnect. On web, a second tab
    // claiming IndexedDB triggers a graceful in-memory fallback (no crash).
    await FirestoreBootstrap.initialize();

    // Network connectivity listener - auto-syncs offline queue when connection restored
    Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        debugPrint(
          '📶 Network link restored. Flushing offline cache data queue...',
        );
        final result =
            await OfflineSyncQueue.instance.processQueueWithInternet();
        if (result.successCount > 0) {
          debugPrint(
            '✅ Synced ${result.successCount} pending actions directly to Firestore!',
          );
        }
      }
    });

    // TEMPORARY: force UNCONDITIONAL ballistics + game guide re-seed on every
    // app startup so local SQLite and Firestore are fully populated. The
    // SharedPreferences `ballistics_seeded` / `game_guide_seed_version`
    // gates are bypassed for this forced re-seed pass (v4.5 hot-fix).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();

      // --- Ballistics reference-data seed (FORCED, unconditional) ---
      try {
        debugPrint("STARTING LIVE BALLISTIC DATA INGESTION (FORCED)...");
        final seeder = BallisticsSeeder();
        await seeder.seedAll();
        await prefs.setBool('ballistics_seeded', true);
        debugPrint("FIRESTORE POPULATION COMPLETELY SUCCESSFUL!");
      } catch (e) {
        debugPrint("SEEDER ERROR LOG: $e");
      }

      // --- SA Game Guide seed (FORCED, unconditional) ---
      // Re-runs on every startup so existing installs that carry null /
      // empty / em-dash Rowland Ward values or blank scientific names get
      // the full benchmark dataset overwritten via the seeder's
      // `merge: true` write.
      try {
        debugPrint("STARTING SA GAME GUIDE SEED (FORCED, v$gameGuideSeedVersion)...");
        await seedAnimalsFromCSV();
        await prefs.setString('game_guide_seed_version', gameGuideSeedVersion);
        debugPrint("SA GAME GUIDE SEED COMPLETE (v$gameGuideSeedVersion).");
      } catch (e) {
        debugPrint("GAME GUIDE SEEDER ERROR LOG: $e");
      }
    });

    runApp(
      JagspoorApp(
        themeController: themeController,
        analytics: analytics,
      ),
    );
  } catch (e) {
    runApp(
      MaterialApp(
        title: 'Jagspoor - Init Error',
        theme: themeController.materialTheme,
        home: Scaffold(
          backgroundColor: themeController.backgroundColor,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: themeController.accentColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Initialization error',
                      style: TextStyle(
                        color: themeController.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      e.toString(),
                      style: TextStyle(color: themeController.subtitleColor),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class JagspoorApp extends StatelessWidget {
  final ThemeController themeController;
  final FirebaseAnalytics? analytics;
  const JagspoorApp({
    super.key,
    required this.themeController,
    this.analytics,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Jagspoor',
          debugShowCheckedModeBanner: false,
          theme: themeController.lightTheme,
          darkTheme: themeController.darkTheme,
          themeMode: themeController.themeMode,
          navigatorObservers: [
            if (analytics != null) FirebaseAnalyticsObserver(analytics: analytics!),
          ],
          initialRoute: '/splash',
          routes: {
            '/splash': (context) => SplashScreen(theme: themeController),
            '/': (context) => AuthScreen(themedata: themeController),
            '/role_selection': (context) => const RoleSelectionScreen(),
            '/hunter_dashboard': (context) => RoleGuardedRoute(
                route: '/hunter_dashboard',
                builder: (_) => HunterDashboard(theme: themeController),
              ),
            '/outfitter_dashboard': (context) => RoleGuardedRoute(
                route: '/outfitter_dashboard',
                builder: (_) => OutfitterDashboard(theme: themeController),
              ),
            '/admin_dashboard': (context) => RoleGuardedRoute(
                route: '/admin_dashboard',
                builder: (_) => AdminDashboardScreen(theme: themeController),
              ),
            '/scan_license':
                (context) => LicenseScannerScreen(theme: themeController),
            '/add_firearm_form':
                (context) => AddFirearmManualForm(theme: themeController),
            '/trophy_detail':
                (context) => TrophyDetailScreen(
                  theme: themeController,
                  trophy:
                      ModalRoute.of(context)?.settings.arguments
                          as Map<String, dynamic>? ??
                      {},
                ),
            '/add_trophy': (context) => AddTrophyScreen(theme: themeController),
            '/edit_trophy':
                (context) => EditTrophyScreen(
                  theme: themeController,
                  trophy:
                      ModalRoute.of(context)?.settings.arguments
                          as Map<String, dynamic>? ??
                      {},
                ),
          },
        );
      },
    );
  }
}

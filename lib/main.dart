// ADDED
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ADDED
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/splash_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/role_selection_screen.dart';
import 'features/hunter_mode/hunter_dashboard.dart';
import 'features/hunter_mode/add_firearm_manual_form.dart';
import 'features/hunter_mode/license_scanner_screen.dart';
import 'features/hunter_mode/trophy_detail_screen.dart';
import 'features/hunter_mode/add_trophy_screen.dart';
import 'features/hunter_mode/edit_trophy_screen.dart';
import 'features/outfitter_mode/outfitter_dashboard.dart';
import 'features/ballistics/data/services/ballistics_seeder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeController = ThemeController();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );


    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

    // Temporary database populator hook - RUNS ONCE
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final hasSeeded = prefs.getBool('ballistics_seeded') ?? false;

      if (!hasSeeded) {
        try {
          debugPrint("STARTING LIVE BALLISTIC DATA INGESTION...");
          final seeder = BallisticsSeeder();
          await seeder.seedAll();
          await prefs.setBool('ballistics_seeded', true);
          debugPrint("FIRESTORE POPULATION COMPLETELY SUCCESSFUL!");
        } catch (e) {
          debugPrint("SEEDER ERROR LOG: $e");
        }
      } else {
        debugPrint("Ballistics data already seeded. Skipping.");
      }
    });

    runApp(JagspoorApp(themeController: themeController));
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
  const JagspoorApp({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Jagspoor',
          debugShowCheckedModeBanner: false,
          theme: themeController.materialTheme,
          initialRoute: '/splash',
          routes: {
            '/splash': (context) => SplashScreen(theme: themeController),
            '/': (context) => AuthScreen(themedata: themeController),
            '/role_selection': (context) => const RoleSelectionScreen(),
            '/hunter_dashboard': (context) =>
                HunterDashboard(theme: themeController),
            '/outfitter_dashboard': (context) =>
                OutfitterDashboard(theme: themeController),
            '/scan_license': (context) =>
                LicenseScannerScreen(theme: themeController),
            '/add_firearm_form': (context) =>
                AddFirearmManualForm(theme: themeController),
            '/trophy_detail': (context) => TrophyDetailScreen(
              theme: themeController,
              trophy:
                  ModalRoute.of(context)?.settings.arguments
                      as Map<String, dynamic>? ??
                  {},
            ),
            '/add_trophy': (context) => AddTrophyScreen(theme: themeController),
            '/edit_trophy': (context) => EditTrophyScreen(
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

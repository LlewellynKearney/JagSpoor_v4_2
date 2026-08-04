import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// POPIA, Google, and iOS compliant Privacy Policy screen
/// for the JagSpoor hunting ecosystem
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<ThemeController>() ?? ThemeController();

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          '🔒 PRIVACY & POPIA POLICY',
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 1.2,
          ),
        ),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: theme.accentColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCard(theme),
              const SizedBox(height: 16),
              _buildSection(
                title: '1. POPIA COMPLIANCE PROTECTIONS',
                icon: Icons.shield_rounded,
                theme: theme,
                content: '''
The Protection of Personal Information Act (POPIA) is South Africa's primary data protection law. JagSpoor is fully committed to compliance.

**1.1 Personal Information We Process:**
• Identity numbers (SA ID numbers)
• Firearm serialisation data and licensing information
• Biometric data (for species identification via AI)
• GPS location data for hunt tracking
• Contact information and payment details

**1.2 Special Protection for Sensitive Data:**
Your South African ID number and firearm serialisation data constitute sensitive personal information under POPIA. This data:
• Is encrypted at rest and in transit
• Is only accessible to verified administrators
• Is never shared with third parties without explicit consent
• Is processed only for legitimate purposes related to legal compliance

**1.3 SA Information Regulator Contact:**
You have the right to contact the Information Regulator if you have concerns:

📍 Information Regulator (South Africa)
Physical: JD House, 27 Stiemens Street, Braamfontein, Johannesburg, 2001
📞: +27 (0)12 406 4818
📧: complaints@inforegulator.org.za
🌐: www.inforegulator.org.za
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '2. GOOGLE & APPLE DATA MINIMISATION',
                icon: Icons.cloud_off_rounded,
                theme: theme,
                content: '''
JagSpoor implements data minimisation principles in compliance with Google Play and Apple App Store policies.

**2.1 Offline-First Architecture:**
Our app is designed to operate primarily offline. All core functionality, including:
• Spoor (track) identification via TensorFlow Lite AI
• Firearm safe management
• Trophy room logging
• Ballistic calculations

...operates entirely on-device without transmitting data to servers.

**2.2 Volatile Local Processing of Bluetooth Telemetry:**
When using the Off-Grid Mesh Sync feature:

• Bluetooth beacon data is processed VOLATILE (temporary memory only)
• No telemetry is persisted to local storage or cloud
• Data is discarded immediately after proximity calculations complete
• No user location history is created from mesh networking

**2.3 Cloud Sync (Optional):**
Cloud synchronisation only occurs when:
• User explicitly initiates a sync
• Active internet connection is available
• User has consented to cloud backup in settings

**2.4 Firebase/Google Services:**
If Firebase services are enabled:
• Analytics data is minimised and anonymised
• Crash reporting uses non-identifying tokens
• Authentication data is encrypted per Firebase security standards
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '3. YOUR RIGHTS UNDER POPIA',
                icon: Icons.gavel_rounded,
                theme: theme,
                content: '''
**3.1 Right to Access:**
You may request access to all personal information we hold about you by contacting our data protection officer.

**3.2 Right to Correction:**
You may request correction of inaccurate or incomplete personal information.

**3.3 Right to Deletion (Right to be Forgotten):**
You have the right to request complete deletion of your account and all associated data.

**3.4 How to Delete Your Account:**
To execute your right to complete account data deletion:

1. Open the JagSpoor app
2. Navigate to: Settings (⚙️) → Hunter Profile
3. Scroll to the "DANGER ZONE" section at the bottom
4. Tap "DELETE ACCOUNT & ALL DATA"
5. Confirm your decision by typing "DELETE" 
6. Your account will be permanently removed within 30 days

Note: Some data may be retained for legal compliance purposes (e.g., firearm license records) as permitted under POPIA Section 37.

**3.5 Right to Object:**
You may object to the processing of your personal information for direct marketing purposes.
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '4. DATA SECURITY MEASURES',
                icon: Icons.lock_rounded,
                theme: theme,
                content: '''
**4.1 Technical Measures:**
• AES-256 encryption for stored data
• TLS 1.3 for data in transit
• Biometric authentication option
• Automatic session timeout

**4.2 Organisational Measures:**
• Regular security audits
• Staff training on data protection
• Incident response procedures
• Third-party security certifications

**4.3 Data Breach Notification:**
In the event of a data breach, we will notify the Information Regulator within 72 hours and affected users without undue delay.
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '5. THIRD-PARTY SERVICES',
                icon: Icons.link_rounded,
                theme: theme,
                content: '''
**5.1 Firebase (Google):**
We use Firebase for authentication and data storage. Their privacy policy applies: https://firebase.google.com/support/privacy

**5.2 Apple (iOS users):**
For iOS users, Apple's Privacy Nutrition Labels apply. We only request permissions necessary for app functionality.

**5.3 TensorFlow Lite:**
On-device AI processing for spoor identification occurs entirely locally. No biometric data leaves your device.
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '6. POLICY UPDATES',
                icon: Icons.update_rounded,
                theme: theme,
                content: '''
This privacy policy may be updated periodically to reflect changes in our practices or legal requirements.

• Users will be notified via in-app notification of material changes
• Continued use of the app after changes constitutes acceptance
• Previous versions available on request

**Last Updated:** July 2026
**Version:** 2.0

For questions regarding this policy, contact: privacy@jagspoor.co.za
''',
              ),
              const SizedBox(height: 32),
              _buildFooterCard(theme),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeController theme) {
    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.accentColor, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(
              Icons.verified_user_rounded,
              size: 64,
              color: theme.accentColor,
            ),
            const SizedBox(height: 12),
            Text(
              'JAGSPOOR ECOSYSTEM',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.textColor,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Privacy & POPIA Compliance Policy',
              style: TextStyle(fontSize: 14, color: theme.subtitleColor),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'POPIA COMPLIANT',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required ThemeController theme,
    required String content,
  }) {
    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.accentColor, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.accentColor,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content.trim(),
              style: TextStyle(
                fontSize: 13,
                color: theme.textColor,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterCard(ThemeController theme) {
    return Card(
      color: theme.accentColor.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.accentColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(
              Icons.help_outline_rounded,
              color: theme.accentColor,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              'Need Assistance?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Contact our Data Protection Officer:\nprivacy@jagspoor.co.za',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: theme.subtitleColor),
            ),
          ],
        ),
      ),
    );
  }
}

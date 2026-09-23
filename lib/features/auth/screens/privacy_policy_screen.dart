import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../legal/popia_registration.dart';

/// POPIA-compliant Privacy Policy screen for the JagSpoor hunting ecosystem.
///
/// Content is sourced from [PopiaRegistration] (the Information Regulator
/// registration certificate) so the published particulars — organisation
/// name, POPIA registration number, Information Officer and contact channels —
/// can never drift from the registered details.
///
/// This screen is reachable from the sign-up form (acceptance checkbox), the
/// login screen (standalone link) and the hunter profile → "PRIVACY & DATA"
/// section, satisfying POPIA s.18 (notification) and Google Play's
/// user-data / account-deletion policy.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key, this.showAcceptanceFooter = false});

  /// When true the footer renders an explicit "I ACCEPT" acknowledgement
  /// button — used when the policy is opened from the sign-up acceptance
  /// checkbox so the reader can return directly to the form.
  final bool showAcceptanceFooter;

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
                title: '1. WHO WE ARE (RESPONSIBLE PARTY)',
                icon: Icons.business_rounded,
                theme: theme,
                content: '''
${PopiaRegistration.organisationName} ("JagSpoor", "we", "us") is the **responsible party** (data controller) for the personal information processed through the JagSpoor hunting ecosystem app, as defined by the Protection of Personal Information Act 4 of 2013 ("POPIA").

**1.1 Registered Particulars:**
• Organisation: ${PopiaRegistration.organisationName}
• POPIA registration number: ${PopiaRegistration.registrationNumber}
• Registration issued: ${PopiaRegistration.registrationDate}
• Company registration (CIPC): ${PopiaRegistration.companyRegistrationNumber}
• Issuing authority: ${PopiaRegistration.issuingAuthority}

**1.2 Information Officer (POPIA s.55 / PAIA s.17):**
Our Information Officer is registered with the Information Regulator and is responsible for POPIA compliance:

• Name: ${PopiaRegistration.informationOfficerName}
• Appointed: ${PopiaRegistration.informationOfficerAppointed}
• Email: ${PopiaRegistration.privacyEmail}
• General support: ${PopiaRegistration.supportEmail}

Address the Information Officer for any request to exercise your rights, any objection to processing, or any data-breach enquiry.
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '2. PERSONAL INFORMATION WE COLLECT',
                icon: Icons.folder_shared_rounded,
                theme: theme,
                content: '''
We collect only what is necessary to run the app and to meet South African hunting, firearm-licensing and animal-transport legal requirements (POPIA s.10 — minimality).

**2.1 Account & Contact Information:**
• First name and surname
• Email address and mobile (cell) number
• Alternative contact number and postal / farm address
• Account role (hunter, outfitter, farm manager, admin)
• Profile photo (optional)
• Farm name (outfitter / farm-manager accounts)

**2.2 Identity & Legal-Compliance Information:**
• South African ID / passport number
• Firearm licence details: make, calibre, serial number, licence number, expiry date and photographs of the licence card
• Hunter status (e.g. dedicated hunter) and provincial permit particulars
• SAPS licence-application references submitted through the SAPS tracker

**2.3 Health & Emergency Information (Special Personal Information):**
• Blood type
• Known allergies
• Medical-aid details
• Emergency-contact person and number
• First-aid certification status

Health information is **special personal information** under POPIA s.26 and is processed only on the basis of your **explicit consent** (given when you complete the Hunter Profile) and solely so that responders can treat you correctly in a hunting accident in a remote area.

**2.4 Location Information:**
• Device GPS coordinates used for off-grid topographic navigation, hunt tracks, waypoints, farm boundaries and carcass-location logging
• Farm / hunt-area coordinates stored on bookings and hunt logs

Location is collected **only while the relevant feature is actively in use**, and off-grid map tiles are cached on your device so navigation works without signal.

**2.5 Hunting & Operational Data:**
• Bookings, hunting packages, price lists and quotes
• Trophy records (species, measurements, photographs)
• Carcass / meat-processing and chiller records
• Venison transport permits (incl. hunter name, ID number, address and farm details for the legally required permit)
• Chat-style booking notes, bug reports and feature suggestions you submit

**2.6 Device & Technical Information:**
• Firebase Cloud Messaging (FCM) device tokens — used to deliver booking-status push notifications
• A one-way hashed device fingerprint (SHA-256 of the platform hardware identifier) used **only** to prevent free-trial abuse (one trial per physical device)
• App-version, platform and diagnostic data used for crash reporting and support
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '3. WHY WE PROCESS IT (LAWFUL PURPOSE)',
                icon: Icons.gavel_rounded,
                theme: theme,
                content: '''
POPIA s.11 requires a lawful basis for every processing activity. We rely on:

**3.1 Performance of a Contract (s.11(1)(b)):**
Account creation, authentication, booking a hunt, publishing a package, issuing a venison permit, invoicing and in-app support.

**3.2 Compliance with a Legal Obligation (s.11(1)(c)):**
Firearm-licence record keeping, hunter/permit verification, animal-transport (venison) permit particulars, and the retention of records required by South African law.

**3.3 Your Explicit Consent (s.11(1)(a) and s.27 for health data):**
• Health / emergency information (blood type, allergies, medical aid)
• Location tracking and off-grid map caching
• Push notifications
• Marketing and product updates (you may withdraw at any time)

**3.4 Legitimate Interest (s.11(1)(f)):**
• Preventing free-trial abuse via the hashed device fingerprint
• Securing the platform (fraud, abuse and unauthorised access detection)
• De-identified, aggregated analytics to improve the app

**3.5 What We Do NOT Do:**
• We never sell your personal information
• We never share your health information, ID number or firearm serial numbers with other app users
• We do not use your data for automated decision-making that produces legal effects

Other app users (an outfitter you booked with, or a hunter who booked with you) can see only the **booking-essential contact details** — name, phone number and email address — so the hunt can be arranged.
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '4. SHARING & CROSS-BORDER TRANSFER',
                icon: Icons.public_rounded,
                theme: theme,
                content: '''
**4.1 Third-Party Operators (POPIA s.20 / s.21):**
We share the minimum necessary information with operators who process it on our behalf under written mandate:

• **Google Firebase** (Authentication, Cloud Firestore, Cloud Storage, Cloud Functions, Cloud Messaging) — hosting, storage, alerting
• **Google Play Billing** — subscription purchase processing (card data is handled by Google, never by us)
• **Google ML Kit / TensorFlow Lite** — on-device spoor and target analysis (no image leaves your device)

**4.2 Cross-Border Transfer:**
Firebase infrastructure may store data on servers outside the Republic of South Africa. POPIA s.72 permits this transfer because Google is contractually bound to a level of protection that is **substantially similar** to POPIA and to the further conditions in s.72(1)(a)–(d). By using JagSpoor you consent to this transfer; you may withdraw by deleting your account.

**4.3 Legal Disclosure:**
We may disclose personal information where compelled by law, subpoena, or a lawful request from SAPS, the Information Regulator or a court of competent jurisdiction.

**4.4 Business Transfer:**
If JagSpoor is sold or merged, personal information may transfer to the acquirer, who remains bound by this policy until amended.
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '5. HOW LONG WE KEEP IT (RETENTION)',
                icon: Icons.hourglass_bottom_rounded,
                theme: theme,
                content: '''
POPIA s.14 requires that records are not kept longer than necessary. We apply the following schedule:

| Category | Retention period |
| --- | --- |
| Account & profile data | Until you delete your account, then erased within 30 days |
| Booking, package and price-list records | 5 years after the last transaction (tax + contractual) |
| Firearm licence and SAPS application records | 5 years after expiry / final decision (legal-compliance obligation) |
| Venison (animal transport) permits | 5 years (legal-compliance obligation) |
| Health / emergency information | Erased immediately on account deletion |
| FCM device tokens | Erased on sign-out or account deletion |
| Hashed device fingerprint | Retained while the account exists (trial-abuse prevention) |
| Support tickets, bug reports, logs | 24 months |

When a retention period lapses the record is securely deleted or irreversibly de-identified.
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '6. YOUR RIGHTS UNDER POPIA',
                icon: Icons.how_to_vote_rounded,
                theme: theme,
                content: '''
**6.1 Right of Access (s.23):**
You may request a copy of the personal information we hold about you.

**6.2 Right to Correction (s.24):**
You may ask us to correct or delete information that is inaccurate, irrelevant, excessive, out of date, incomplete, misleading or unlawfully obtained. Most details can be corrected directly in **Hunter Profile**.

**6.3 Right to Deletion / Objection (s.24 / s.11(3)):**
You may object to processing and request erasure. In-app, self-service deletion:

1. Open JagSpoor
2. Go to **Hunter Profile** (Settings ⚙️ → Hunter Profile)
3. Scroll down to the **PRIVACY & DATA** section
4. Tap **DELETE MY ACCOUNT & DATA**
5. Confirm by typing **DELETE**
6. Your account and associated personal information are permanently removed within 30 days

Outfitter accounts follow the same route from **Outfitter Settings → DANGER ZONE → DELETE ACCOUNT & ALL DATA**.

**6.4 Right to Object to Direct Marketing (s.69):**
You may object at any time to processing for direct marketing by emailing ${PopiaRegistration.privacyEmail} or by using the unsubscribe link.

**6.5 Right to Lodge a Complaint (s.74):**
If you believe we have interfered with your rights, you may complain to our Information Officer (${PopiaRegistration.privacyEmail}) and, if unresolved, to the Information Regulator:

📍 ${PopiaRegistration.regulatorAddress}
📞 ${PopiaRegistration.regulatorPhone}
📧 ${PopiaRegistration.regulatorComplaintsEmail}
🌐 ${PopiaRegistration.regulatorWebsite}

**6.6 Right to Data Portability:**
Where processing is automated and consent-based, you may request your data in a structured, machine-readable format.

**6.7 Legal-Retention Caveat:**
Some records (firearm licence and permit records) may be retained after account deletion where a statute requires it — POPIA s.11(1)(c) read with s.14(2). Those records are restricted to that legal purpose only.
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '7. SECURITY SAFEGUARDS (s.19)',
                icon: Icons.security_rounded,
                theme: theme,
                content: '''
**7.1 Technical Measures:**
• TLS 1.2+ (HTTPS) for all data in transit
• Encryption at rest by Google Cloud / Firebase
• Owner-scoped Firestore security rules — your health, ID and firearm data are readable **only by you**, never by other app users
• Server-side (Admin SDK) writers for subscription and entitlement state
• Optional biometric / device-lock authentication for the app
• One-way hashed device fingerprint (SHA-256) — the raw hardware identifier is never stored
• Secret material (API keys, payment tokens) is never stored in the app or in version control

**7.2 Organisational Measures:**
• Least-privilege administrative access
• Information-Officer oversight of every data request
• Documented incident-response procedure
• POPIA awareness training for personnel and operators

**7.3 Breach Notification (s.22):**
If your personal information is compromised we will notify the Information Regulator **and** you as soon as reasonably possible after discovery, and describe the possible consequences and the remedial action taken.
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '8. COOKIES, LOCAL STORAGE & PUSH NOTIFICATIONS',
                icon: Icons.notifications_active_rounded,
                theme: theme,
                content: '''
**8.1 Cookies:**
The mobile application sets no advertising or tracking cookies. The web pricing page may use strictly-necessary session cookies only.

**8.2 Local Device Storage:**
The app stores the following on your own device:
• Day / night theme preference, favourite dashboard shortcuts and battery-saver setting
• Off-grid topographic map tiles for the areas you cache
• Your offline hunting data (tracks, waypoints, trophies, ammunition) in an encrypted-by-OS SQLite database

This local data is not transmitted unless you explicitly sync, and it is erased when you delete the app or your account.

**8.3 Push Notifications (FCM):**
With your permission we register an FCM device token against your account to deliver booking-status notifications (approval, payment received, cancellation). You may disable notifications in your device settings at any time; the token is removed when you sign out or delete your account.

**8.4 Analytics:**
De-identified, aggregated feature-usage events (which screens are used, by role) are recorded to improve the product. Administrative accounts are excluded from this analytics partition.
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '9. CHILDREN',
                icon: Icons.child_care_rounded,
                theme: theme,
                content: '''
JagSpoor is intended for users aged 18 and older. We do not knowingly process the personal information of a child (under 18) without the consent of a competent person (POPIA s.35). If you believe a child's information has been submitted, contact ${PopiaRegistration.privacyEmail} and we will erase it.
''',
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: '10. POLICY UPDATES',
                icon: Icons.update_rounded,
                theme: theme,
                content: '''
We review this policy at least annually and whenever our processing changes materially.

• Material changes are announced by in-app notification before they take effect
• Continued use after the effective date constitutes acceptance
• Prior versions are available on request from ${PopiaRegistration.privacyEmail}

**Last Updated:** ${PopiaRegistration.lastUpdated}
**Version:** ${PopiaRegistration.policyVersion}
**Policy enquiries:** ${PopiaRegistration.privacyEmail}
''',
              ),
              const SizedBox(height: 32),
              _buildFooterCard(theme, context),
              if (showAcceptanceFooter) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const ValueKey('privacyPolicyAcceptButton'),
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text(
                      'I HAVE READ AND ACCEPT THIS POLICY',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
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
              PopiaRegistration.organisationName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.textColor,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'JAGSPOOR ECOSYSTEM',
              style: TextStyle(
                fontSize: 13,
                color: theme.subtitleColor,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Privacy & POPIA Compliance Policy',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: theme.subtitleColor),
            ),
            const SizedBox(height: 12),
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
                    'REGISTERED WITH THE INFORMATION REGULATOR',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              PopiaRegistration.registrationSummary,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: theme.subtitleColor,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Information Officer: '
              '${PopiaRegistration.informationOfficerName} · '
              '${PopiaRegistration.privacyEmail}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: theme.subtitleColor,
                height: 1.4,
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
                      fontSize: 13,
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

  Widget _buildFooterCard(ThemeController theme, BuildContext context) {
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
              'Information Officer\n'
              '${PopiaRegistration.informationOfficerName}\n'
              '${PopiaRegistration.privacyEmail}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: theme.subtitleColor),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('privacyPolicyRegulatorButton'),
              onPressed: () => _openRegulator(context),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('COMPLAIN TO THE INFORMATION REGULATOR'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.accentColor,
                side: BorderSide(color: theme.accentColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRegulator(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final uri = Uri.parse(PopiaRegistration.regulatorWebsite);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger?.showSnackBar(
          SnackBar(content: Text(PopiaRegistration.regulatorWebsite)),
        );
      }
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(PopiaRegistration.regulatorWebsite)),
      );
    }
  }
}

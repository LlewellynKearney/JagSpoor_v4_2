import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A reusable, theme-aware social "Facebook" row linking to the JagSpoor
/// community page, used on both the Hunter and Outfitter profile/settings
/// screens.
///
/// Tapping the row opens the link in the device's external browser via
/// `url_launcher`. A failed hand-off surfaces a non-blocking snackbar.
class FacebookLinkTile extends StatelessWidget {
  /// The public JagSpoor community / profile page.
  static const String facebookUrl =
      'https://www.facebook.com/profile.php?id=61593783617254';

  final String? title;
  final String? subtitle;

  const FacebookLinkTile({super.key, this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark ? const Color(0xFFE0E0E0) : const Color(0xFF212121);
    final subtitleColor = (isDark ? const Color(0xFFB0B0B0) : const Color(0xFF5D4037))
        .withValues(alpha: 0.85);

    return ListTile(
      leading: Icon(Icons.facebook, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF795548)),
      title: Text(
        title ?? 'Follow Us on Facebook',
        style: TextStyle(
          color: titleColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(color: subtitleColor, fontSize: 12),
            ),
      trailing: Icon(Icons.open_in_new, color: subtitleColor),
      onTap: () => _launch(context),
    );
  }

  Future<void> _launch(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final launched = await launchUrl(Uri.parse(facebookUrl));
      if (!launched && context.mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Could not open Facebook link.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Could not open Facebook link: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
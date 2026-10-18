import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A reusable, theme-aware "Website" row linking to the public JagSpoor site
/// (`https://jag-spoor.co.za`), used next to [FacebookLinkTile] on both the
/// Hunter and Outfitter profile/settings screens.
///
/// Tapping the row opens the link in the device's external browser via
/// `url_launcher` -- identical behaviour on web and Android (no `kIsWeb`
/// branch). A failed hand-off surfaces a non-blocking snackbar.
class WebsiteLinkTile extends StatelessWidget {
  /// The public JagSpoor website.
  static const String websiteUrl = 'https://jag-spoor.co.za';

  final String? title;
  final String? subtitle;

  const WebsiteLinkTile({super.key, this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark ? const Color(0xFFE0E0E0) : const Color(0xFF212121);
    final subtitleColor = (isDark ? const Color(0xFFB0B0B0) : const Color(0xFF5D4037))
        .withValues(alpha: 0.85);

    return ListTile(
      leading: Icon(
        Icons.language,
        color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF795548),
      ),
      title: Text(
        title ?? 'Visit JagSpoor Website',
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
      final launched = await launchUrl(
        Uri.parse(websiteUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('Could not open the JagSpoor website.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Could not open the JagSpoor website: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

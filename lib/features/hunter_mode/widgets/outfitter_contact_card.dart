import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../services/outfitter_contact_resolver.dart';

/// Reusable "CONTACT THE OUTFITTER" card that resolves + renders the
/// outfitter / farm manager contact details (name + role, tappable phone
/// `tel:` intent, tappable email `mailto:` intent) for a package or booking.
///
/// Resolves the contact asynchronously via [OutfitterContactResolver] from
/// the `outfitterId` (+ optional `farmId`) carried on the supplied document
/// map. Renders three states: a compact loading spinner, a graceful
/// "not available" fallback (older records / missing docs / offline), and the
/// resolved contact rows. A failed `tel:` / `mailto:` launch surfaces an
/// orange/red snackbar (messenger captured pre-async-gap, `mounted` guarded).
///
/// Used by:
/// - the Package Details bottom sheet (`_BookingConfirmationSheet`) so a
///   hunter can contact the outfitter before booking;
/// - the hunter "My Bookings" card (`_HunterBookingCard`) so a hunter can
///   contact the outfitter / farm manager for an active or confirmed booking.
class OutfitterContactCard extends StatefulWidget {
  /// The raw package or booking document map. Must carry `outfitterId`;
  /// `farmId` is optional (a package/booking may have no bound farm).
  final Map<String, dynamic> source;

  final ThemeController theme;

  /// Optional heading override (e.g. "CONTACT THE OUTFITTER"). Defaults to
  /// "CONTACT THE OUTFITTER".
  final String heading;

  const OutfitterContactCard({
    super.key,
    required this.source,
    required this.theme,
    this.heading = 'CONTACT THE OUTFITTER',
  });

  @override
  State<OutfitterContactCard> createState() => _OutfitterContactCardState();
}

class _OutfitterContactCardState extends State<OutfitterContactCard> {
  OutfitterContact? _contact;
  bool _isContactLoading = true;

  @override
  void initState() {
    super.initState();
    _resolveContact();
  }

  @override
  void didUpdateWidget(covariant OutfitterContactCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-resolve when the underlying document's outfitterId / farmId changes
    // (e.g. the card is recycled for a new booking by a ListView builder).
    if (oldWidget.source['outfitterId'] != widget.source['outfitterId'] ||
        oldWidget.source['farmId'] != widget.source['farmId']) {
      _resolveContact();
    }
  }

  Future<void> _resolveContact() async {
    if (!mounted) return;
    setState(() => _isContactLoading = true);
    try {
      final contact =
          await OutfitterContactResolver.instance.resolve(widget.source);
      if (mounted) {
        setState(() {
          _contact = contact;
          _isContactLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _contact = const OutfitterContact();
          _isContactLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.contact_phone_rounded,
                  color: theme.accentColor, size: 18),
              const SizedBox(width: 8),
              Text(
                widget.heading,
                style: TextStyle(
                  color: theme.subtitleColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isContactLoading)
            _loadingRow(theme)
          else if (_contact == null || !_contact!.hasAnyContact)
            _unavailableRow(theme)
          else
            _contactDetailsRows(theme, _contact!),
        ],
      ),
    );
  }

  Widget _loadingRow(ThemeController theme) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
        ),
        const SizedBox(width: 12),
        Text(
          'Loading contact details...',
          style: TextStyle(color: theme.subtitleColor, fontSize: 13),
        ),
      ],
    );
  }

  Widget _unavailableRow(ThemeController theme) {
    return Row(
      children: [
        Icon(Icons.info_outline, color: theme.subtitleColor, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Contact details are not available for this booking yet. '
            'Use the in-app chat to reach the outfitter.',
            style: TextStyle(color: theme.subtitleColor, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _contactDetailsRows(ThemeController theme, OutfitterContact contact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _contactNameRow(theme, contact),
        if (contact.primaryPhone.isNotEmpty) ...[
          const SizedBox(height: 8),
          _contactActionRow(
            theme: theme,
            icon: Icons.phone_rounded,
            label: contact.primaryPhone,
            onTap: () => _launchUrl('tel:${contact.primaryPhone}'),
          ),
        ],
        if (contact.primaryEmail.isNotEmpty) ...[
          const SizedBox(height: 8),
          _contactActionRow(
            theme: theme,
            icon: Icons.email_rounded,
            label: contact.primaryEmail,
            onTap: () => _launchUrl('mailto:${contact.primaryEmail}'),
          ),
        ],
      ],
    );
  }

  Widget _contactNameRow(ThemeController theme, OutfitterContact contact) {
    return Row(
      children: [
        Icon(Icons.person_rounded, color: theme.accentColor, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                contact.primaryContactName,
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                contact.primaryContactRole,
                style: TextStyle(
                  color: theme.subtitleColor,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A tappable contact row (phone / email) that launches the platform
  /// tel: / mailto: intent via url_launcher.
  Widget _contactActionRow({
    required ThemeController theme,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              Icon(icon, color: theme.accentColor, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: theme.accentColor,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationColor: theme.accentColor.withValues(alpha: 0.5),
                  ),
                ),
              ),
              Icon(Icons.open_in_new_rounded,
                  color: theme.subtitleColor, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchUrl(String uri) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final parsed = Uri.parse(uri);
      final launched = await launchUrl(parsed);
      if (!launched && mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Could not open $uri.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Could not open link: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

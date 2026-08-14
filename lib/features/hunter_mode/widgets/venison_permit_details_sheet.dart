import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/theme/app_theme.dart';
import '../models/venison_transport_permit.dart';

/// Reusable, draggable details sheet for a [VenisonTransportPermit].
///
/// Renders the full statutory breakdown (hunter, authorized person/farm, hunt
/// window, species hunted and transported, signatures) plus optional actions to
/// export the PDF, void, or delete the permit. Shared by the permit log
/// screens so the details presentation stays consistent.
class VenisonPermitDetailsSheet {
  VenisonPermitDetailsSheet._();

  static Future<void> show(
    BuildContext context, {
    required VenisonTransportPermit permit,
    required ThemeController theme,
    VoidCallback? onExport,
    VoidCallback? onVoid,
    VoidCallback? onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _DetailsContent(
          permit: permit,
          theme: theme,
          scrollController: scrollController,
          onExport: onExport,
          onVoid: onVoid,
          onDelete: onDelete,
        ),
      ),
    );
  }
}

class _DetailsContent extends StatelessWidget {
  final VenisonTransportPermit permit;
  final ThemeController theme;
  final ScrollController scrollController;
  final VoidCallback? onExport;
  final VoidCallback? onVoid;
  final VoidCallback? onDelete;

  const _DetailsContent({
    required this.permit,
    required this.theme,
    required this.scrollController,
    this.onExport,
    this.onVoid,
    this.onDelete,
  });

  String _fmt(DateTime? d) =>
      d == null ? '—' : '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: theme.backgroundColor,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.subtitleColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.receipt_long_rounded,
                    color: theme.accentColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Venison Transport Permit',
                          style: TextStyle(
                              color: theme.textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      Text(permit.permitNumber,
                          style: TextStyle(
                              color: theme.subtitleColor, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: theme.subtitleColor,
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                PermitSection(
                    title: 'PERMIT',
                    theme: theme,
                    children: [
                      PermitDetailRow('Permit No.', permit.permitNumber, theme),
                      PermitDetailRow(
                          'Issued',
                          permit.createdAt == null
                              ? '—'
                              : '${permit.createdAt!.day}/${permit.createdAt!.month}/${permit.createdAt!.year}',
                          theme),
                      PermitDetailRow('Status', permit.status, theme),
                    ]),
                const SizedBox(height: 16),
                PermitSection(
                    title: 'HUNTER DETAILS', theme: theme, children: [
                  PermitDetailRow('Name', permit.hunterName, theme),
                  PermitDetailRow('ID / Passport', permit.hunterIdNumber, theme),
                  PermitDetailRow('Cell', permit.hunterCell, theme),
                  PermitDetailRow('Address', permit.hunterAddress, theme),
                ]),
                const SizedBox(height: 16),
                PermitSection(
                    title: 'AUTHORIZED PERSON / FARM',
                    theme: theme,
                    children: [
                      PermitDetailRow('Authorized Person',
                          permit.authorizedPersonName, theme),
                      PermitDetailRow('Farm', permit.farmName, theme),
                      PermitDetailRow('Farm Address', permit.farmAddress, theme),
                      PermitDetailRow('Farm Cell', permit.farmCell, theme),
                    ]),
                const SizedBox(height: 16),
                PermitSection(title: 'HUNT WINDOW', theme: theme, children: [
                  PermitDetailRow('Start', _fmt(permit.huntStartDate), theme),
                  PermitDetailRow('End', _fmt(permit.huntEndDate), theme),
                ]),
                const SizedBox(height: 16),
                PermitSection(
                  title: 'SPECIES HUNTED AND TRANSPORTED',
                  theme: theme,
                  children: permit.speciesHuntedAndTransported.isEmpty
                      ? [PermitDetailRow('—', 'No species declared', theme)]
                      : permit.speciesHuntedAndTransported
                          .map((s) => PermitDetailRow(
                                s['species']?.toString() ?? 'Unknown',
                                '${s['quantity']}x ${s['sex'] ?? ''}',
                                theme,
                              ))
                          .toList(),
                ),
                const SizedBox(height: 16),
                if (permit.hunterSignatureUrl != null ||
                    permit.outfitterSignatureUrl != null) ...[
                  Text('SIGNATURES',
                      style: TextStyle(
                          color: theme.accentColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (permit.hunterSignatureUrl != null)
                        Expanded(
                          child: PermitSignatureTile(
                            label: 'Hunter',
                            url: permit.hunterSignatureUrl!,
                            signedDate: permit.hunterSignedDate,
                            theme: theme,
                          ),
                        ),
                      if (permit.hunterSignatureUrl != null &&
                          permit.outfitterSignatureUrl != null)
                        const SizedBox(width: 12),
                      if (permit.outfitterSignatureUrl != null)
                        Expanded(
                          child: PermitSignatureTile(
                            label: 'Outfitter',
                            url: permit.outfitterSignatureUrl!,
                            signedDate: permit.outfitterSignedDate,
                            theme: theme,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                // Bottom content padding so the last section (signatures)
                // clears the sticky action bar on gesture-nav devices.
                const SizedBox(height: 90),
              ],
            ),
          ),
          // Sticky action bar — wrapped in SafeArea(bottom: true) so the
          // EXPORT PDF / VOID / DELETE buttons clear the Android 3-button /
          // gesture navigation bar cleanly on every device.
          SafeArea(
            top: false,
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onExport != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onExport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.picture_as_pdf_rounded,
                            size: 18),
                        label: const Text('EXPORT PERMIT PDF',
                            style:
                                TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (onVoid != null || onDelete != null)
                    Row(
                      children: [
                        if (onVoid != null && permit.status != 'Voided')
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onVoid,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange,
                                side:
                                    const BorderSide(color: Colors.orange),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              ),
                              icon:
                                  const Icon(Icons.block_rounded, size: 18),
                              label: const Text('VOID',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ),
                          )
                        else
                          const Spacer(),
                        if (onVoid != null && onDelete != null)
                          const SizedBox(width: 12),
                        if (onDelete != null)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: onDelete,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              ),
                              icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18),
                              label: const Text('DELETE',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PermitSection extends StatelessWidget {
  final String title;
  final ThemeController theme;
  final List<Widget> children;

  const PermitSection(
      {super.key,
      required this.title,
      required this.theme,
      required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: theme.accentColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: theme.accentColor.withValues(alpha: 0.15)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class PermitDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeController theme;

  const PermitDetailRow(this.label, this.value, this.theme, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(color: theme.textColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class PermitSignatureTile extends StatelessWidget {
  final String label;
  final String url;
  final DateTime? signedDate;
  final ThemeController theme;

  const PermitSignatureTile({
    super.key,
    required this.label,
    required this.url,
    required this.signedDate,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label Signature',
            style: TextStyle(
                color: theme.subtitleColor,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          height: 80,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              placeholder: (_, __) => Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: theme.accentColor),
                ),
              ),
              errorWidget: (_, __, ___) => Icon(Icons.draw_rounded,
                  color: theme.subtitleColor),
            ),
          ),
        ),
        if (signedDate != null) ...[
          const SizedBox(height: 4),
          Text(
            'Signed: ${signedDate!.day}/${signedDate!.month}/${signedDate!.year}',
            style: TextStyle(color: theme.subtitleColor, fontSize: 10),
          ),
        ],
      ],
    );
  }
}

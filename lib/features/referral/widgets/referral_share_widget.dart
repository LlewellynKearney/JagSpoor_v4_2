import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../services/referral_repository.dart';
import '../services/referral_share_composer.dart';

/// Reusable "Refer & Earn" widget for the profile settings screens.
///
/// Auto-generates (or loads) the signed-in user's unique referral code
/// ([ReferralRepository.getOrCreateMyReferralProfile]) and exposes:
///   - the formatted code (`formatCodeForDisplay`),
///   - the shareable deep link / message ([ReferralShareComposer]),
///   - a COPY LINK button (system clipboard + visual confirmation),
///   - a SHARE VIA WHATSAPP button (`url_launcher` `wa.me` intent),
///   - a native-share button (`share_plus` platform sheet).
///
/// The widget is self-contained + theme-aware, mirroring
/// [ReferralRewardsAdminCard]: state is isolated, the repository is
/// injectable for tests, and every platform hand-off is failure-tolerant
/// with an on-widget confirmation state (never crashes).
class ReferralShareWidget extends StatefulWidget {
  final ThemeController theme;
  final ReferralRepository? repository;

  const ReferralShareWidget({
    super.key,
    required this.theme,
    this.repository,
  });

  /// Resolves the repository to use — the injectable test seam, or the
  /// production singleton.
  ReferralRepository get repo => repository ?? ReferralRepository.instance;

  @override
  State<ReferralShareWidget> createState() => _ReferralShareWidgetState();
}

enum _ShareCopyState { none, copied, failed }

class _ReferralShareWidgetState extends State<ReferralShareWidget> {
  bool _loading = true;
  bool _sharingWhatsApp = false;
  _ShareCopyState _copyState = _ShareCopyState.none;
  String? _code;
  String? _error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: widget.theme.cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.theme.accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.celebration_rounded,
                    color: widget.theme.accentColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Refer & Earn',
                    style: TextStyle(
                      color: widget.theme.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Share your code — friends get a reward, and so do you.',
              style: TextStyle(
                  color: widget.theme.subtitleColor, fontSize: 11),
            ),
            const SizedBox(height: 12),
            if (_loading)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Loading your referral code…',
                      style: TextStyle(
                          color: widget.theme.subtitleColor, fontSize: 12)),
                ],
              )
            else if (_error != null || _code == null || _code!.isEmpty)
              Text(
                _error ??
                    'Referral code unavailable right now. Please check your '
                        'connection and try again.',
                style: TextStyle(color: Colors.red, fontSize: 12),
              )
            else
              _buildCodeSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeSection(BuildContext context) {
    final code = _code!;
    final link = ReferralShareComposer.buildReferralLink(code);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'YOUR CODE',
                style: TextStyle(
                    color: widget.theme.subtitleColor, fontSize: 10),
              ),
            ),
            if (_copyState == _ShareCopyState.copied)
              Text(
                '✓ Copied to clipboard',
                style: TextStyle(color: Colors.green, fontSize: 11),
              )
            else if (_copyState == _ShareCopyState.failed)
              Text(
                'Copy failed — select + copy manually',
                style: TextStyle(color: Colors.red, fontSize: 11),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          ReferralShareComposer.formatCodeForDisplay(code),
          style: TextStyle(
            color: widget.theme.accentColor,
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          link.isEmpty ? 'No referral link yet.' : link,
          style: TextStyle(
              color: widget.theme.subtitleColor, fontSize: 11),
          softWrap: true,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _copyLink(context),
                icon: const Icon(Icons.content_copy_rounded, size: 18),
                label: Text('COPY LINK',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _sharingWhatsApp ? null : () => _shareWhatsApp(context),
                icon: _sharingWhatsApp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chat_rounded, size: 18),
                label: Text(_sharingWhatsApp ? 'OPENING…' : 'WHATSAPP',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () => _shareNative(context),
            icon: const Icon(Icons.share_rounded, size: 18),
            label: Text('More share options (Email / SMS / Telegram…)',
                style: TextStyle(
                    color: widget.theme.subtitleColor, fontSize: 11)),
          ),
        ),
      ],
    );
  }

  Future<void> load() async {
    final profile = await widget.repo.getOrCreateMyReferralProfile();
    if (!mounted) return;
    if (profile == null || profile.referralCode.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Referral code unavailable right now.';
      });
      return;
    }
    setState(() {
      _loading = false;
      _code = profile.referralCode;
      _error = null;
    });
  }

  Future<void> _copyLink(BuildContext context) async {
    final link = ReferralShareComposer.buildReferralLink(_code ?? '');
    if (link.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: link));
      _setCopyState(_ShareCopyState.copied);
    } catch (_) {
      _setCopyState(_ShareCopyState.failed);
    }
  }

  Future<void> _shareWhatsApp(BuildContext context) async {
    final link = ReferralShareComposer.buildWhatsAppShareLink(_code ?? '');
    if (link.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _sharingWhatsApp = true);
    try {
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('ReferralShareWidget._shareWhatsApp: $e');
      messenger?.showSnackBar(SnackBar(
            content: Text(
                'Could not open WhatsApp. Copy the link and paste it manually.'),
            backgroundColor: Colors.orange));
    } finally {
      if (mounted) setState(() => _sharingWhatsApp = false);
    }
  }

  Future<void> _shareNative(BuildContext context) async {
    final code = _code ?? '';
    final message = ReferralShareComposer.buildShareMessage(code);
    if (message.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await Share.share(
          message, subject: ReferralShareComposer.kDefaultShareSubject);
    } catch (e) {
      debugPrint('ReferralShareWidget._shareNative: $e');
      messenger?.showSnackBar(SnackBar(
            content: Text(
                'Could not open the share sheet. Try COPY LINK instead.'),
            backgroundColor: Colors.orange));
    }
  }

  void _setCopyState(_ShareCopyState state) {
    if (!mounted) return;
    setState(() => _copyState = state);
  }
}
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/contextual_info_icon.dart';
import '../../referral/models/referral_reward_config.dart';
import '../../referral/services/referral_repository.dart';

/// Admin Portal settings card for the JagSpoor referral rewards.
///
/// Views + edits the DYNAMIC hunter vs. outfitter referral reward amounts
/// stored at `admin_config/referral_rewards` ([ReferralRewards
/// .adminConfigDocId]). The card:
///   - loads the live config through [ReferralRepository.loadRewardConfig]
///     and pre-fills the two ZAR fields (falling back to the documented
///     defaults when the doc is absent);
///   - validates each input with [ReferralRewardValidator] — blank,
///     non-numeric and NEGATIVE amounts are blocked by the inline `Form`
///     validators and re-checked in [_save] (the repository clamps as a
///     final belt-and-braces);
///   - persists via [ReferralRepository.saveRewardConfig] (merge into
///     `admin_config/referral_rewards`, admin-only per `firestore.rules`);
///     a non-admin caller's write fails server-side and is surfaced.
///
/// Mirror widget of the existing "Subscription Revenue (ZAR)" manual-input
/// card on [AdminDashboardScreen]; the state is self-contained so it can be
/// reused on any admin surface.
class ReferralRewardsAdminCard extends StatefulWidget {
  final ThemeController theme;
  final ReferralRepository? repository;
  final bool isAdmin;

  const ReferralRewardsAdminCard({
    super.key,
    required this.theme,
    this.repository,
    this.isAdmin = false,
  });

  /// Resolves the repository to use — the injectable test seam, or the
  /// production singleton.
  ReferralRepository get repo => repository ?? ReferralRepository.instance;

  @override
  State<ReferralRewardsAdminCard> createState() =>
      _ReferralRewardsAdminCardState();
}

class _ReferralRewardsAdminCardState extends State<ReferralRewardsAdminCard> {
  final TextEditingController _hunterController = TextEditingController();
  final TextEditingController _outfitterController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _hunterController.dispose();
    _outfitterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _card(Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              'Loading referral reward config…',
              style:
                  TextStyle(color: widget.theme.subtitleColor, fontSize: 12),
            ),
          ],
        ),
      ));
    }
    return _card(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Referral reward amounts (per referral, ZAR)',
                      style: TextStyle(
                        color: widget.theme.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  ContextualInfoIcon(
                    title: 'Referral Rewards',
                    description:
                        'Set the reward paid to a user who refers a NEW paying '
                        'subscriber. Hunters receive the hunter amount; '
                        'outfitters the outfitter amount. Rewards are '
                        'finalised by the backend against this live config.',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.isAdmin
                    ? 'Stored at admin_config/referral_rewards (signed-in read, '
                        'admin write).'
                    : 'Admin-only. You are viewing the configured amounts.',
                style: TextStyle(
                    color: widget.theme.subtitleColor, fontSize: 10),
              ),
              const SizedBox(height: 10),
              _zarField(
                label: 'Hunter referral reward (ZAR)',
                controller: _hunterController,
                enabled: widget.isAdmin && !_saving,
              ),
              const SizedBox(height: 10),
              _zarField(
                label: 'Outfitter referral reward (ZAR)',
                controller: _outfitterController,
                enabled: widget.isAdmin && !_saving,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed:
                      widget.isAdmin && !_saving ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(_saving ? 'SAVING…' : 'SAVE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _zarField({
    required String label,
    required TextEditingController controller,
    required bool enabled,
  }) {
    return TextFormField(
      key: ValueKey(
          label.contains('Hunter')
              ? 'referralHunterRewardField'
              : 'referralOutfitterRewardField'),
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: widget.theme.textColor, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: widget.theme.subtitleColor, fontSize: 12),
        prefixText: 'R ',
        prefixStyle:
            TextStyle(color: widget.theme.subtitleColor, fontSize: 12),
        filled: true,
        fillColor: widget.theme.cardColor,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
      ),
      validator: ReferralRewardValidator.validateZar,
    );
  }

  Widget _card(Widget child) {
    return Card(
      color: widget.theme.cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: widget.theme.textColor.withAlpha(15)),
      ),
      child: child,
    );
  }

  Future<void> _save() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text('Fix the highlighted reward amounts before saving.'),
            backgroundColor: Colors.orange));
      return;
    }
    final hunterValue = ReferralRewardValidator.tryParseZar(
        _hunterController.text);
    final outfitterValue = ReferralRewardValidator.tryParseZar(
        _outfitterController.text);
    if (hunterValue == null || outfitterValue == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text('Enter valid ZAR amounts for both rewards.'),
            backgroundColor: Colors.red));
      return;
    }
    final config = ReferralRewardConfig(
      hunterRewardZAR: hunterValue,
      outfitterRewardZAR: outfitterValue,
    );
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    try {
      await widget.repo.saveRewardConfig(config);
      _applyLoaded(config);
      setState(() {
        _saving = false;
        _error = null;
      });
      messenger?.showSnackBar(SnackBar(
            content: Text(
                'Referral rewards saved (hunter R ${hunterValue.toStringAsFixed(2)} / '
                'outfitter R ${outfitterValue.toStringAsFixed(2)}).'),
            backgroundColor: Colors.green));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger?.showSnackBar(SnackBar(
            content: Text('Could not save referral rewards: $e'),
            backgroundColor: Colors.red));
    }
  }

  /// Loads the config and pre-fills the fields from the live document
  /// (defaults when absent). Exposed for the dashboard's `_bootstrap` so the
  /// card can be refreshed via the dashboard refresh action.
  Future<void> load() async {
    _applyLoaded(await widget.repo.loadRewardConfig());
  }

  void _applyLoaded(ReferralRewardConfig config) {
    _hunterController.text = _formatAmount(config.hunterRewardZAR);
    _outfitterController.text = _formatAmount(config.outfitterRewardZAR);
    setState(() {
      _loading = false;
      _error = null;
    });
  }

  String _formatAmount(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
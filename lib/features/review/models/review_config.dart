/// Admin-configured review-prompt settings, stored on
/// `admin_config/review_config`.
///
/// `admin_config/*` documents are admin-write / signed-in-read per
/// `firestore.rules`, so the values are a server-owned control-plane input
/// that every client reads but only an admin can change. The review modal is
/// gated on [enabled], the number of app launches ([minLaunches]), and a
/// per-device [cooldownDays] window between prompts.
class ReviewConfig {
  final bool enabled;
  final int minLaunches;
  final int cooldownDays;
  final String facebookUrl;
  final String playStoreUrl;
  final String promptTitleHunter;
  final String promptTitleOutfitter;
  final String promptMessage;

  const ReviewConfig({
    this.enabled = true,
    this.minLaunches = defaultMinLaunches,
    this.cooldownDays = defaultCooldownDays,
    this.facebookUrl = defaultFacebookUrl,
    this.playStoreUrl = defaultPlayStoreUrl,
    this.promptTitleHunter = defaultPromptTitleHunter,
    this.promptTitleOutfitter = defaultPromptTitleOutfitter,
    this.promptMessage = defaultPromptMessage,
  });

  /// Firestore document path for the review control plane.
  static const String collection = 'admin_config';
  static const String documentId = 'review_config';

  /// Seed / fallback values written by [ReviewService.ensureConfig] and used
  /// whenever the document is absent (so the feature degrades to a sane
  /// default rather than throwing).
  static const bool defaultEnabled = true;
  static const int defaultMinLaunches = 3;
  static const int defaultCooldownDays = 30;

  /// JagSpoor Facebook reviews page (the reviews tab is part of the page URL).
  static const String defaultFacebookUrl =
      'https://www.facebook.com/JagSpoor/reviews/';

  /// Google Play listing for the JagSpoor package (`za.co.jagspoor.app`, the
  /// real Android `applicationId`).
  static const String defaultPlayStoreUrl =
      'https://play.google.com/store/apps/details?id=za.co.jagspoor.app';

  static const String defaultPromptTitleHunter = 'LOVE JAGSPOOR?';
  static const String defaultPromptTitleOutfitter =
      'LOVE JAGSPOOR FOR OUTFITTERS?';
  static const String defaultPromptMessage =
      'Help keep SA hunting alive — Bush • Karoo • Kalahari';

  /// The canonical seed payload for `admin_config/review_config`.
  static const ReviewConfig defaults = ReviewConfig();

  /// The prompt title for the active mode.
  String promptTitleFor(bool isOutfitter) =>
      isOutfitter ? promptTitleOutfitter : promptTitleHunter;

  ReviewConfig copyWith({
    bool? enabled,
    int? minLaunches,
    int? cooldownDays,
    String? facebookUrl,
    String? playStoreUrl,
    String? promptTitleHunter,
    String? promptTitleOutfitter,
    String? promptMessage,
  }) =>
      ReviewConfig(
        enabled: enabled ?? this.enabled,
        minLaunches: minLaunches ?? this.minLaunches,
        cooldownDays: cooldownDays ?? this.cooldownDays,
        facebookUrl: facebookUrl ?? this.facebookUrl,
        playStoreUrl: playStoreUrl ?? this.playStoreUrl,
        promptTitleHunter: promptTitleHunter ?? this.promptTitleHunter,
        promptTitleOutfitter:
            promptTitleOutfitter ?? this.promptTitleOutfitter,
        promptMessage: promptMessage ?? this.promptMessage,
      );

  /// Firestore / model hydration. Numeric strings and bool-ish values are
  /// tolerated so a hand-edited console document still resolves. Missing
  /// fields fall back to the documented defaults.
  static ReviewConfig fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    return ReviewConfig(
      enabled: _asBool(data['enabled'], defaultEnabled),
      minLaunches: _asInt(data['min_launches'], defaultMinLaunches),
      cooldownDays: _asInt(data['cooldown_days'], defaultCooldownDays),
      facebookUrl: _asString(data['facebook_url'], defaultFacebookUrl),
      playStoreUrl: _asString(data['play_store_url'], defaultPlayStoreUrl),
      promptTitleHunter:
          _asString(data['prompt_title_hunter'], defaultPromptTitleHunter),
      promptTitleOutfitter: _asString(
          data['prompt_title_outfitter'], defaultPromptTitleOutfitter),
      promptMessage: _asString(data['prompt_message'], defaultPromptMessage),
    );
  }

  /// The admin-config payload written to `admin_config/review_config`.
  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'min_launches': minLaunches,
        'cooldown_days': cooldownDays,
        'facebook_url': facebookUrl,
        'play_store_url': playStoreUrl,
        'prompt_title_hunter': promptTitleHunter,
        'prompt_title_outfitter': promptTitleOutfitter,
        'prompt_message': promptMessage,
      };

  static bool _asBool(dynamic value, bool fallback) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      if (v == 'true' || v == '1' || v == 'yes') return true;
      if (v == 'false' || v == '0' || v == 'no') return false;
    }
    return fallback;
  }

  static int _asInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static String _asString(dynamic value, String fallback) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }
}

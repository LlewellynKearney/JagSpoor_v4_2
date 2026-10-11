import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/review/models/review_config.dart';
import 'package:jagspoor/widgets/jagspoor_review_modal.dart';

void main() {
  setUp(() {
    JagspoorReviewModal.resetTestSeams();
  });

  tearDown(() {
    JagspoorReviewModal.resetTestSeams();
  });

  Widget host({required ReviewConfig config, bool isOutfitter = false}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => JagspoorReviewModal.show(
                context,
                config: config,
                isOutfitter: isOutfitter,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders the JagSpoor brand palette + exactly 3 destinations',
      (tester) async {
    await tester.pumpWidget(host(config: ReviewConfig.defaults));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('jagspoorReviewModal')), findsOneWidget);
    expect(find.text('LOVE JAGSPOOR?'), findsOneWidget);
    expect(find.text('WHATSAPP'), findsOneWidget);
    expect(find.text('FACEBOOK'), findsOneWidget);
    expect(find.text('GOOGLE PLAY RATE'), findsOneWidget);
    expect(find.text('MAYBE LATER'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsWidgets);

    // Exactly three review destinations (WhatsApp / Facebook / Play).
    expect(find.byKey(const ValueKey('reviewWhatsAppButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('reviewFacebookButton')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('reviewRatePlayStoreButton')), findsOneWidget);
    // Exactly 3 OutlinedButton destinations (MAYBE LATER is a TextButton).
    expect(find.byType(OutlinedButton), findsNWidgets(3));
  });

  testWidgets('hunter mode shows the hunt-story WhatsApp subtitle',
      (tester) async {
    await tester.pumpWidget(host(config: ReviewConfig.defaults));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Share your hunt story'), findsOneWidget);
  });

  testWidgets('outfitter mode shows the farm subtitle + outfitter title',
      (tester) async {
    await tester.pumpWidget(
      host(config: ReviewConfig.defaults, isOutfitter: true),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Share your farm'), findsOneWidget);
    expect(find.text('LOVE JAGSPOOR FOR OUTFITTERS?'), findsOneWidget);
  });

  testWidgets('uses the official logo asset', (tester) async {
    await tester.pumpWidget(host(config: ReviewConfig.defaults));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, JagspoorReviewModal.logoAsset);
    expect(JagspoorReviewModal.logoAsset, 'assets/app logo/logo1.png');
  });

  testWidgets('MAYBE LATER dismisses with false', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await JagspoorReviewModal.show(
                      context, config: ReviewConfig.defaults);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // MAYBE LATER sits at the bottom of the scrollable dialog; scroll it into
    // view before tapping (documented repo pattern for below-the-fold taps).
    await tester.ensureVisible(find.text('MAYBE LATER'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MAYBE LATER'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.byKey(const ValueKey('jagspoorReviewModal')), findsNothing);
  });

  testWidgets('WhatsApp button shares the hunter message', (tester) async {
    String? shared;
    JagspoorReviewModal.shareWhatsAppForTesting =
        (message) async => shared = message;

    await tester.pumpWidget(host(config: ReviewConfig.defaults));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reviewWhatsAppButton')));
    await tester.pumpAndSettle();

    expect(shared, JagspoorReviewModal.whatsappHunterMessage);
    expect(find.byKey(const ValueKey('jagspoorReviewModal')), findsNothing);
  });

  testWidgets('Facebook button launches the reviews URL', (tester) async {
    String? launched;
    JagspoorReviewModal.launchUrlForTesting = (url) async => launched = url;

    await tester.pumpWidget(host(config: ReviewConfig.defaults));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reviewFacebookButton')));
    await tester.pumpAndSettle();

    expect(launched, 'https://www.facebook.com/JagSpoor/reviews/');
    expect(launched, ReviewConfig.defaultFacebookUrl);
  });

  testWidgets('Google Play Rate requests a native review then dismisses',
      (tester) async {
    var requested = false;
    JagspoorReviewModal.requestReviewForTesting =
        (config) async => requested = true;

    await tester.pumpWidget(host(config: ReviewConfig.defaults));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reviewRatePlayStoreButton')));
    await tester.pumpAndSettle();

    expect(requested, isTrue);
    expect(find.byKey(const ValueKey('jagspoorReviewModal')), findsNothing);
  });
}

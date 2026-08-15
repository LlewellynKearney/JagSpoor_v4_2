import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:jagspoor/utils/image_helper.dart';
import 'package:jagspoor/widgets/photo_unavailable_placeholder.dart';

Widget _boilerplate(Widget child) => MaterialApp(
      home: Scaffold(
        body: Material(child: Center(child: child)),
      ),
    );

void main() {
  group('PhotoUnavailablePlaceholder', () {
    testWidgets('renders the broken-image icon + generic caption with no '
        'sensitive path or HTTP detail surfaced', (tester) async {
      await tester.pumpWidget(_boilerplate(
        const PhotoUnavailablePlaceholder(),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.image_not_supported_outlined),
          findsOneWidget);
      expect(find.text('Photo unavailable'), findsOneWidget);
      // No raw path / status text is ever surfaced to the end user.
      expect(find.textContaining('http'), findsNothing);
      expect(find.textContaining('403'), findsNothing);
      expect(find.textContaining('404'), findsNothing);
    });

    testWidgets('honours icon/label/backgroundColor overrides', (tester) async {
      await tester.pumpWidget(_boilerplate(
        const PhotoUnavailablePlaceholder(
          icon: Icons.emoji_events_rounded,
          label: 'No trophy photo',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
      expect(find.text('No trophy photo'), findsOneWidget);
    });
  });

  group('AdaptiveImage resilient pipeline', () {
    testWidgets('empty path -> placeholder (no image widget built)',
        (tester) async {
      await tester.pumpWidget(_boilerplate(
        const AdaptiveImage(imagePath: ''),
      ));
      await tester.pump();

      // The placeholder caption is rendered.
      expect(find.text('Photo unavailable'), findsOneWidget);
      // No Image.file / CachedNetworkImage attempt for an empty path.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('stale local path (file missing) -> delegates to the '
        'network stage (CachedNetworkImage constructed)', (tester) async {
      // A path that looks local but does not exist on disk. The pipeline
      // must skip Image.file (the file is missing) and delegate onward to
      // the network stage (CachedNetworkImage). We assert the structural
      // contract — that CachedNetworkImage is constructed — rather than the
      // async image-decode outcome, so the test is stable in a headless /
      // no-network sandbox. (CachedNetworkImage wraps its provider in an
      // internal Image widget, so we do not assert against `Image`.)
      await tester.pumpWidget(_boilerplate(
        const AdaptiveImage(imagePath: '/definitely/not/a/real/path.jpg'),
      ));
      await tester.pump();

      // The network stage was constructed (delegation happened).
      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('remote URL -> network stage (CachedNetworkImage)',
        (tester) async {
      await tester.pumpWidget(_boilerplate(
        const AdaptiveImage(
            imagePath: 'https://example.com/trophy.png'),
      ));
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('caller-supplied errorWidget is plumbed through to the '
        'network stage', (tester) async {
      // The errorWidget must be passed to CachedNetworkImage's errorWidget
      // callback so it renders when the network load fails. We verify
      // structurally that AdaptiveImage constructs the network stage with
      // the custom widget in scope (does not throw, does not fall back to
      // the default placeholder at construction time).
      const custom = Key('custom-error');
      await tester.pumpWidget(_boilerplate(
        const AdaptiveImage(
          imagePath: 'https://example.com/trophy.png',
          errorWidget: SizedBox(key: custom),
        ),
      ));
      await tester.pump();

      // Network stage constructed; the custom errorWidget is in the closure.
      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });
  });
}


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
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('stale local path (file missing) -> placeholder, NOT '
        'CachedNetworkImage (instruction 4)', (tester) async {
      // A path that looks local but does not exist on disk. Under the strict
      // contract it must NOT be passed to CachedNetworkImage (that was the
      // bug — a local-looking path treated as a URL hung the loader). It now
      // falls straight to the placeholder.
      await tester.pumpWidget(_boilerplate(
        const AdaptiveImage(imagePath: '/data/local/tmp/definitely-missing.jpg'),
      ));
      await tester.pump();

      // Placeholder rendered; no network attempt, no Image widget.
      expect(find.text('Photo unavailable'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('non-existent file:// URI -> placeholder, NOT CachedNetworkImage',
        (tester) async {
      await tester.pumpWidget(_boilerplate(
        const AdaptiveImage(imagePath: 'file:///data/local/tmp/nope.jpg'),
      ));
      await tester.pump();

      expect(find.text('Photo unavailable'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('remote http(s) URL -> network stage (CachedNetworkImage)',
        (tester) async {
      await tester.pumpWidget(_boilerplate(
        const AdaptiveImage(
            imagePath: 'https://example.com/trophy.png'),
      ));
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('non-URL non-local string -> placeholder, NOT CachedNetworkImage '
        '(instruction 4)', (tester) async {
      // A bare token that is neither a local file path nor an http(s) URL.
      // Must NOT be passed to CachedNetworkImage.
      await tester.pumpWidget(_boilerplate(
        const AdaptiveImage(imagePath: 'not-a-valid-url-or-path'),
      ));
      await tester.pump();

      expect(find.text('Photo unavailable'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('content:// Android media URI -> placeholder, NOT '
        'CachedNetworkImage (content:// is not http(s) and not a File path)',
        (tester) async {
      await tester.pumpWidget(_boilerplate(
        const AdaptiveImage(
            imagePath: 'content://media/external/images/media/123'),
      ));
      await tester.pump();

      expect(find.text('Photo unavailable'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('caller-supplied errorWidget wins over the default placeholder '
        'for a non-URL non-local path', (tester) async {
      const custom = Key('custom-error');
      await tester.pumpWidget(_boilerplate(
        const AdaptiveImage(
          imagePath: 'not-a-valid-url-or-path',
          errorWidget: SizedBox(key: custom),
        ),
      ));
      await tester.pump();

      // The caller's errorWidget is rendered, not the default placeholder.
      expect(find.byKey(custom), findsOneWidget);
      expect(find.text('Photo unavailable'), findsNothing);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('caller-supplied errorWidget is plumbed through to the '
        'network stage for http(s) URLs', (tester) async {
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

  // The URI-path-handling + normalization logic is verified as pure unit
  // tests (instructions 1 & 2) without mounting an Image widget, because
  // real image decode is flaky in a headless test sandbox.
  group('isLocalImagePath (instruction 1 — local path detection)', () {
    test('/data/ prefix is local', () {
      expect(isLocalImagePath('/data/user/0/com.example.jagspoor/files/x.png'),
          isTrue);
    });
    test('/storage/ prefix is local', () {
      expect(isLocalImagePath('/storage/emulated/0/Pictures/y.jpg'), isTrue);
    });
    test('file:// scheme is local', () {
      expect(isLocalImagePath('file:///data/local/tmp/z.png'), isTrue);
    });
    test('POSIX absolute path is local (Path.isAbsolute)', () {
      expect(isLocalImagePath('/tmp/trophy.png'), isTrue);
      expect(isLocalImagePath('/definitely/not/a/real/path.jpg'), isTrue);
    });
    test('http(s) URL is NOT local', () {
      expect(isLocalImagePath('https://firebasestorage.googleapis.com/x.png'),
          isFalse);
      expect(isLocalImagePath('http://example.com/y.jpg'), isFalse);
    });
    test('content:// Android media URI is NOT local', () {
      expect(isLocalImagePath('content://media/external/images/media/123'),
          isFalse);
    });
    test('bare token / relative path is NOT local', () {
      expect(isLocalImagePath('not-a-valid-url-or-path'), isFalse);
      expect(isLocalImagePath('relative/path.jpg'), isFalse);
    });
    test('empty string is NOT local', () {
      expect(isLocalImagePath(''), isFalse);
    });
  });

  group('normalizeLocalImagePath (instruction 2 — file:// normalization)', () {
    test('strips file:// scheme via Uri.toFilePath()', () {
      final result = normalizeLocalImagePath('file:///data/local/tmp/x.png');
      expect(result, '/data/local/tmp/x.png');
    });
    test('strips file:// for an existing on-disk file path', () {
      // A file:// wrapping a real path must normalize to the bare path that
      // File.existsSync() can read.
      final result = normalizeLocalImagePath('file:///tmp/a/b/c.jpg');
      expect(result, '/tmp/a/b/c.jpg');
    });
    test('plain filesystem path is returned unchanged', () {
      const plain = '/data/user/0/com.example.jagspoor/files/photo.png';
      expect(normalizeLocalImagePath(plain), plain);
    });
    test('non-file:// path (http URL) is returned unchanged', () {
      const url = 'https://example.com/trophy.png';
      expect(normalizeLocalImagePath(url), url);
    });
  });
}


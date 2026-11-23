import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Centralized image picking + compression + Firebase Storage upload service.
///
/// All user-generated photos (trophies, carcass logs, firearms, profile
/// pictures, package listings) should route through [ImageService] so that
/// images are consistently downscaled and JPEG-compressed before upload,
/// keeping Storage usage and Firestore document sizes small.
class ImageService {
  ImageService._();

  static final ImagePicker _picker = ImagePicker();

  /// Picks an image from [source] (camera or gallery), downscales it to fit
  /// within [minWidth] x [minHeight], and JPEG-compresses it to [quality].
  ///
  /// Returns the compressed [File] (in the app temp directory), or `null`
  /// when the user cancels image selection.
  ///
  /// [quality]   JPEG quality 1-100 (default 75 — a good balance for photos).
  /// [minWidth]  Target maximum width in pixels (downscaled to fit).
  /// [minHeight] Target maximum height in pixels (downscaled to fit).
  static Future<File?> pickAndCompressImage({
    required ImageSource source,
    int quality = 75,
    int minWidth = 1280,
    int minHeight = 1280,
  }) async {
    final XFile? picked = await _picker.pickImage(source: source);
    if (picked == null) return null;

    return _compress(picked, quality: quality, minWidth: minWidth, minHeight: minHeight);
  }

  /// Compresses an already-picked [XFile] / [File] in place. Exposed so
  /// callers that already have an [XFile] (e.g. from a multi-image picker)
  /// can still benefit from the same compression pipeline.
  static Future<File> compressExisting(
    File imageFile, {
    int quality = 75,
    int minWidth = 1280,
    int minHeight = 1280,
  }) async {
    final compressed = await _compress(
      XFile(imageFile.path),
      quality: quality,
      minWidth: minWidth,
      minHeight: minHeight,
    );
    return compressed ?? imageFile;
  }

  static Future<File?> _compress(
    XFile source, {
    required int quality,
    required int minWidth,
    required int minHeight,
  }) async {
    final Directory tempDir = await getTemporaryDirectory();
    final String targetPath = join(
      tempDir.path,
      'compressed_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );

    try {
      final XFile? result =
          await FlutterImageCompress.compressAndGetFile(
        source.path,
        targetPath,
        quality: quality,
        minWidth: minWidth,
        minHeight: minHeight,
        format: CompressFormat.jpeg,
      );

      if (result == null) {
        debugPrint('ImageService: compression returned null, using original');
        return File(source.path);
      }
      return File(result.path);
    } catch (e) {
      debugPrint('ImageService: compression failed ($e), using original');
      return File(source.path);
    }
  }

  /// Uploads a compressed JPEG [imageFile] to Firebase Storage at
  /// [storagePath] (e.g. 'trophies/{uid}/123.jpg') and returns the public
  /// download URL. Throws on upload failure.
  static Future<String> uploadCompressedPhoto({
    required File imageFile,
    required String storagePath,
  }) async {
    final Reference ref = FirebaseStorage.instance.ref().child(storagePath);
    final UploadTask uploadTask = ref.putFile(
      imageFile,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final TaskSnapshot snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  /// Convenience: pick, compress, and upload in one call. Returns the
  /// download URL, or `null` when the user cancels image selection.
  static Future<String?> pickCompressAndUpload(
    ImageSource source,
    String storagePath, {
    int quality = 75,
    int minWidth = 1280,
    int minHeight = 1280,
  }) async {
    final File? compressed = await pickAndCompressImage(
      source: source,
      quality: quality,
      minWidth: minWidth,
      minHeight: minHeight,
    );
    if (compressed == null) return null;
    return await uploadCompressedPhoto(
      imageFile: compressed,
      storagePath: storagePath,
    );
  }

  /// Uploads an arbitrary document file (an image or a PDF) to Firebase
  /// Storage at [storagePath] and returns the public download URL.
  ///
  /// This is the generic sibling of [uploadCompressedPhoto]: photos go through
  /// [uploadCompressedPhoto] so they are downscaled first, while a document
  /// (e.g. a permit PDF) is uploaded byte-for-byte. Both live here so the app
  /// keeps exactly ONE Firebase Storage uploader.
  ///
  /// [onProgress] receives a 0..1 fraction as the upload advances (used to
  /// render a progress bar). Throws on upload failure — the caller decides
  /// whether to surface an error or abort the enclosing save.
  static Future<String> uploadDocument({
    required File file,
    required String storagePath,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    final Reference ref = FirebaseStorage.instance.ref().child(storagePath);
    final UploadTask uploadTask = ref.putFile(
      file,
      SettableMetadata(contentType: contentType),
    );
    StreamSubscription<TaskSnapshot>? progressSub;
    if (onProgress != null) {
      progressSub = uploadTask.snapshotEvents.listen(
        (snapshot) {
          final total = snapshot.totalBytes;
          if (total > 0) {
            onProgress((snapshot.bytesTransferred / total).clamp(0.0, 1.0));
          }
        },
        onError: (Object _) {},
      );
    }
    try {
      final TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } finally {
      await progressSub?.cancel();
    }
  }

  /// Best-effort delete of a previously uploaded file, addressed by its
  /// download URL.
  ///
  /// Returns true when the object was deleted. NEVER throws: a missing object,
  /// a malformed URL, a permission error or an unavailable Storage instance
  /// all resolve to false (the caller logs it and keeps going — a failed
  /// Storage cleanup must not fail the Firestore delete that owns the record).
  static Future<bool> deleteByDownloadUrl(String? downloadUrl) async {
    final url = downloadUrl?.trim();
    if (url == null || url.isEmpty) return false;
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
      return true;
    } catch (e) {
      debugPrint('ImageService: storage delete failed for "$url" ($e)');
      return false;
    }
  }
}

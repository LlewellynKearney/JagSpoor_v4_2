import 'dart:io';
import 'core/services/image_service.dart' show ImageService;

/// Legacy helper retained for compatibility. New code should call
/// [ImageService] directly. Picks no longer happen here; this only uploads
/// (with re-compression) a file that was already chosen.
Future<String> uploadHunterImage(File file, String hunterId) async {
  // Re-compress defensively in case the caller supplied a raw image.
  final compressed = await ImageService.compressExisting(file);
  final storagePath =
      'hunters/$hunterId/${DateTime.now().millisecondsSinceEpoch}.jpg';
  return ImageService.uploadCompressedPhoto(
    imageFile: compressed,
    storagePath: storagePath,
  );
}


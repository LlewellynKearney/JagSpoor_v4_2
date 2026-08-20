/// Pure photo-gallery resolution helpers for hunter-facing detail surfaces.
///
/// Outfitter-authored documents store photos under a variety of field names:
/// - `imageUrls: [...]` (package gallery, outfitter package creator),
/// - `photoUrls: [...]` (farm photos, registration photo),
/// - `trophyPhotoUrls: [...]` (trophy stock multi-photo attachments),
/// - `photoUrl: '...'` / `imageUrl: '...'` (single-photo fallbacks).
///
/// [resolveGalleryUrls] collects every non-empty URL across all known field
/// names in priority order and de-duplicates the result, so a detail view
/// can render ALL loaded photos (not just the first) without knowing which
/// field the outfitter populates.
library;

/// Resolves every photo URL a document carries, in priority order:
/// 1. `imageUrls` -- package gallery images (most common),
/// 2. `photoUrls` -- farm photo array,
/// 3. `trophyPhotoUrls` -- trophy stock attachments,
/// 4. `photoUrl` -- single-photo field,
/// 5. `imageUrl` -- single-image fallback field.
///
/// Blank entries are skipped, non-string entries are ignored, duplicates are
/// removed (first occurrence wins), and every URL is trimmed. Returns an
/// empty list when the document has no photos at all (the caller renders a
/// clean placeholder).
List<String> resolveGalleryUrls(Map<String, dynamic>? data) {
  if (data == null) return const [];
  final out = <String>[];
  void addUrl(dynamic value) {
    // Non-string entries (numbers, maps, null) are not URLs -- ignore them.
    if (value is! String) return;
    final url = value.trim();
    if (url.isEmpty) return;
    if (!out.contains(url)) out.add(url);
  }

  void addList(dynamic value) {
    if (value is! List) return;
    for (final entry in value) {
      addUrl(entry);
    }
  }

  addList(data['imageUrls']);
  addList(data['photoUrls']);
  addList(data['trophyPhotoUrls']);
  addUrl(data['photoUrl']);
  addUrl(data['imageUrl']);
  return out;
}

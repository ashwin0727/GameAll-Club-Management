import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Lets the person choose where a photo comes from — the camera or their phone's gallery / file chooser — then returns it
/// (null if they back out or the camera/gallery is unavailable or permission is refused).
///
/// The camera asks Android for permission the first time it is used; the gallery uses the system photo picker and needs no
/// permission at all.
Future<XFile?> pickPhoto(BuildContext context, {int? maxWidth, int imageQuality = 85}) async {
  final source = await _askSource(context, multiple: false);
  if (source == null) return null;
  try {
    return await ImagePicker().pickImage(
      source: source,
      maxWidth: maxWidth?.toDouble(),
      imageQuality: imageQuality,
    );
  } catch (_) {
    // Camera permission refused, or no camera on this device.
    return null;
  }
}

/// The result of [pickPhotos]: the photos taken, and how many chosen ones did not fit under the limit.
class PickedPhotos {
  const PickedPhotos(this.files, {this.skipped = 0});

  final List<XFile> files;
  final int skipped;
}

/// Like [pickPhoto], but the gallery lets the person tick several photos in one go, up to [limit]. (The camera takes one picture at a
/// time.) Anything chosen beyond [limit] is dropped and counted in [PickedPhotos.skipped], because older Android pickers ignore the
/// limit. Returns an empty result when they back out.
Future<PickedPhotos> pickPhotos(BuildContext context, {required int limit, int? maxWidth, int imageQuality = 85}) async {
  if (limit <= 0) return const PickedPhotos([]);
  final source = await _askSource(context, multiple: limit > 1);
  if (source == null) return const PickedPhotos([]);
  try {
    if (source == ImageSource.camera) {
      final one = await ImagePicker().pickImage(source: source, maxWidth: maxWidth?.toDouble(), imageQuality: imageQuality);
      return PickedPhotos([?one]);
    }
    if (limit == 1) {
      final one = await ImagePicker().pickImage(source: source, maxWidth: maxWidth?.toDouble(), imageQuality: imageQuality);
      return PickedPhotos([?one]);
    }
    // the picker needs a limit of at least 2 (a limit of 1 is the single picker above)
    final many = await ImagePicker().pickMultiImage(maxWidth: maxWidth?.toDouble(), imageQuality: imageQuality, limit: limit);
    if (many.length <= limit) return PickedPhotos(many);
    return PickedPhotos(many.take(limit).toList(), skipped: many.length - limit);
  } catch (_) {
    // Camera permission refused, or no camera on this device.
    return const PickedPhotos([]);
  }
}

Future<ImageSource?> _askSource(BuildContext context, {required bool multiple}) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(multiple ? 'Choose from gallery (select several)' : 'Choose from gallery or files'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}

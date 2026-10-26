import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Lets the person choose where a photo comes from — the camera or their phone's gallery / file chooser — then returns it
/// (null if they back out or the camera/gallery is unavailable or permission is refused).
///
/// The camera asks Android for permission the first time it is used; the gallery uses the system photo picker and needs no
/// permission at all.
Future<XFile?> pickPhoto(BuildContext context, {int? maxWidth, int imageQuality = 85}) async {
  final source = await showModalBottomSheet<ImageSource>(
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
            title: const Text('Choose from gallery or files'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
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

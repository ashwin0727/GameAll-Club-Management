import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

/// RFC-4180 quoting: wrap in quotes when the cell holds a comma, quote or
/// newline, doubling any quotes inside.
String csvCell(Object? value) {
  final s = value == null ? '' : '$value';
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String buildCsv(List<List<Object?>> rows) => rows.map((r) => r.map(csvCell).join(',')).join('\r\n');

/// Saves [bytes] to the device's Downloads (no share sheet) and tells the user with a snackbar. Returns whether it
/// was saved.
Future<bool> saveFileToDevice(
  BuildContext context, {
  required String fileName,
  required List<int> bytes,
  required String ext,
  required MimeType mimeType,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final base = fileName.toLowerCase().endsWith('.$ext') ? fileName.substring(0, fileName.length - ext.length - 1) : fileName;
    final data = Uint8List.fromList(bytes);
    // Android: straight into the public Download folder (saveFile would bury it in app-private storage).
    // iOS has no shared Downloads, so it goes to the app documents folder, visible in Files.
    if (Platform.isIOS) {
      await FileSaver.instance.saveFile(name: base, bytes: data, fileExtension: ext, mimeType: mimeType);
    } else {
      await FileSaver.instance.saveToDownloads(name: base, bytes: data, fileExtension: ext, mimeType: mimeType);
    }
    messenger.showSnackBar(SnackBar(
      content: Text(Platform.isIOS ? 'Saved $base.$ext to Files.' : 'Saved $base.$ext to your Downloads folder.'),
    ));
    return true;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not save the file. Please try again.')));
    return false;
  }
}

/// Saves [rows] as a `.csv` on the device. A leading BOM keeps ₹ and other non-ASCII text intact in Excel.
Future<bool> saveCsv(BuildContext context, {required String fileName, required List<List<Object?>> rows}) {
  return saveFileToDevice(
    context,
    fileName: fileName,
    bytes: utf8.encode('﻿${buildCsv(rows)}'),
    ext: 'csv',
    mimeType: MimeType.csv,
  );
}

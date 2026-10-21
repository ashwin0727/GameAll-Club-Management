import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

/// Writes [rows] to a temp `.csv` and opens the system share sheet (save to
/// Files / Drive, email, WhatsApp…). A leading BOM keeps ₹ and other non-ASCII
/// text intact when the file is opened in Excel.
Future<void> shareCsv({required String fileName, required List<List<Object?>> rows}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString('﻿${buildCsv(rows)}', encoding: utf8);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/csv')]));
}

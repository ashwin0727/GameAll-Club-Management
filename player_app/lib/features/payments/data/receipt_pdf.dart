import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../my_membership/domain/membership_detail.dart' show clock12, daysLabel, fmtDate;
import '../../venues/domain/venue.dart' show rupees;
import '../domain/payment_receipt.dart';

/// Saves a built PDF: a download on the web, the share sheet on Android. Tests replace it.
typedef ReceiptSaver = Future<void> Function(Uint8List bytes, String filename);

final receiptSaverProvider = Provider<ReceiptSaver>(
  (ref) => (bytes, filename) => Printing.sharePdf(bytes: bytes, filename: filename),
);

/// The file name of a receipt: "GameAll-Receipt-RCP-1A2B3C4D.pdf".
String receiptFileName(PaymentReceipt r) => 'GameAll-Receipt-${r.receiptNo.isEmpty ? r.id : r.receiptNo}.pdf';

/// "Rs. 1,400" — the PDF's built-in fonts have no rupee sign, so the receipt says Rs.
String inrText(int amount) => rupees(amount).replaceFirst('₹', 'Rs. ');

/// The key / value rows for the item the payment was for, by kind.
List<(String, String)> receiptDetailRows(PaymentReceipt r) {
  final rows = <(String, String)>[];
  void add(String label, String? value) {
    if (value != null && value.trim().isNotEmpty) rows.add((label, value.trim()));
  }

  switch (r.kind) {
    case PaymentKind.membership:
      final slot = r.map('slot');
      final days = [for (final d in (slot?['daysOfWeek'] as List<dynamic>? ?? const [])) (d as num).toInt()];
      final start = slot?['startTime'] as String?;
      final end = slot?['endTime'] as String?;
      add('Membership ID', r.str('membershipRef'));
      add('Plan', r.str('planName') ?? r.title);
      add('Plan length', _periodLabel((r.details['durationDays'] as num?)?.toInt()));
      add('Sport', slot?['sport'] as String?);
      add('Court', slot?['court'] as String?);
      add('Allocated time slot', [daysLabel(days), if (start != null && end != null) '${clock12(start)} – ${clock12(end)}'].where((s) => s.isNotEmpty).join(', '));
      add('Valid from', r.date('startDate') == null ? null : fmtDate(r.date('startDate')!));
      add('Valid till', r.date('endDate') == null ? null : fmtDate(r.date('endDate')!));
    case PaymentKind.coaching:
      final batch = r.map('batch');
      final days = [for (final d in (batch?['daysOfWeek'] as List<dynamic>? ?? const [])) (d as num).toInt()];
      final start = batch?['startTime'] as String?;
      final end = batch?['endTime'] as String?;
      add('Programme', r.str('programName') ?? r.title);
      add('Sport', r.str('sport'));
      add('Level', r.str('level'));
      add('Coach', r.str('coach'));
      add('Batch', batch?['name'] as String?);
      add('Days and time', [daysLabel(days), if (start != null && end != null) '${clock12(start)} – ${clock12(end)}'].where((s) => s.isNotEmpty).join(', '));
      add('Fee', r.str('feeType') == 'MONTHLY' ? 'Monthly (AutoPay)' : 'One time');
      add('Starts', r.date('startDate') == null ? null : fmtDate(r.date('startDate')!));
      add('Ends', r.date('endDate') == null ? null : fmtDate(r.date('endDate')!));
    case PaymentKind.booking:
      final from = r.date('startTime');
      final to = r.date('endTime');
      add('Booking ID', r.str('bookingRef'));
      add('Sport', r.str('sport'));
      add('Court', r.str('court'));
      add('Date', from == null ? null : fmtDate(from));
      add('Time', from == null ? null : '${clock12('${from.hour}:${from.minute}')}${to == null ? '' : ' – ${clock12('${to.hour}:${to.minute}')}'}');
      add('Players', (r.details['players'] as num?)?.toString());
  }
  return rows;
}

String? _periodLabel(int? days) => switch (days) {
  null => null,
  >= 25 && <= 45 => 'Monthly',
  >= 80 && <= 100 => 'Quarterly',
  >= 170 && <= 200 => 'Half-yearly',
  >= 350 && <= 380 => 'Yearly',
  final d => '$d days',
};

/// A one-page A4 receipt: GameAll logo header ([logoPng]; the word GAMEALL when null), PAID stamp, amount, who paid, the venue, the item (membership / coaching / booking) and how it
/// was paid. [playerName] / [playerPhone] go under "Paid by".
Future<Uint8List> buildReceiptPdf(PaymentReceipt r, {String? playerName, String? playerPhone, Uint8List? logoPng}) async {
  final logo = logoPng == null ? null : pw.MemoryImage(logoPng);
  final doc = pw.Document(title: 'GameAll receipt ${r.receiptNo}', author: 'GameAll');
  final violet = PdfColor.fromHex('#6D3FE0');
  final grey = PdfColor.fromHex('#5B6478');
  final line = PdfColor.fromHex('#D9DCE6');

  pw.Widget kv(String k, String v, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 150, child: pw.Text(k, style: pw.TextStyle(fontSize: 11, color: grey))),
        pw.Expanded(child: pw.Text(v, style: pw.TextStyle(fontSize: 11.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
      ],
    ),
  );
  pw.Widget section(String title, List<pw.Widget> rows) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 16),
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: line), borderRadius: pw.BorderRadius.circular(8)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: violet)),
        pw.SizedBox(height: 6),
        ...rows,
      ],
    ),
  );

  final paidOn = r.paidAt == null ? null : '${fmtDate(r.paidAt!)}, ${clock12('${r.paidAt!.hour}:${r.paidAt!.minute}')}';
  final detailRows = receiptDetailRows(r);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // the GameAll header: a dark band with the logo (white on dark, as everywhere in the app), then the PAID stamp
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: pw.BoxDecoration(color: PdfColor.fromHex('#0B1230'), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logo != null)
                      pw.Image(logo, height: 30)
                    else
                      pw.Text('GAMEALL', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 1.5)),
                    pw.SizedBox(width: 14),
                    pw.Text('Payment Receipt', style: pw.TextStyle(fontSize: 13, color: PdfColor.fromHex('#C9CFE6'))),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: r.isPaid ? PdfColor.fromHex('#3DDC97') : PdfColor.fromHex('#FDBA74'), width: 1.4), borderRadius: pw.BorderRadius.circular(14)),
                  child: pw.Text(
                    r.isPaid ? 'PAID' : (r.state == PaymentState.failed ? 'FAILED' : 'PENDING'),
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: r.isPaid ? PdfColor.fromHex('#3DDC97') : PdfColor.fromHex('#FDBA74')),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F3EFFE'), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(r.kindLabel.toUpperCase(), style: pw.TextStyle(fontSize: 9.5, color: grey, letterSpacing: 1)),
                    pw.SizedBox(height: 3),
                    pw.Text(r.title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.Text(r.venueName, style: pw.TextStyle(fontSize: 11, color: grey)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Amount paid', style: pw.TextStyle(fontSize: 10, color: grey)),
                    pw.Text(inrText(r.amountInr), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: violet)),
                  ],
                ),
              ],
            ),
          ),
          section('Payment', [
            kv('Receipt number', r.receiptNo, bold: true),
            if (paidOn != null) kv('Paid on', paidOn),
            if (r.methodLabel != null) kv('Payment method', r.methodLabel!),
            if (r.reference != null) kv('Payment reference', r.reference!),
            if (r.totalInr > 0 && r.totalInr != r.amountInr) kv('Total fee', inrText(r.totalInr)),
            if (r.totalInr > r.paidInr && r.paidInr > 0) kv('Balance to pay', inrText(r.totalInr - r.paidInr)),
            if (playerName != null && playerName.trim().isNotEmpty) kv('Paid by', [playerName.trim(), if (playerPhone != null && playerPhone.trim().isNotEmpty) playerPhone.trim()].join('  ·  ')),
          ]),
          section('Venue', [
            kv('Venue', r.venueName),
            if (r.venuePlace != null && r.venuePlace!.isNotEmpty) kv('Location', r.venuePlace!),
            if (r.venuePhone != null) kv('Contact', r.venuePhone!),
          ]),
          if (detailRows.isNotEmpty) section('${r.kindLabel} details', [for (final (k, v) in detailRows) kv(k, v)]),
          pw.Spacer(),
          pw.Divider(color: line),
          pw.Text(
            'This is a computer-generated receipt for a payment made through GameAll and needs no signature. '
            'Keep it for your records. For any question about this payment, contact the venue.',
            style: pw.TextStyle(fontSize: 9, color: grey),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Loads the GameAll logo as PNG bytes for the receipt (the app's logo is a WebP, which a PDF cannot hold). Null when it cannot be read.
typedef ReceiptLogoLoader = Future<Uint8List?> Function();

Future<Uint8List?> loadReceiptLogoPng() async {
  try {
    final data = await rootBundle.load('assets/images/gameall_logo_large.webp');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Tests replace this so no image decoding is needed.
final receiptLogoProvider = Provider<ReceiptLogoLoader>((ref) => loadReceiptLogoPng);

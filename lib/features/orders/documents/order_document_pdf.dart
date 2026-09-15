import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../home/widgets/product_rail.dart' show formatRupees;
import 'order_document.dart';

/// The brand's own inks, as a printed page takes them.
const _blue = PdfColor.fromInt(0xFF267488);
const _ink = PdfColor.fromInt(0xFF36454F);
const _muted = PdfColor.fromInt(0xFF5B6871);
const _hairline = PdfColor.fromInt(0xFFE5E7EB);
const _wash = PdfColor.fromInt(0xFFF6F7F8);

/// Lays an [OrderDocument] out as an A4 PDF.
///
/// The font is embedded rather than left to the reader: the PDF standard
/// fonts cover only Latin-1, and a customer name or a product title outside it
/// would print as nothing at all. Roboto, bundled with the app, covers Latin,
/// Greek and Cyrillic; characters beyond that are dropped from the printed
/// text rather than drawn as boxes -- see [_printable].
Future<Uint8List> renderOrderDocument(OrderDocument document) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );

  final pdf = pw.Document(
    title: '${document.kind.label} ${document.number}',
    author: 'gtradea.com',
    creator: 'gtradea.com',
    subject: 'Order ${document.orderNumber}',
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 44),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _hairline)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _text(
              'gtradea.com  ·  ${document.kind.label} ${document.number}',
              size: 8,
              color: _muted,
            ),
            _text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              size: 8,
              color: _muted,
            ),
          ],
        ),
      ),
      build: (context) => [
        _header(document),
        pw.SizedBox(height: 20),
        _parties(document),
        pw.SizedBox(height: 20),
        _items(document),
        pw.SizedBox(height: 14),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _payment(document)),
            pw.SizedBox(width: 24),
            pw.SizedBox(width: 230, child: _totals(document)),
          ],
        ),
        pw.SizedBox(height: 22),
        _closingNote(document),
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _header(OrderDocument d) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _text('gtradea.com', size: 20, bold: true, color: _blue),
            pw.SizedBox(height: 2),
            _text('Beyond Borders', size: 9, color: _muted),
          ],
        ),
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          _text(d.kind.label.toUpperCase(), size: 22, bold: true, color: _ink),
          pw.SizedBox(height: 6),
          _keyValue('${d.kind.label} no.', d.number),
          if (d.number != d.orderNumber) _keyValue('Order no.', d.orderNumber),
          if (d.placedAt != null) _keyValue('Order date', _date(d.placedAt!)),
          if (d.completedAt != null)
            _keyValue('Delivered', _date(d.completedAt!)),
          _keyValue('Issued', _date(d.issuedAt)),
          _keyValue('Status', d.status),
        ],
      ),
    ],
  );
}

pw.Widget _keyValue(String key, String value) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 2),
  child: pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      // A gap rather than spaces in the string: [_printable] trims each line,
      // and trailing spaces ran the label into its value.
      _text(key, size: 9, color: _muted),
      pw.SizedBox(width: 6),
      _text(value, size: 9, bold: true),
    ],
  ),
);

pw.Widget _parties(OrderDocument d) {
  final billedTo = [
    ?d.customerName,
    ?d.companyName,
    if (d.taxId != null) 'Tax ID: ${d.taxId}',
    ?d.customerEmail,
    ?d.customerPhone,
  ];
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: _block(
          'Billed to',
          billedTo.isEmpty ? const ['Not recorded on the order'] : billedTo,
        ),
      ),
      pw.SizedBox(width: 24),
      pw.Expanded(
        child: _block(
          'Deliver to',
          d.addressLines.isEmpty
              ? const ['Not recorded on the order']
              : [?d.customerName, ...d.addressLines],
        ),
      ),
    ],
  );
}

pw.Widget _block(String title, List<String> lines) => pw.Container(
  padding: const pw.EdgeInsets.all(10),
  decoration: pw.BoxDecoration(
    color: _wash,
    borderRadius: pw.BorderRadius.circular(6),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _text(title.toUpperCase(), size: 8, bold: true, color: _blue),
      pw.SizedBox(height: 5),
      for (final line in lines)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 1.5),
          child: _text(line, size: 9.5),
        ),
    ],
  ),
);

pw.Widget _items(OrderDocument d) {
  final rows = <List<String>>[
    for (var i = 0; i < d.lines.length; i++)
      [
        '${i + 1}',
        _printable(
          d.lines[i].variant == null
              ? d.lines[i].name
              : '${d.lines[i].name}\n${d.lines[i].variant}',
        ),
        '${d.lines[i].quantity}',
        d.lines[i].unitPrice == null ? '—' : formatRupees(d.lines[i].unitPrice!),
        d.lines[i].amount == null ? '—' : formatRupees(d.lines[i].amount!),
      ],
  ];

  return pw.TableHelper.fromTextArray(
    headers: const ['#', 'Item', 'Qty', 'Unit price', 'Amount'],
    data: rows,
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _hairline, width: 0.6),
      bottom: pw.BorderSide(color: _hairline, width: 0.6),
    ),
    headerDecoration: const pw.BoxDecoration(color: _blue),
    headerStyle: pw.TextStyle(
      color: PdfColors.white,
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
    ),
    cellStyle: const pw.TextStyle(color: _ink, fontSize: 9.5),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    headerAlignments: const {
      0: pw.Alignment.centerLeft,
      1: pw.Alignment.centerLeft,
      2: pw.Alignment.center,
      3: pw.Alignment.centerRight,
      4: pw.Alignment.centerRight,
    },
    cellAlignments: const {
      0: pw.Alignment.topLeft,
      1: pw.Alignment.topLeft,
      2: pw.Alignment.topCenter,
      3: pw.Alignment.topRight,
      4: pw.Alignment.topRight,
    },
    columnWidths: const {
      0: pw.FixedColumnWidth(22),
      1: pw.FlexColumnWidth(5),
      2: pw.FixedColumnWidth(34),
      3: pw.FlexColumnWidth(1.7),
      4: pw.FlexColumnWidth(1.7),
    },
  );
}

pw.Widget _totals(OrderDocument d) {
  pw.Widget row(String label, String value, {bool strong = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: _text(
                label,
                size: strong ? 11 : 9.5,
                bold: strong,
                color: strong ? _ink : _muted,
              ),
            ),
            _text(value, size: strong ? 11 : 9.5, bold: strong),
          ],
        ),
      );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      row('Subtotal', formatRupees(d.subtotal)),
      if (d.discount != null)
        row(
          d.couponCode == null ? 'Discount' : 'Discount (${d.couponCode})',
          '- ${formatRupees(d.discount!.abs())}',
        ),
      if (d.delivery != null)
        row(
          'Delivery',
          d.delivery == 0 ? 'Free' : formatRupees(d.delivery!),
        ),
      if (d.adjustment != null)
        row(
          d.adjustment! > 0
              ? 'Delivery and other charges'
              : 'Discounts and adjustments',
          d.adjustment! > 0
              ? formatRupees(d.adjustment!)
              : '- ${formatRupees(d.adjustment!.abs())}',
        ),
      pw.Divider(color: _hairline, height: 10, thickness: 0.8),
      row('Total', formatRupees(d.total), strong: true),
      if (d.tax != null && d.tax! > 0)
        row(
          d.taxFromServer ? 'Tax' : 'Includes VAT (13%)',
          formatRupees(d.tax!),
        ),
      if (d.advancePaid != null) row('Paid in advance', formatRupees(d.advancePaid!)),
      if (d.balanceDue != null) row('Balance due', formatRupees(d.balanceDue!)),
      pw.SizedBox(height: 4),
      _text('All amounts in NPR', size: 8, color: _muted),
    ],
  );
}

pw.Widget _payment(OrderDocument d) => _block('Payment', [
  'Method: ${d.paymentMethod ?? 'Not recorded'}',
  'Status: ${d.paymentStatus ?? 'Not recorded'}',
]);

pw.Widget _closingNote(OrderDocument d) {
  final note = d.kind == OrderDocumentKind.invoice
      ? 'Thank you for shopping with gtradea.com. This invoice is for an order '
            'that has been delivered.'
      : 'This receipt confirms an order that has not been completed yet. An '
            'invoice is available once the order has been delivered.';
  return _text(note, size: 9, color: _muted);
}

pw.Widget _text(
  String value, {
  double size = 10,
  bool bold = false,
  PdfColor color = _ink,
}) => pw.Text(
  _printable(value),
  style: pw.TextStyle(
    fontSize: size,
    color: color,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  ),
);

/// What the embedded font can actually draw.
///
/// Latin, Greek, Cyrillic and the common punctuation block. Anything else --
/// most often Chinese in a product title taken from a supplier -- is left out
/// rather than printed as a row of empty boxes, and the spaces it leaves are
/// closed up. A title that was nothing but such characters reads "Item".
String _printable(String value) {
  final kept = StringBuffer();
  for (final rune in value.runes) {
    final printable =
        rune == 0x0A ||
        (rune >= 0x20 && rune < 0x0250) ||
        (rune >= 0x0370 && rune < 0x0530) ||
        (rune >= 0x1E00 && rune < 0x1F00) ||
        (rune >= 0x2000 && rune < 0x20D0);
    if (printable) kept.writeCharCode(rune);
  }
  final cleaned = kept
      .toString()
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'\s{2,}'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
  return cleaned.isEmpty ? 'Item' : cleaned;
}

String _date(DateTime value) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = value.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

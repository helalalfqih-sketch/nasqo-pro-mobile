import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/erp_models.dart';
import '../models/invoice_print_snapshot.dart';

class LocalInvoicePdfResult {
  LocalInvoicePdfResult(this.bytes, List<Uint8List> previews)
      : previewPages = List.unmodifiable(previews);
  final Uint8List bytes;
  final List<Uint8List> previewPages;
}

/// The preview and PDF both use the same Flutter-shaped Arabic render.
/// Raster pages at 144 dpi preserve RTL and ligatures without remote fonts.
class LocalInvoicePdf {
  static const _pageWidth = 595;
  static const _pageHeight = 842;
  static const _scale = 2;
  static const _rowsPerPage = 18;
  static const _maxPages = 12;

  static Future<LocalInvoicePdfResult> render(InvoicePrintSnapshot data) async {
    final pages = (data.lines.length / _rowsPerPage).ceil().clamp(1, _maxPages);
    if (data.lines.length > _rowsPerPage * _maxPages) {
      throw const FormatException('Invoice has too many pages.');
    }
    final previews = <Uint8List>[];
    final images = <Uint8List>[];
    for (var i = 0; i < pages; i++) {
      final recorder = ui.PictureRecorder();
      ui.Picture? picture;
      ui.Image? image;
      try {
        final canvas = Canvas(recorder)..scale(_scale.toDouble());
        _draw(canvas, data, i, pages);
        picture = recorder.endRecording();
        image =
            await picture.toImage(_pageWidth * _scale, _pageHeight * _scale);
        final rgba =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final pixels =
            rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
        final gray = Uint8List(pixels.length ~/ 4);
        for (var p = 0; p < gray.length; p++) {
          gray[p] = pixels[p * 4];
        }
        images.add(Uint8List.fromList(zlib.encode(gray)));
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        previews
            .add(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
      } finally {
        image?.dispose();
        if (picture == null && recorder.isRecording) {
          recorder.endRecording().dispose();
        }
        picture?.dispose();
      }
    }
    final pdf = _pack(images);
    if (pdf.length > 8 * 1024 * 1024) {
      throw const FormatException('PDF is too large.');
    }
    return LocalInvoicePdfResult(pdf, previews);
  }

  static String _value(String source) {
    if (source.length > 300) {
      throw const FormatException('Saved invoice field too long.');
    }
    final raw = source
        .replaceAll(
            RegExp(
                r'[\u0000-\u001f\u007f-\u009f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]'),
            ' ')
        .trim();
    return raw.isEmpty ? 'غير مسجل' : raw;
  }

  static String _ltr(String value) => '\u2066$value\u2069';

  static String _num(double value) {
    final n = value.toString();
    return n.endsWith('.0') ? n.substring(0, n.length - 2) : n;
  }

  static void _box(
          Canvas c, double l, double t, double w, double h, Color color) =>
      c.drawRect(Rect.fromLTWH(l, t, w, h), Paint()..color = color);

  static void _text(Canvas canvas, String value, double left, double top,
      double width, double height,
      {double size = 13,
      bool ltr = false,
      bool center = false,
      int lines = 1,
      Color color = const Color(0xff222222)}) {
    for (var scale = 1.0; scale >= .62; scale -= .07) {
      final p = TextPainter(
        text: TextSpan(
            text: value,
            style: TextStyle(
              fontFamily: 'InvoiceArabic',
              fontFamilyFallback: const ['InvoiceLatin'],
              fontSize: size * scale,
              height: 1.2,
              color: color,
            )),
        textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
        textAlign: center
            ? TextAlign.center
            : (ltr ? TextAlign.left : TextAlign.right),
        maxLines: lines,
      )..layout(minWidth: width, maxWidth: width);
      final fits = !p.didExceedMaxLines &&
          p.height <= height + .1 &&
          p.computeLineMetrics().every((line) => line.width <= width + .1);
      if (fits) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(left, top, width, height));
        p.paint(canvas, Offset(left, top + (height - p.height) / 2));
        canvas.restore();
      }
      p.dispose();
      if (fits) return;
    }
    throw const FormatException('Saved invoice value will not fit.');
  }

  static void _draw(Canvas c, InvoicePrintSnapshot data, int page, int total) {
    const ink = Color(0xff161616);
    const mute = Color(0xff555555);
    const band = Color(0xffececec);
    const hairline = Color(0xffd9d9d9);
    final e = data.entry;
    _box(c, 0, 0, 595, 842, const Color(0xffffffff));
    _box(c, 34, 25, 527, 3, ink);
    final purchase = e.direction == EntryDirection.credit;
    _text(c, purchase ? 'نسقو برو  |  فاتورة مشتريات محفوظة' : 'نسقو برو  |  فاتورة مبيعات محفوظة', 34, 35, 527, 36, size: 23);
    _text(c, 'نسخة من السجل المحلي، وليست إصدارًا جديدًا للفاتورة', 34, 73, 527,
        20,
        color: mute);
    _box(c, 34, 100, 527, 91, band);
    _text(c, '${purchase ? 'المورد' : 'العميل'}: ${_value(e.accountName)}', 50, 103, 495, 30, lines: 2);
    _text(c, 'المستند: ${_value(e.documentNumber)}', 291, 136, 254, 22);
    _text(c, 'التاريخ: ${_ltr(_value(e.entryDate))}', 50, 136, 230, 22);
    _text(c, 'المستودع: ${_value(e.warehouseName)}', 282, 162, 263, 24);
    _text(c, 'الدفع: ${e.payment.label}   |   العملة: ${e.currency.label}', 50,
        162, 218, 24);
    _box(c, 34, 202, 527, 24, ink);
    const white = Color(0xffffffff);
    _text(c, 'الصنف', 317, 202, 229, 24, color: white);
    _text(c, 'الوحدة', 240, 202, 69, 24, center: true, color: white);
    _text(c, 'الكمية', 178, 202, 58, 24, center: true, color: white);
    _text(c, 'سعر الوحدة', 108, 202, 67, 24,
        center: true, color: white, size: 11);
    _text(c, 'إجمالي البند', 38, 202, 66, 24,
        center: true, color: white, size: 11);
    final visible = data.lines.skip(page * _rowsPerPage).take(_rowsPerPage);
    var y = 227.0;
    for (final line in visible) {
      _box(c, 34, y + 26, 527, 1, hairline);
      _text(c, _value(line.itemName), 317, y, 229, 26, lines: 2);
      _text(c, _value(line.unit), 240, y, 69, 26, center: true, lines: 2);
      _text(c, _num(line.quantity), 178, y, 58, 26, center: true, ltr: true);
      _text(c, _num(line.unitPrice), 108, y, 67, 26, center: true, ltr: true);
      _text(
          c,
          _num(double.parse(
              (line.quantity * line.unitPrice).toStringAsPrecision(15))),
          38,
          y,
          66,
          26,
          center: true,
          ltr: true);
      y += 27;
    }
    if (data.lines.isEmpty) {
      _text(c, 'بنود الأصناف غير محفوظة لهذه الفاتورة القديمة.', 40, y + 4, 510,
          24);
      y += 28;
    }
    if (page == total - 1) {
      final f = data.facts;
      if (f == null) {
        _text(
            c, 'التفصيل الضريبي غير محفوظ لهذه الفاتورة.', 40, y + 4, 510, 19);
      } else {
        _text(
            c,
            'قبل الضريبة: ${_num(f.preTaxTotal)}   |   الضريبة المحفوظة: ${_num(f.taxAmount)}',
            40,
            y + 4,
            510,
            19);
      }
      _box(c, 34, y + 26, 527, 34, band);
      _text(c, 'الإجمالي المسجل: ${_num(e.amount)} ${e.currency.label}', 48,
          y + 26, 499, 34,
          size: 18);
    }
    _box(c, 34, 783, 527, 1, hairline);
    _text(c, '${page + 1} / $total', 40, 786, 85, 25, ltr: true, color: mute);
    _text(c, 'رقم القيد المحلي: ${e.entryNumber}', 180, 786, 368, 25,
        color: mute);
  }

  static Uint8List _pack(List<Uint8List> images) {
    final out = BytesBuilder(copy: false);
    final offsets = <int>[0];
    void write(String value) => out.add(ascii.encode(value));
    void object(String value) {
      offsets.add(out.length);
      write('${offsets.length - 1} 0 obj\n$value\nendobj\n');
    }

    write('%PDF-1.4\n');
    out.add(const [37, 226, 227, 207, 211, 10]);
    object('<< /Type /Catalog /Pages 2 0 R >>');
    final kids =
        List.generate(images.length, (i) => '${3 + 3 * i} 0 R').join(' ');
    object('<< /Type /Pages /Kids [ $kids ] /Count ${images.length} >>');
    for (var i = 0; i < images.length; i++) {
      final id = 3 + 3 * i;
      object('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
          '/Resources << /XObject << /Im ${id + 2} 0 R >> >> '
          '/Contents ${id + 1} 0 R >>');
      const content = 'q\n595 0 0 842 0 0 cm\n/Im Do\nQ\n';
      object('<< /Length ${content.length} >>\nstream\n${content}endstream');
      final image = images[i];
      offsets.add(out.length);
      write('${id + 2} 0 obj\n<< /Type /XObject /Subtype /Image /Width 1190 '
          '/Height 1684 /ColorSpace /DeviceGray /BitsPerComponent 8 '
          '/Filter /FlateDecode /Length ${image.length} >>\nstream\n');
      out.add(image);
      write('\nendstream\nendobj\n');
    }
    final xref = out.length;
    write('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    write(
        'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
    return out.takeBytes();
  }
}

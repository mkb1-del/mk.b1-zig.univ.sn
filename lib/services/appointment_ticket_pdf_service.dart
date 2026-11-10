import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'appointment_ticket.dart';

/// Génère le ticket de rendez-vous en PDF (format A5), avec son code QR, puis
/// le télécharge (web) ou le partage (téléphone).
class AppointmentTicketPdfService {
  static const PdfColor _rose = PdfColor.fromInt(0xFFD81B60);
  static const PdfColor _plum = PdfColor.fromInt(0xFF5B2150);
  static const PdfColor _ink = PdfColor.fromInt(0xFF2A1A24);
  static const PdfColor _muted = PdfColor.fromInt(0xFF7A6B75);
  static const PdfColor _line = PdfColor.fromInt(0xFFE8D5DE);
  static const PdfColor _soft = PdfColor.fromInt(0xFFFCE4EC);

  /// Les polices PDF standard ne gèrent que le Latin-1 : on remplace les
  /// quelques caractères typographiques qui n'y sont pas.
  static String _clean(String? input) {
    if (input == null) return '';
    return input
        .replaceAll('\u2019', "'")
        .replaceAll('\u2018', "'")
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2026', '...')
        .replaceAll('\u0153', 'oe')
        .replaceAll('\u0152', 'OE')
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u202F', ' ');
  }

  static PdfColor _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return const PdfColor.fromInt(0xFF237952);
      case 'cancelled':
        return const PdfColor.fromInt(0xFFC03C40);
      case 'completed':
        return _plum;
      default:
        return const PdfColor.fromInt(0xFF956006);
    }
  }

  static pw.Widget _row(String label, String value) {
    if (value.trim().isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 78,
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 10, color: _muted),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<Uint8List> build(AppointmentTicket t) async {
    final doc = pw.Document(
      title: 'Ticket de rendez-vous ${t.code}',
      author: 'Sunu Yaakaar',
    );

    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    );

    final doctor = _clean(t.doctorName).isEmpty ? 'Votre médecin' : 'Dr ${_clean(t.doctorName)}';
    final doctorLine = _clean(t.doctorSpecialty).isEmpty
        ? doctor
        : '$doctor (${_clean(t.doctorSpecialty)})';
    final statusColor = _statusColor(t.status);

    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a5,
          margin: const pw.EdgeInsets.all(28),
          theme: theme,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'Sunu Yaakaar',
                  style: const pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: _rose,
                  ),
                ),
                pw.Text(
                  'TICKET DE RENDEZ-VOUS',
                  style: const pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _plum,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Container(height: 2, color: _rose),
            pw.SizedBox(height: 14),

            // Statut
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 7),
              decoration: pw.BoxDecoration(
                color: _soft,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Center(
                child: pw.Text(
                  _clean(t.statusTitle),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 16),

            // Code QR et numéro
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _line, width: 1),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: t.qrPayload,
                  width: 110,
                  height: 110,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                t.code,
                style: const pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: _plum,
                  letterSpacing: 2,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'Numéro de rendez-vous',
                style: const pw.TextStyle(fontSize: 9, color: _muted),
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Divider(borderStyle: pw.BorderStyle.dashed, color: _line),
            pw.SizedBox(height: 10),

            // Détails
            _row('Patiente', _clean(t.patientName)),
            _row('Médecin', doctorLine),
            _row('Hôpital', _clean(t.hospital)),
            _row('Date', _clean(t.dateLabel)),
            _row('Heure', _clean(t.timeLabel)),
            _row('Motif', _clean(t.reason)),

            pw.Spacer(),
            pw.Text(
              _clean(t.statusMessage),
              style: pw.TextStyle(
                fontSize: 9,
                color: statusColor,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Présentez ce ticket à l\'accueil. Ticket généré par Sunu Yaakaar.',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  /// Télécharge (web) ou partage (téléphone) le ticket en PDF.
  static Future<void> share(AppointmentTicket t) async {
    final bytes = await build(t);
    await Printing.sharePdf(bytes: bytes, filename: 'ticket-${t.code}.pdf');
  }
}
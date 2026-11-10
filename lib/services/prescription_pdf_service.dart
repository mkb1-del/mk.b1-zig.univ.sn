import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/prescription_model.dart';
import '../models/medication_model.dart';

/// Génère l'ordonnance au format PDF (document formel imprimable) et la
/// télécharge (web) ou la partage / enregistre (mobile).
class PrescriptionPdfService {
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

  static String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  static pw.Widget _labelValue(String label, String value) {
    return pw.RichText(
      text: pw.TextSpan(
        style: const pw.TextStyle(fontSize: 11, color: _ink),
        children: [
          pw.TextSpan(
            text: label,
            style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _plum),
          ),
          pw.TextSpan(text: value),
        ],
      ),
    );
  }

  static pw.Widget _sectionTitle(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
      child: pw.Text(
        text.toUpperCase(),
        style: const pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: _rose,
        ),
      ),
    );
  }

  static pw.Widget _medicationBlock(int index, Medication m) {
    final details = <String>[];
    if (m.dosage.trim().isNotEmpty) details.add('Dose : ${_clean(m.dosage)}');
    if (m.frequency.trim().isNotEmpty) {
      details.add('Fréquence : ${_clean(m.frequency)}');
    }
    if (m.duration.trim().isNotEmpty) {
      details.add('Durée : ${_clean(m.duration)}');
    }
    final instructions = (m.instructions ?? '').trim();

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line, width: 1),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 22,
            height: 22,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              color: _rose,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Text(
              '$index',
              style: const pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _clean(m.name),
                  style: const pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                if (details.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Text(
                      details.join('   |   '),
                      style: const pw.TextStyle(fontSize: 11, color: _ink),
                    ),
                  ),
                if (instructions.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: _labelValue("Mode d'emploi : ", _clean(instructions)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<Uint8List> build({
    required Prescription prescription,
    required List<Medication> medications,
    String? doctorSpecialty,
    String? doctorPhone,
    String? doctorHospital,
  }) async {
    final doctorName = _clean(
      prescription.doctorName.trim().isEmpty ? 'Médecin' : prescription.doctorName,
    );
    final patientName = _clean(
      prescription.patientName.trim().isEmpty ? 'Patiente' : prescription.patientName,
    );
    final specialty = _clean(doctorSpecialty).trim();
    final phone = _clean(doctorPhone).trim();
    final hospital = _clean(doctorHospital).trim();
    final diagnosis = _clean(prescription.diagnosis).trim();
    final treatment = _clean(prescription.treatment).trim();
    final notes = _clean(prescription.notes).trim();
    final date = _fmtDate(prescription.createdAt);

    final doc = pw.Document(
      title: 'Ordonnance - $patientName',
      author: 'Dr $doctorName',
    );

    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    );

    final header = pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Établissement : en tête de l'ordonnance, au-dessus du médecin.
                if (hospital.isNotEmpty) ...[
                  pw.Text(
                    hospital,
                    style: const pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: _rose,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                ],
                pw.Text(
                  'Dr $doctorName',
                  style: const pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: _plum,
                  ),
                ),
                if (specialty.isNotEmpty)
                  pw.Text(
                    specialty,
                    style: const pw.TextStyle(fontSize: 11, color: _rose),
                  ),
                if (phone.isNotEmpty)
                  pw.Text(
                    'Tél : $phone',
                    style: const pw.TextStyle(fontSize: 11, color: _muted),
                  ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'ORDONNANCE',
                  style: const pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: _rose,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Le $date',
                  style: const pw.TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(height: 2, color: _rose),
      ],
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          theme: theme,
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 12),
          child: pw.Text(
            'Ordonnance générée par Sunu Yaakaar  -  Page ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 11, color: _muted),
          ),
        ),
        build: (context) => [
          header,
          pw.SizedBox(height: 18),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _soft,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _labelValue('Patiente : ', patientName),
                if (diagnosis.isNotEmpty) pw.SizedBox(height: 4),
                if (diagnosis.isNotEmpty) _labelValue('Diagnostic : ', diagnosis),
              ],
            ),
          ),
          if (treatment.isNotEmpty) ...[
            _sectionTitle('Traitement'),
            pw.Text(treatment, style: const pw.TextStyle(fontSize: 11, color: _ink)),
          ],
          _sectionTitle('Médicaments prescrits'),
          if (medications.isEmpty)
            pw.Text(
              'Aucun médicament renseigné.',
              style: const pw.TextStyle(fontSize: 11, color: _muted),
            )
          else
            ...[
              for (var i = 0; i < medications.length; i++)
                _medicationBlock(i + 1, medications[i]),
            ],
          if (notes.isNotEmpty) ...[
            _sectionTitle('Recommandations'),
            pw.Text(notes, style: const pw.TextStyle(fontSize: 11, color: _ink)),
          ],
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Container(
                width: 190,
                height: 90,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _line, width: 1),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  'Signature et cachet du médecin',
                  style: const pw.TextStyle(fontSize: 11, color: _muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  static String _fileName(Prescription p) {
    final name = _clean(p.patientName).replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final d = p.createdAt;
    final date =
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    return 'ordonnance_${name.isEmpty ? 'patiente' : name}_$date.pdf';
  }

  /// Génère le PDF puis le télécharge (web) ou ouvre le partage (mobile).
  static Future<void> download({
    required Prescription prescription,
    required List<Medication> medications,
    String? doctorSpecialty,
    String? doctorPhone,
    String? doctorHospital,
  }) async {
    final bytes = await build(
      prescription: prescription,
      medications: medications,
      doctorSpecialty: doctorSpecialty,
      doctorPhone: doctorPhone,
      doctorHospital: doctorHospital,
    );
    await Printing.sharePdf(bytes: bytes, filename: _fileName(prescription));
  }
}

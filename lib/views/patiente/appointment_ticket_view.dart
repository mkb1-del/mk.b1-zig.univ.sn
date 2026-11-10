import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/app_errors.dart';
import '../../services/appointment_ticket.dart';
import '../../services/appointment_ticket_pdf_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/ribbon_background.dart';

/// Ticket de rendez-vous : numéro de référence, code QR et détails, à montrer
/// à l'accueil. Téléchargeable en PDF.
class AppointmentTicketView extends StatefulWidget {
  final AppointmentTicket ticket;

  const AppointmentTicketView({super.key, required this.ticket});

  @override
  State<AppointmentTicketView> createState() => _AppointmentTicketViewState();
}

class _AppointmentTicketViewState extends State<AppointmentTicketView> {
  bool _isSharing = false;

  AppointmentTicket get _t => widget.ticket;

  Future<void> _share() async {
    setState(() => _isSharing = true);
    try {
      await AppointmentTicketPdfService.share(_t);
    } catch (e) {
      AppErrors.log('ticket PDF', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Impossible de créer le ticket. ${AppErrors.message(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  // ---------------------------------------------------------------- Aides

  Color _statusColor() => StatusStyle.color(_t.status);

  /// Version foncée pour écrire du texte (contraste suffisant).
  Color _statusTextColor() {
    switch (_t.status) {
      case 'confirmed':
        return AppColors.successText;
      case 'cancelled':
        return AppColors.dangerText;
      case 'completed':
        return AppColors.plum;
      default:
        return AppColors.amberText;
    }
  }

  Widget _detail(IconData icon, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: AppColors.roseSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: AppColors.rose),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- Ticket

  /// Partie haute : bandeau, statut, code QR et numéro.
  Widget _buildTop() {
    final statusColor = _statusColor();

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          decoration: const BoxDecoration(gradient: AppColors.heroGradient),
          child: const Row(
            children: [
              RibbonLogo(size: 34, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sunu Yaakaar',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Ticket de rendez-vous',
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _t.statusTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _statusTextColor(),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _t.statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Semantics(
                label: 'Code QR du ticket ${_t.code}',
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: QrImageView(
                    data: _t.qrPayload,
                    version: QrVersions.auto,
                    size: 150,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                _t.code,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.plum,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Numéro de rendez-vous',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Partie basse : détails du rendez-vous.
  Widget _buildBottom() {
    final doctor = _t.doctorName.isEmpty ? 'Votre médecin' : 'Dr ${_t.doctorName}';
    final doctorLine =
        _t.doctorSpecialty.isEmpty ? doctor : '$doctor · ${_t.doctorSpecialty}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DashedLine(),
          const SizedBox(height: 22),
          _detail(Icons.person_outline, 'Patiente', _t.patientName),
          _detail(Icons.medical_services_outlined, 'Médecin', doctorLine),
          _detail(Icons.local_hospital_outlined, 'Hôpital', _t.hospital),
          _detail(Icons.calendar_today_outlined, 'Date', _t.dateLabel),
          _detail(Icons.schedule, 'Heure', _t.timeLabel),
          _detail(Icons.notes, 'Motif', _t.reason),
          const SizedBox(height: 4),
          const Text(
            'Présentez ce ticket à l\'accueil le jour du rendez-vous.',
            style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon ticket')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Les deux moitiés du ticket, séparées par la ligne pointillée.
                  PhysicalShape(
                    clipper: const _TicketClipper(top: true),
                    color: Colors.white,
                    elevation: 4,
                    shadowColor: AppColors.rose.withValues(alpha: 0.35),
                    child: _buildTop(),
                  ),
                  PhysicalShape(
                    clipper: const _TicketClipper(top: false),
                    color: Colors.white,
                    elevation: 4,
                    shadowColor: AppColors.rose.withValues(alpha: 0.35),
                    child: _buildBottom(),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _isSharing ? null : _share,
                      icon: _isSharing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_outlined),
                      label: const Text('Télécharger le ticket (PDF)'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Forme d'une moitié de ticket : coins arrondis à l'extérieur, encoches
/// demi-circulaires à l'endroit où les deux moitiés se rejoignent.
class _TicketClipper extends CustomClipper<Path> {
  /// true : moitié haute (encoches en bas) ; false : moitié basse (encoches en haut).
  final bool top;

  const _TicketClipper({required this.top});

  @override
  Path getClip(Size size) {
    const corner = 22.0;
    const notch = 13.0;
    const round = Radius.circular(corner);

    final body = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(0, 0, size.width, size.height),
          topLeft: top ? round : Radius.zero,
          topRight: top ? round : Radius.zero,
          bottomLeft: top ? Radius.zero : round,
          bottomRight: top ? Radius.zero : round,
        ),
      );

    final y = top ? size.height : 0.0;
    final cuts = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, y), radius: notch))
      ..addOval(Rect.fromCircle(center: Offset(size.width, y), radius: notch));

    return Path.combine(PathOperation.difference, body, cuts);
  }

  @override
  bool shouldReclip(covariant _TicketClipper oldClipper) => oldClipper.top != top;
}

/// Ligne pointillée entre les deux moitiés du ticket.
class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashedPainter()),
    );
  }
}

class _DashedPainter extends CustomPainter {
  const _DashedPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1.5;
    const dash = 7.0;
    const gap = 5.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter oldDelegate) => false;
}
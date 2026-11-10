import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import '../../services/app_errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/medication_model.dart';
import '../../models/prescription_model.dart';
import '../../services/auth_service.dart';
import '../../services/doctor_directory_service.dart';
import '../../services/medication_service.dart';
import '../../services/prescription_pdf_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/user_avatar.dart';
import '../messages/chat_view.dart';

/// Détail d'une ordonnance : en-tête (date, état du traitement, médecin),
/// diagnostic, traitement, médicaments avec leur avancement, recommandations,
/// accès au médecin et téléchargement en PDF.
class PatientPrescriptionDetailView extends StatefulWidget {
  final Prescription prescription;

  const PatientPrescriptionDetailView({super.key, required this.prescription});

  @override
  State<PatientPrescriptionDetailView> createState() =>
      _PatientPrescriptionDetailViewState();
}

class _PatientPrescriptionDetailViewState
    extends State<PatientPrescriptionDetailView> {
  final MedicationService _medicationService = MedicationService();
  final AuthService _authService = AuthService();

  List<Medication> _medications = [];
  String? _doctorSpecialty;
  String? _doctorPhone;
  String? _doctorHospital;
  String? _doctorAvatar;
  bool _isLoading = true;
  bool _isDownloading = false;

  /// Ce même écran sert à la patiente et au médecin qui a prescrit : le médecin
  /// ne voit ni « Écrire au médecin » ni « Suivre mes prises ».
  bool get _isDoctorView =>
      Supabase.instance.client.auth.currentUser?.id == widget.prescription.doctorId;

  static const List<String> _monthsShort = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];
  static const List<String> _monthsFull = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _markAsRead();
  }

  Future<void> _load() async {
    // Médicaments, médecin et hôpital : trois lectures indépendantes.
    final directory = DoctorDirectoryService();
    final (medications, doctor, saved, current) = await (
      _medicationService.getMedications(widget.prescription.id),
      _authService.getUserById(widget.prescription.doctorId),
      directory.hospitalOfPrescription(widget.prescription.id),
      directory.hospitalOf(widget.prescription.doctorId),
    ).wait;

    // Le lieu enregistré à la création de l'ordonnance fait foi ; à défaut
    // (ordonnance ancienne), l'hôpital actuel du médecin.
    final hospital = saved.isNotEmpty ? saved : current;

    if (!mounted) return;
    setState(() {
      _medications = medications;
      _doctorSpecialty = doctor?.specialty;
      _doctorPhone = doctor?.phone;
      _doctorAvatar = doctor?.avatarUrl;
      _doctorHospital = hospital;
      _isLoading = false;
    });
  }

  /// Marque l'ordonnance comme lue (fonction SQL sécurisée : la patiente ne
  /// peut modifier que ce champ, et seulement sur ses propres ordonnances).
  Future<void> _markAsRead() async {
    if (widget.prescription.isRead) return;
    try {
      await Supabase.instance.client.rpc(
        'mark_prescription_read',
        params: {'p_id': widget.prescription.id},
      );
    } catch (e) {
      debugPrint('❌ Erreur marquage ordonnance lue: $e');
    }
  }

  Future<void> _download() async {
    setState(() => _isDownloading = true);
    try {
      await PrescriptionPdfService.download(
        prescription: widget.prescription,
        medications: _medications,
        doctorSpecialty: _doctorSpecialty,
        doctorPhone: _doctorPhone,
        doctorHospital: _doctorHospital,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Votre ordonnance est prête'),
          backgroundColor: AppColors.teal,
        ),
      );
    } catch (e) {
      debugPrint('❌ Erreur génération PDF: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Impossible de générer le PDF. ${AppErrors.message(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// Ouvre la conversation avec le médecin qui a prescrit cette ordonnance.
  void _openChat() {
    final p = widget.prescription;
    if (p.doctorId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatView(
          receiverId: p.doctorId,
          receiverName: p.doctorName.trim().isEmpty ? 'Votre médecin' : p.doctorName.trim(),
          receiverAvatar: _doctorAvatar,
        ),
      ),
    );
  }

  // ------------------------------------------------------------ Aides

  DateTime _day(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  String _short(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';

  String _long(DateTime d) => '${d.day} ${_monthsFull[d.month - 1]} ${d.year}';

  Color _darker(Color c) => Color.lerp(c, Colors.black, 0.4)!;

  /// Dernier jour d'un traitement de `days` jours commencé le jour de l'ordonnance.
  DateTime _lastDayOf(int days) {
    final c = _day(widget.prescription.createdAt);
    return DateTime(c.year, c.month, c.day + days - 1);
  }

  /// Dernier jour de tous les traitements de l'ordonnance (null si inconnu).
  DateTime? get _lastDay {
    DateTime? last;
    for (final m in _medications) {
      final days = m.durationDays;
      if (days == null || days < 1) continue;
      final d = _lastDayOf(days);
      if (last == null || d.isAfter(last)) last = d;
    }
    return last;
  }

  /// true : en cours, false : terminée, null : on ne sait pas.
  bool? get _ongoing {
    final last = _lastDay;
    if (last == null) return null;
    return !last.isBefore(_day(DateTime.now()));
  }

  // ------------------------------------------------------------------ UI : en-tête

  Widget _heroLine(IconData icon, String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: bold ? Colors.white : Colors.white.withValues(alpha: 0.85),
                fontSize: bold ? 15 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    final p = widget.prescription;
    final doctorView = _isDoctorView;
    final name = (doctorView ? p.patientName : p.doctorName).trim();
    final specialty = doctorView ? '' : (_doctorSpecialty ?? '').trim();
    final hospital = (_doctorHospital ?? '').trim();
    final ongoing = _ongoing;
    final last = _lastDay;
    final count = _medications.length;

    final subtitle = [
      if (count > 0) '$count médicament${count > 1 ? 's' : ''}',
      if (last != null) (ongoing == true ? 'jusqu\'au ${_long(last)}' : 'terminé le ${_long(last)}'),
    ].join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.rose.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'ORDONNANCE',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (ongoing != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(ongoing ? Icons.timelapse : Icons.task_alt, size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        ongoing ? 'En cours' : 'Terminée',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Prescrite le ${_long(_day(p.createdAt))}',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.15),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.25), height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: UserAvatar(
                  name: name.isEmpty ? (doctorView ? 'Patiente' : 'Médecin') : name,
                  url: doctorView ? null : _doctorAvatar,
                  radius: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (doctorView)
                      const Text('Patiente', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(
                      doctorView
                          ? (name.isEmpty ? 'Patiente' : name)
                          : (name.isEmpty ? 'Votre médecin' : 'Dr $name'),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    if (specialty.isNotEmpty)
                      Text(specialty, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          if (hospital.isNotEmpty) _heroLine(Icons.local_hospital_outlined, hospital),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ UI : textes

  Widget _noteCard({
    required IconData icon,
    required Color color,
    required String title,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 19),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: Text(
                text,
                style: const TextStyle(fontSize: 15, color: AppColors.ink, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ UI : médicaments

  Widget _infoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.roseSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.rose),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              Text(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Avancement du traitement d'un médicament : « Jour 4 sur 14 » avec une barre.
  Widget _progress(Medication m) {
    final days = m.durationDays;
    if (days == null || days < 1) return const SizedBox.shrink();

    final start = _day(widget.prescription.createdAt);
    final last = _lastDayOf(days);
    final today = _day(DateTime.now());

    if (today.isAfter(last)) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          children: [
            const Icon(Icons.task_alt, size: 18, color: AppColors.muted),
            const SizedBox(width: 8),
            Text(
              'Traitement terminé le ${_short(last)}',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    final index = (today.difference(start).inDays + 1).clamp(1, days).toInt();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Jour $index sur $days',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _darker(AppColors.success)),
                ),
              ),
              Text('fin le ${_short(last)}', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: index / days,
              minHeight: 8,
              backgroundColor: AppColors.success.withValues(alpha: 0.15),
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationCard(int index, Medication m) {
    final instructions = (m.instructions ?? '').trim();
    final times = m.timesPerDay;
    final intake = times != null
        ? '$times prise${times > 1 ? 's' : ''} par jour'
        : m.frequency.trim();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.rose, shape: BoxShape.circle),
                child: Text(
                  '$index',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  m.name,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (m.dosage.trim().isNotEmpty) _infoChip(Icons.medication_outlined, 'Dose', m.dosage),
              if (intake.isNotEmpty) _infoChip(Icons.schedule, 'Prises', intake),
              if (m.duration.trim().isNotEmpty) _infoChip(Icons.event_outlined, 'Durée', m.duration),
            ],
          ),
          _progress(m),
          if (instructions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: AppColors.teal, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Comment l\'utiliser',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.teal),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          instructions,
                          style: const TextStyle(fontSize: 14, color: AppColors.ink, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMedications() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        SectionTitle(
          title: _medications.length > 1
              ? 'Médicaments (${_medications.length})'
              : 'Médicament',
        ),
        if (_medications.isEmpty)
          const AppCard(
            child: Text(
              'Aucun médicament renseigné.',
              style: TextStyle(color: AppColors.muted),
            ),
          )
        else
          for (var i = 0; i < _medications.length; i++) ...[
            _buildMedicationCard(i + 1, _medications[i]),
            if (i < _medications.length - 1) const SizedBox(height: 12),
          ],
      ],
    );
  }

  /// Recommandations du médecin, mises en évidence.
  Widget _buildAdvice(String notes) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_outline, color: AppColors.amberText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recommandations du médecin',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.amberText),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notes,
                    style: const TextStyle(fontSize: 15, color: AppColors.ink, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Accès rapides : poser une question au médecin, suivre ses prises.
  Widget _buildHelp() {
    final name = widget.prescription.doctorName.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Une question sur cette ordonnance ?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ne modifiez pas votre traitement sans l\'avis de votre médecin.',
              style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.35),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openChat,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(name.isEmpty ? 'Écrire au médecin' : 'Écrire au Dr $name', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/medications'),
                icon: const Icon(Icons.checklist_rtl, size: 18),
                label: const Text('Suivre mes prises'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: AppColors.rose.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: (_isDownloading || _isLoading) ? null : _download,
            icon: _isDownloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_outlined),
            label: Text(
              _isDownloading ? 'Préparation du PDF...' : 'Télécharger en PDF',
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.prescription;
    final diagnosis = p.diagnosis.trim();
    final treatment = p.treatment.trim();
    final notes = (p.notes ?? '').trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Mon ordonnance')),
      body: _isLoading
          ? const SkeletonPage()
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(),
                        if (diagnosis.isNotEmpty)
                          _noteCard(
                            icon: Icons.medical_information_outlined,
                            color: AppColors.violet,
                            title: 'Diagnostic',
                            text: diagnosis,
                          ),
                        if (treatment.isNotEmpty)
                          _noteCard(
                            icon: Icons.healing_outlined,
                            color: AppColors.teal,
                            title: 'Traitement',
                            text: treatment,
                          ),
                        _buildMedications(),
                        if (notes.isNotEmpty) _buildAdvice(notes),
                        if (!_isDoctorView) _buildHelp(),
                      ],
                    ),
                  ),
                ),
                _buildDownloadBar(),
              ],
            ),
    );
  }
}
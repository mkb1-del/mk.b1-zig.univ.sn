import 'package:flutter/material.dart';
import '../../services/app_errors.dart';
import '../../theme/app_role.dart';
import '../../theme/app_theme.dart';
import '../../services/prescription_service.dart';
import '../../services/medication_service.dart';
import '../../services/auth_service.dart';
import '../../services/doctor_directory_service.dart';
import '../../models/prescription_model.dart';
import '../../models/medication_model.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/user_avatar.dart';

/// Formulaire de création d'une ordonnance : en-tête (patiente, date,
/// établissement), diagnostic, traitement, médicaments, recommandations,
/// récapitulatif et confirmation avant l'envoi.
class CreatePrescriptionView extends StatefulWidget {
  final String patientId;
  final String patientName;

  const CreatePrescriptionView({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<CreatePrescriptionView> createState() => _CreatePrescriptionViewState();
}

class _CreatePrescriptionViewState extends State<CreatePrescriptionView> {
  final PrescriptionService _prescriptionService = PrescriptionService();
  final MedicationService _medicationService = MedicationService();
  final AuthService _authService = AuthService();
  final DoctorDirectoryService _directory = DoctorDirectoryService();

  final _formKey = GlobalKey<FormState>();
  final _diagnosisController = TextEditingController();
  final _treatmentController = TextEditingController();
  final _instructionsController = TextEditingController();

  final List<Medication> _medications = [];
  bool _isSaving = false;

  // Établissement du médecin, repris de son profil (affiché sur l'ordonnance).
  String _doctorName = '';
  String _hospital = '';
  bool _issuerLoaded = false;

  static const List<String> _diagnosisChoices = [
    'Cancer du sein',
    'Suivi après chirurgie',
    'Chimiothérapie',
    'Radiothérapie',
    'Hormonothérapie',
  ];

  static const List<String> _monthsFull = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
  ];
  static const List<String> _monthsShort = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];

  @override
  void initState() {
    super.initState();
    _loadIssuer();
  }

  @override
  void dispose() {
    _diagnosisController.dispose();
    _treatmentController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _loadIssuer() async {
    final doctor = await _authService.getCurrentUser();
    final hospital = doctor == null ? '' : await _directory.hospitalOf(doctor.id);
    if (!mounted) return;
    setState(() {
      _doctorName = doctor?.name ?? '';
      _hospital = hospital;
      _issuerLoaded = true;
    });
  }

  // ------------------------------------------------------------ Aides

  /// Du travail est en cours : on demande confirmation avant de quitter.
  bool get _dirty =>
      _diagnosisController.text.trim().isNotEmpty ||
      _treatmentController.text.trim().isNotEmpty ||
      _instructionsController.text.trim().isNotEmpty ||
      _medications.isNotEmpty;

  String _todayLong() {
    final n = DateTime.now();
    return '${n.day} ${_monthsFull[n.month - 1]} ${n.year}';
  }

  /// Dernier jour d'un traitement de `days` jours commencé aujourd'hui.
  DateTime _lastDay(int days) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + days - 1);
  }

  String _short(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';

  /// Dernier jour de tous les médicaments (null s'il n'y en a pas).
  DateTime? get _treatmentEnd {
    DateTime? last;
    for (final m in _medications) {
      final days = m.durationDays;
      if (days == null || days < 1) continue;
      final d = _lastDay(days);
      if (last == null || d.isAfter(last)) last = d;
    }
    return last;
  }

  void _addToDiagnosis(String choice) {
    final current = _diagnosisController.text.trim();
    setState(() {
      if (current.isEmpty) {
        _diagnosisController.text = choice;
      } else if (!current.toLowerCase().contains(choice.toLowerCase())) {
        _diagnosisController.text = '$current, ${choice.toLowerCase()}';
      }
    });
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandonner l\'ordonnance ?'),
        content: const Text('Ce que vous avez saisi ne sera pas enregistré.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  // ------------------------------------------------------------ Médicaments

  Future<void> _openMedicationDialog({Medication? initial, int? index}) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _MedicationDialog(
        initial: initial,
        onAdd: (medication) {
          setState(() {
            if (index != null) {
              _medications[index] = medication;
            } else {
              _medications.add(medication);
            }
          });
        },
      ),
    );
  }

  // ------------------------------------------------------------ Enregistrement

  /// Vérifie le formulaire, demande confirmation, puis enregistre.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_medications.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez ajouter au moins un médicament'),
          backgroundColor: AppColors.amber,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Envoyer l\'ordonnance ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pour ${widget.patientName}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              '${_medications.length} médicament${_medications.length > 1 ? 's' : ''} : '
              '${_medications.map((m) => m.name).join(', ')}',
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 10),
            const Text(
              'La patiente la recevra aussitôt dans son application.',
              style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Revoir'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await _save();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    String? createdId;

    try {
      final doctor = await _authService.getCurrentUser();
      if (doctor == null) throw Exception('Médecin non connecté');

      final prescription = Prescription(
        id: '',
        patientId: widget.patientId,
        patientName: widget.patientName,
        doctorId: doctor.id,
        doctorName: doctor.name,
        diagnosis: _diagnosisController.text.trim(),
        treatment: _treatmentController.text.trim(),
        notes: _instructionsController.text.trim().isEmpty
            ? null
            : _instructionsController.text.trim(),
        createdAt: DateTime.now(),
      );

      final createdPrescription =
          await _prescriptionService.createPrescription(prescription);
      if (createdPrescription == null) {
        throw Exception(
            'Échec de la création de l\'ordonnance (voir la console pour le détail)');
      }
      createdId = createdPrescription.id;

      for (final med in _medications) {
        final medication = Medication(
          id: '',
          prescriptionId: createdPrescription.id,
          name: med.name,
          dosage: med.dosage,
          frequency: med.frequency,
          duration: med.duration,
          instructions: med.instructions,
          timesPerDay: med.timesPerDay,
          durationDays: med.durationDays,
        );

        final ok = await _medicationService.addMedication(medication);
        if (!ok) {
          throw Exception(
              'Échec de l\'ajout du médicament "${med.name}" (voir la console)');
        }
      }

      if (!mounted) return;

      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Ordonnance créée avec succès'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      // Annule l'ordonnance si elle a été créée mais qu'un médicament a échoué,
      // pour ne pas laisser une ordonnance vide en base.
      if (createdId != null) {
        await _prescriptionService.deletePrescription(createdId);
      }

      if (!mounted) return;

      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${AppErrors.message(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
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
                fontSize: 13.5,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppRole.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppRole.headerShadow.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NOUVELLE ORDONNANCE',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: UserAvatar(name: widget.patientName, radius: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pour', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(
                      widget.patientName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: Colors.white.withValues(alpha: 0.25), height: 1),
          const SizedBox(height: 4),
          _heroLine(Icons.event_outlined, _todayLong()),
          if (_doctorName.isNotEmpty)
            _heroLine(Icons.medical_services_outlined, 'Dr $_doctorName', bold: true),
          if (_issuerLoaded && _hospital.trim().isNotEmpty)
            _heroLine(Icons.local_hospital_outlined, _hospital)
          else if (!_issuerLoaded)
            _heroLine(Icons.local_hospital_outlined, 'Chargement...'),
        ],
      ),
    );
  }

  /// Avertissement quand l'hôpital n'est pas renseigné : il ne figurera pas sur l'ordonnance.
  Widget _buildMissingHospital() {
    if (!_issuerLoaded || _hospital.trim().isNotEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.local_hospital_outlined, color: AppColors.amberText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Aucun hôpital renseigné',
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.amberText),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'L\'établissement ne figurera pas sur l\'ordonnance. Indiquez-le dans votre profil.',
                    style: TextStyle(fontSize: 13, color: AppColors.ink, height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/doctor-profile')
                        .then((_) => _loadIssuer()),
                    child: const Text('Compléter mon profil'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ UI : sections

  Widget _section({
    required IconData icon,
    required Color color,
    required String title,
    String? hint,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
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
                if (hint != null) ...[
                  const SizedBox(width: 8),
                  Text(hint, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosis() {
    return _section(
      icon: Icons.medical_information_outlined,
      color: AppColors.violet,
      title: 'Diagnostic',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _diagnosisController,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Ex : cancer du sein, suivi après chirurgie',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Veuillez entrer le diagnostic';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          const Text('Ajouter :', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 0,
            children: [
              for (final c in _diagnosisChoices)
                ActionChip(
                  label: Text(c),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _addToDiagnosis(c),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTreatment() {
    return _section(
      icon: Icons.healing_outlined,
      color: AppColors.teal,
      title: 'Traitement',
      child: TextFormField(
        controller: _treatmentController,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: 'Ex : hormonothérapie pendant 5 ans',
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Veuillez entrer le traitement';
          }
          return null;
        },
      ),
    );
  }

  // ------------------------------------------------------------------ UI : médicaments

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.roseSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.rose),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
        ],
      ),
    );
  }

  Widget _medicationCard(int index, Medication m) {
    final instructions = (m.instructions ?? '').trim();
    final times = m.timesPerDay;
    final days = m.durationDays;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.rose, shape: BoxShape.circle),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  m.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
              ),
              IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit_outlined, color: AppColors.muted),
                onPressed: () => _openMedicationDialog(initial: m, index: index),
              ),
              IconButton(
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: () => setState(() => _medications.removeAt(index)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (m.dosage.trim().isNotEmpty) _chip(Icons.medication_outlined, m.dosage),
                if (times != null) _chip(Icons.schedule, '$times prise${times > 1 ? 's' : ''} par jour'),
                if (days != null)
                  _chip(Icons.event_outlined, '$days jour${days > 1 ? 's' : ''} · jusqu\'au ${_short(_lastDay(days))}'),
              ],
            ),
          ),
          if (instructions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 17, color: AppColors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        instructions,
                        style: const TextStyle(fontSize: 13, color: AppColors.ink, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMedications() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _medications.isEmpty ? 'Médicaments' : 'Médicaments (${_medications.length})',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
              ),
              if (_medications.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () => _openMedicationDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_medications.isEmpty)
            AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(color: AppColors.roseSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.medication_outlined, size: 28, color: AppColors.rose),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Aucun médicament ajouté',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Une ordonnance doit contenir au moins un médicament.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () => _openMedicationDialog(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Ajouter un médicament'),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < _medications.length; i++) ...[
              _medicationCard(i, _medications[i]),
              if (i < _medications.length - 1) const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Widget _buildNotes() {
    return _section(
      icon: Icons.lightbulb_outline,
      color: AppColors.amberText,
      title: 'Recommandations',
      hint: 'facultatif',
      child: TextFormField(
        controller: _instructionsController,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: 'Ex : boire beaucoup d\'eau, éviter l\'exposition au soleil',
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ UI : barre du bas

  Widget _buildBottomBar() {
    final end = _treatmentEnd;
    final n = _medications.length;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (n > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '$n médicament${n > 1 ? 's' : ''}'
                  '${end != null ? ' · traitement jusqu\'au ${_short(end)}' : ''}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _submit,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(
                  _isSaving ? 'Envoi en cours...' : 'Créer et envoyer l\'ordonnance',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty || _isSaving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // ignore: use_build_context_synchronously
        if (await _confirmLeave() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Nouvelle ordonnance')),
        body: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHero(),
                      _buildMissingHospital(),
                      _buildDiagnosis(),
                      _buildTreatment(),
                      _buildMedications(),
                      _buildNotes(),
                    ],
                  ),
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================================================================
// Ajout et modification d'un médicament
// ====================================================================

class _MedicationDialog extends StatefulWidget {
  final Function(Medication) onAdd;

  /// Médicament à modifier (null : nouveau médicament).
  final Medication? initial;

  const _MedicationDialog({required this.onAdd, this.initial});

  @override
  State<_MedicationDialog> createState() => _MedicationDialogState();
}

class _MedicationDialogState extends State<_MedicationDialog> {
  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _durationController = TextEditingController(text: '7');
  final _instructionsController = TextEditingController();
  int _timesPerDay = 3;
  String? _error;

  static const List<int> _durationChoices = [3, 5, 7, 10, 14, 21, 30];
  static const List<String> _monthsShort = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    if (m != null) {
      _nameController.text = m.name;
      _dosageController.text = m.dosage;
      _durationController.text = '${m.durationDays ?? 7}';
      _instructionsController.text = (m.instructions ?? '').trim();
      _timesPerDay = m.timesPerDay ?? 3;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _durationController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  /// « jusqu'au 17 nov. » pour la durée saisie (rien si elle est invalide).
  String? get _endHint {
    final days = int.tryParse(_durationController.text.trim());
    if (days == null || days < 1 || days > 365) return null;
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day + days - 1);
    return 'Jusqu\'au ${d.day} ${_monthsShort[d.month - 1]}';
  }

  void _add() {
    final name = _nameController.text.trim();
    final dosage = _dosageController.text.trim();
    final days = int.tryParse(_durationController.text.trim());

    if (name.isEmpty || dosage.isEmpty) {
      setState(() => _error = 'Le nom et la dose sont obligatoires.');
      return;
    }
    if (days == null || days < 1 || days > 365) {
      setState(() => _error = 'La durée doit être comprise entre 1 et 365 jours.');
      return;
    }

    widget.onAdd(
      Medication(
        id: '',
        prescriptionId: '',
        name: name,
        dosage: dosage,
        frequency: '$_timesPerDay fois par jour',
        duration: days > 1 ? '$days jours' : '$days jour',
        instructions: _instructionsController.text.trim(),
        timesPerDay: _timesPerDay,
        durationDays: days,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    final selectedDays = int.tryParse(_durationController.text.trim());

    return AlertDialog(
      title: Text(editing ? 'Modifier le médicament' : 'Ajouter un médicament'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nom du médicament'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dosageController,
              decoration: const InputDecoration(labelText: 'Dose (ex: 500mg)'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Prises par jour',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 1, label: Text('1x')),
                  ButtonSegment(value: 2, label: Text('2x')),
                  ButtonSegment(value: 3, label: Text('3x')),
                  ButtonSegment(value: 4, label: Text('4x')),
                ],
                selected: {_timesPerDay},
                onSelectionChanged: (selection) {
                  setState(() => _timesPerDay = selection.first);
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Durée du traitement',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final d in _durationChoices)
                  ChoiceChip(
                    label: Text('$d j'),
                    selected: selectedDays == d,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _durationController.text = '$d'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Nombre de jours',
                suffixText: 'jours',
                helperText: _endHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _instructionsController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Comment l\'utiliser (ex: après les repas)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.dangerText, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _add,
          child: Text(editing ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}
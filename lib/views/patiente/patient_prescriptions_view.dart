import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/medication_model.dart';
import '../../models/prescription_model.dart';
import '../../services/prescription_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import 'patient_prescription_detail_view.dart';

/// Où en est le traitement d'une ordonnance.
enum _Phase { ongoing, finished, unknown }

/// Ce qu'on sait d'une ordonnance une fois ses médicaments connus.
class _Info {
  final List<Medication> meds;
  final DateTime? lastDay;
  final _Phase phase;
  final String specialty;

  const _Info({
    required this.meds,
    required this.lastDay,
    required this.phase,
    required this.specialty,
  });
}

/// Liste des ordonnances de la patiente : chiffres clés, recherche, filtre
/// (toutes, en cours, terminées), regroupement par mois et aperçu des médicaments.
class PatientPrescriptionsView extends StatefulWidget {
  /// true : utilisé comme contenu d'un onglet (sans barre du haut).
  final bool embedded;

  const PatientPrescriptionsView({super.key, this.embedded = false});

  @override
  State<PatientPrescriptionsView> createState() =>
      _PatientPrescriptionsViewState();
}

class _PatientPrescriptionsViewState extends State<PatientPrescriptionsView> {
  final PrescriptionService _prescriptionService = PrescriptionService();
  final TextEditingController _searchController = TextEditingController();

  List<Prescription> _prescriptions = [];
  Map<String, List<Medication>> _medications = {};
  Map<String, String> _specialties = {};
  bool _isLoading = true;
  String _query = '';

  /// 0 = toutes, 1 = en cours, 2 = terminées.
  int _tab = 0;

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
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ Données

  /// silent = true : rafraîchit sans remplacer la page par un spinner.
  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);

    final patientId = Supabase.instance.client.auth.currentUser?.id;
    if (patientId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final items = await _prescriptionService.getPatientPrescriptions(patientId);

    // Médicaments et spécialités de toutes les ordonnances : deux requêtes
    // pour la liste entière (et non une par ordonnance).
    final ids = items.map((p) => p.id).where((id) => id.isNotEmpty).toList();
    final doctorIds = items.map((p) => p.doctorId).where((id) => id.isNotEmpty).toSet().toList();
    final (meds, specialties) = await (
      _loadMedications(ids),
      _loadSpecialties(doctorIds),
    ).wait;

    if (!mounted) return;
    setState(() {
      _prescriptions = items;
      _medications = meds;
      _specialties = specialties;
      _isLoading = false;
    });
  }

  Future<Map<String, List<Medication>>> _loadMedications(List<String> ids) async {
    final out = <String, List<Medication>>{};
    if (ids.isEmpty) return out;
    try {
      final rows = await Supabase.instance.client
          .from('medications')
          .select()
          .inFilter('prescription_id', ids);
      for (final r in rows) {
        final m = Medication.fromMap(Map<String, dynamic>.from(r));
        out.putIfAbsent(m.prescriptionId, () => []).add(m);
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement des médicaments : $e');
    }
    return out;
  }

  Future<Map<String, String>> _loadSpecialties(List<String> doctorIds) async {
    final out = <String, String>{};
    if (doctorIds.isEmpty) return out;
    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id, specialty')
          .inFilter('id', doctorIds);
      for (final r in rows) {
        out[r['id'].toString()] = (r['specialty']?.toString() ?? '').trim();
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement des spécialités : $e');
    }
    return out;
  }

  // ------------------------------------------------------------ Aides

  DateTime _day(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  /// Dernier jour d'un traitement de `days` jours commencé le jour de l'ordonnance.
  DateTime _lastDayOf(DateTime created, int days) {
    final c = _day(created);
    return DateTime(c.year, c.month, c.day + days - 1);
  }

  String _short(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';

  _Info _infoOf(Prescription p) {
    final meds = _medications[p.id] ?? const <Medication>[];
    DateTime? last;
    for (final m in meds) {
      final days = m.durationDays;
      if (days == null || days < 1) continue;
      final d = _lastDayOf(p.createdAt, days);
      if (last == null || d.isAfter(last)) last = d;
    }
    final today = _day(DateTime.now());
    final phase = last == null
        ? _Phase.unknown
        : (last.isBefore(today) ? _Phase.finished : _Phase.ongoing);
    return _Info(
      meds: meds,
      lastDay: last,
      phase: phase,
      specialty: _specialties[p.doctorId] ?? '',
    );
  }

  Color _darker(Color c) => Color.lerp(c, Colors.black, 0.4)!;

  bool _matches(Prescription p, _Info i) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final haystack = [
      p.doctorName,
      p.diagnosis,
      p.treatment,
      i.specialty,
      ...i.meds.map((m) => m.name),
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }

  void _open(Prescription prescription) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PatientPrescriptionDetailView(prescription: prescription),
      ),
    ).then((_) {
      if (mounted) _load(silent: true);
    });
  }

  // ------------------------------------------------------------ Éléments d'interface

  Widget _buildHeader(int total, int ongoing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mes ordonnances',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            '$total ordonnance${total > 1 ? 's' : ''} · $ongoing en cours',
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, Color color, int value, String label) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink, height: 1),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _buildStats(int total, int ongoing, int unread) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _stat(Icons.description_outlined, AppColors.violet, total, 'Ordonnances'),
            const VerticalDivider(width: 1),
            _stat(Icons.medication_outlined, AppColors.success, ongoing, 'En cours'),
            const VerticalDivider(width: 1),
            _stat(Icons.mark_email_unread_outlined, AppColors.rose, unread, 'Nouvelles'),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: 'Rechercher un médecin, un médicament...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Effacer',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
      ),
    );
  }

  Widget _buildTabs(int all, int ongoing, int finished) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          ButtonSegment<int>(value: 0, label: Text('Toutes ($all)')),
          ButtonSegment<int>(value: 1, label: Text('En cours ($ongoing)')),
          ButtonSegment<int>(value: 2, label: Text('Terminées ($finished)')),
        ],
        selected: {_tab},
        onSelectionChanged: (set) => setState(() => _tab = set.first),
      ),
    );
  }

  Widget _dateBlock(Prescription p, Color tint) {
    final d = _day(p.createdAt);
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            d.day.toString().padLeft(2, '0'),
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: tint, height: 1),
          ),
          const SizedBox(height: 3),
          Text(_monthsShort[d.month - 1], style: TextStyle(fontSize: 12, color: tint)),
          Text('${d.year}', style: TextStyle(fontSize: 10.5, color: tint.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _medChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.violet.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.medication_outlined, size: 14, color: AppColors.violet),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.violet),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phasePill(_Info i) {
    if (i.phase == _Phase.unknown || i.lastDay == null) return const SizedBox.shrink();
    final ongoing = i.phase == _Phase.ongoing;
    final c = ongoing ? AppColors.success : AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ongoing ? Icons.timelapse : Icons.task_alt, size: 14, color: _darker(c)),
          const SizedBox(width: 5),
          Text(
            ongoing ? 'En cours · jusqu\'au ${_short(i.lastDay!)}' : 'Terminée le ${_short(i.lastDay!)}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _darker(c)),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Prescription p) {
    final i = _infoOf(p);
    final doctor = p.doctorName.trim();
    final diagnosis = p.diagnosis.trim();
    final railColor = !p.isRead
        ? AppColors.rose
        : (i.phase == _Phase.ongoing
            ? AppColors.success
            : (i.phase == _Phase.finished ? AppColors.muted : AppColors.border));
    final inactive = i.phase == _Phase.finished && p.isRead;
    final shown = i.meds.take(3).toList();
    final more = i.meds.length - shown.length;

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => _open(p),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: railColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _dateBlock(p, inactive ? AppColors.muted : AppColors.violet),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        doctor.isEmpty ? 'Ordonnance' : 'Dr $doctor',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: inactive ? AppColors.muted : AppColors.ink,
                                        ),
                                      ),
                                    ),
                                    if (!p.isRead)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: StatusPill(label: 'Nouvelle', color: AppColors.rose),
                                      ),
                                  ],
                                ),
                                if (i.specialty.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1),
                                    child: Text(
                                      i.specialty,
                                      style: const TextStyle(fontSize: 12.5, color: AppColors.rose),
                                    ),
                                  ),
                                if (diagnosis.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      diagnosis,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.3),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (shown.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final m in shown) _medChip('${m.name} ${m.dosage}'.trim()),
                            if (more > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.muted.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '+$more',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _phasePill(i),
                            ),
                          ),
                          if (i.meds.isNotEmpty)
                            Text(
                              '${i.meds.length} médicament${i.meds.length > 1 ? 's' : ''}',
                              style: const TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, color: AppColors.muted),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyBlock(IconData icon, String title, String message, {bool withButton = false}) {
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.roseSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppColors.rose),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
          ),
          if (withButton) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/patient-messages'),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Écrire à mon médecin'),
            ),
          ],
        ],
      ),
    );
  }

  /// Les cartes, regroupées par mois (« Novembre 2026 »).
  List<Widget> _buildGroups(List<Prescription> list) {
    final out = <Widget>[];
    String? currentMonth;
    for (var n = 0; n < list.length; n++) {
      final d = _day(list[n].createdAt);
      final raw = '${_monthsFull[d.month - 1]} ${d.year}';
      final month = raw[0].toUpperCase() + raw.substring(1);
      if (month != currentMonth) {
        if (currentMonth != null) out.add(const SizedBox(height: 16));
        out.add(SectionTitle(title: month));
        currentMonth = month;
      }
      out.add(_buildCard(list[n]));
      if (n < list.length - 1) out.add(const SizedBox(height: 12));
    }
    return out;
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const SkeletonList(avatar: false);
    }

    if (_prescriptions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.embedded) _buildHeader(0, 0),
          _emptyBlock(
            Icons.description_outlined,
            'Aucune ordonnance pour le moment',
            'Les ordonnances prescrites par votre médecin apparaîtront ici, avec leurs médicaments et la durée du traitement.',
            withButton: true,
          ),
        ],
      );
    }

    final infos = {for (final p in _prescriptions) p.id: _infoOf(p)};
    final ongoing = infos.values.where((i) => i.phase == _Phase.ongoing).length;
    final finished = infos.values.where((i) => i.phase == _Phase.finished).length;
    final unread = _prescriptions.where((p) => !p.isRead).length;

    final filtered = _prescriptions.where((p) {
      final i = infos[p.id]!;
      final okTab = _tab == 0 ||
          (_tab == 1 && i.phase == _Phase.ongoing) ||
          (_tab == 2 && i.phase == _Phase.finished);
      return okTab && _matches(p, i);
    }).toList();

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (widget.embedded) _buildHeader(_prescriptions.length, ongoing),
          _buildStats(_prescriptions.length, ongoing, unread),
          const SizedBox(height: 16),
          if (_prescriptions.length >= 4) ...[
            _buildSearch(),
            const SizedBox(height: 12),
          ],
          _buildTabs(_prescriptions.length, ongoing, finished),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            _emptyBlock(
              Icons.search_off,
              'Aucune ordonnance trouvée',
              _query.trim().isNotEmpty
                  ? 'Aucun résultat pour « ${_query.trim()} ». Essayez un autre nom.'
                  : (_tab == 1
                      ? 'Aucun traitement n\'est en cours.'
                      : 'Aucune ordonnance terminée pour le moment.'),
            )
          else
            ..._buildGroups(filtered),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('Mes ordonnances')),
      body: _buildContent(),
    );
  }
}
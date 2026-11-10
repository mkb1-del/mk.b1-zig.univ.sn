import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/follow_up_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/follow_up_chart.dart';
import '../../widgets/user_avatar.dart';
import '../messages/chat_view.dart';
import 'create_prescription_view.dart';
import 'doctor_prescriptions_view.dart';

/// Fiche d'une patiente suivie : coordonnées, actions rapides et suivi de santé
/// (en lecture seule) tel que la patiente l'a saisi.
class DoctorPatientDetailView extends StatefulWidget {
  final UserModel patient;

  const DoctorPatientDetailView({super.key, required this.patient});

  @override
  State<DoctorPatientDetailView> createState() => _DoctorPatientDetailViewState();
}

class _DoctorPatientDetailViewState extends State<DoctorPatientDetailView> {
  final FollowUpService _service = FollowUpService();

  PatientFollowUp? _followUp;
  bool _sharing = true;
  bool _isLoading = true;

  /// Échelle de couleur : 0 = vert ... 5 = rouge (inversée pour le moral).
  static const List<Color> _scale = [
    Color(0xFF2E9E6B),
    Color(0xFF8DBE3F),
    Color(0xFFF2B705),
    Color(0xFFF28C28),
    Color(0xFFE8603C),
    Color(0xFFE5484D),
  ];

  static const List<String> _weekdays = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
  ];
  static const List<String> _weekdayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  static const List<String> _months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// silent = true : rafraîchit sans remplacer les sections par un spinner.
  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final followUp = await _service.loadPatient(widget.patient.id);
    final sharing = await _service.isSharedWithMe(widget.patient.id);
    if (!mounted) return;
    setState(() {
      _followUp = followUp;
      _sharing = sharing;
      _isLoading = false;
    });
  }

  // ------------------------------------------------------------- Calculs

  Color _levelColor(int v, {bool reverse = false}) {
    final clamped = v.clamp(0, 5).toInt();
    return _scale[reverse ? 5 - clamped : clamped];
  }

  String _dateLabel(DateTime d) =>
      '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  List<DailyEntry> _lastDays(List<DailyEntry> entries, int days) {
    final now = DateTime.now();
    final limit = DateTime(now.year, now.month, now.day - (days - 1));
    return entries.where((e) => !e.day.isBefore(limit)).toList();
  }

  double _average(List<DailyEntry> list, int Function(DailyEntry) pick) {
    if (list.isEmpty) return 0;
    return list.map(pick).reduce((a, b) => a + b) / list.length;
  }

  // ------------------------------------------------------------- En-tête

  Widget _buildHeader() {
    final name = widget.patient.name;
    final attention = _followUp?.needsAttention ?? false;

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.plum.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: UserAvatar(name: name, url: widget.patient.avatarUrl, radius: 44),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.roseSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Patiente',
                  style: TextStyle(
                    color: AppColors.rose,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (attention)
                const StatusPill(label: 'À surveiller', color: AppColors.amber),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatView(
                    receiverId: widget.patient.id,
                    receiverName: widget.patient.name,
                    receiverAvatar: widget.patient.avatarUrl,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Envoyer un message'),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CreatePrescriptionView(
                          patientId: widget.patient.id,
                          patientName: widget.patient.name,
                        ),
                      ),
                    ).then((_) {
                      if (mounted) _load(silent: true);
                    });
                  },
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Prescrire'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DoctorPrescriptionsView(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Ordonnances'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --------------------------------------------------------- Suivi de santé

  Widget _averageColumn(String label, double value, {bool reverse = false}) {
    final color = _levelColor(value.round(), reverse: reverse);
    return Expanded(
      child: Column(
        children: [
          Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _buildWeekSummary(List<DailyEntry> week) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Moyennes des 7 derniers jours',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            week.isEmpty
                ? 'Aucun suivi saisi cette semaine.'
                : '${week.length} suivi${week.length > 1 ? 's' : ''} saisi${week.length > 1 ? 's' : ''} sur 7 jours · sur 5',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          if (week.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _averageColumn('Fatigue', _average(week, (e) => e.fatigue)),
                _averageColumn('Douleur', _average(week, (e) => e.pain)),
                _averageColumn('Moral', _average(week, (e) => e.mood), reverse: true),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _heatCell(DailyEntry? entry, int Function(DailyEntry) pick, bool reverse) {
    final value = entry == null ? null : pick(entry);
    final color = value == null ? null : _levelColor(value, reverse: reverse);

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: color ?? AppColors.border, width: 1.5),
      ),
      child: Center(
        child: Text(
          value == null ? '' : '$value',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildHeatmap(List<DailyEntry> entries) {
    final now = DateTime.now();
    final days = [
      for (var i = 6; i >= 0; i--) DateTime(now.year, now.month, now.day - i)
    ];

    DailyEntry? entryOf(DateTime d) {
      for (final e in entries) {
        if (e.day.year == d.year && e.day.month == d.month && e.day.day == d.day) {
          return e;
        }
      }
      return null;
    }

    Widget row(String label, int Function(DailyEntry) pick, {bool reverse = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 62,
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
            for (final d in days)
              Expanded(child: Center(child: _heatCell(entryOf(d), pick, reverse))),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Jour par jour',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          row('Fatigue', (e) => e.fatigue),
          row('Douleur', (e) => e.pain),
          row('Moral', (e) => e.mood, reverse: true),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 62),
              for (final d in days)
                Expanded(
                  child: Center(
                    child: Text(
                      _weekdayLetters[d.weekday - 1],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: d.day == now.day ? FontWeight.w800 : FontWeight.w500,
                        color: d.day == now.day ? AppColors.rose : AppColors.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Vert : tout va bien · Rouge : difficile. Pour le moral, vert = moral élevé. Un cercle vide = pas de saisie ce jour-là.',
            style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildAdherence(PatientFollowUp f) {
    final rate = f.adherenceRate;
    final tone = rate == null
        ? AppColors.muted
        : (rate >= 0.8
            ? AppColors.success
            : (rate >= 0.5 ? AppColors.amber : AppColors.danger));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Observance des traitements',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Prises cochées sur les 7 derniers jours complets, pour vos ordonnances.',
            style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35),
          ),
          const SizedBox(height: 14),
          if (rate == null)
            const Text(
              'Aucune prise prévue sur cette période.',
              style: TextStyle(color: AppColors.muted),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(rate * 100).round()} %',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: tone,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '${f.takenDoses} prises sur ${f.expectedDoses}',
                    style: const TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: rate,
                minHeight: 10,
                backgroundColor: AppColors.roseSoft,
                color: tone,
              ),
            ),
          ],
          if (f.activeTreatments.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            for (final t in f.activeTreatments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.medication_outlined,
                        size: 18, color: AppColors.rose),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t.dosage.isEmpty ? t.name : '${t.name} · ${t.dosage}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    Text(
                      '${t.timesPerDay}x/j · ${t.daysLeftFrom(DateTime.now())} j',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildComments(List<DailyEntry> entries) {
    final withComment = entries.where((e) => e.comment.isNotEmpty).take(3).toList();
    if (withComment.isEmpty) {
      return const AppCard(
        child: Text(
          'Aucun commentaire récent.',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < withComment.length; i++) ...[
            Text(
              _dateLabel(withComment[i].day),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.rose,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              withComment[i].comment,
              style: const TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: AppColors.ink,
                height: 1.4,
              ),
            ),
            if (i < withComment.length - 1) ...[
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildNextAppointment(Map<String, dynamic>? a) {
    if (a == null) {
      return const AppCard(
        child: Text(
          'Aucun rendez-vous à venir avec cette patiente.',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }

    final date = a['date']?.toString() ?? '';
    final time = (a['time']?.toString() ?? '');
    final dt = DateTime.tryParse(time.isEmpty ? date : '$date $time');
    final status = a['status']?.toString() ?? 'pending';
    final reason = (a['reason']?.toString() ?? '').trim();

    String label = date;
    if (dt != null) {
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      label = '${_dateLabel(dt)}${time.isEmpty ? '' : ' à $hh:$mm'}';
    }

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.rose.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_available_outlined, color: AppColors.rose),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
          StatusPill(
            label: StatusStyle.label(status),
            color: StatusStyle.color(status),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- Coordonnées

  Widget _infoRow(IconData icon, Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final email = ((widget.patient.email as String?) ?? '').trim();
    final phone = (widget.patient.phone ?? '').trim();
    final bio = (widget.patient.bio ?? '').trim();

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          _infoRow(
            Icons.phone_outlined,
            AppColors.teal,
            'Téléphone',
            phone.isEmpty ? 'Non renseigné' : phone,
          ),
          if (email.isNotEmpty) ...[
            const Divider(),
            _infoRow(Icons.mail_outline, AppColors.sky, 'Email', email),
          ],
          if (bio.isNotEmpty) ...[
            const Divider(),
            _infoRow(Icons.notes, AppColors.plum, 'À propos', bio),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ Page

  Widget _buildFollowUpSections() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final f = _followUp;
    if (f == null) return const SizedBox.shrink();

    // La patiente ne l'a pas ajouté à son équipe : le suivi n'est pas partagé.
    if (!_sharing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppCard(
            color: AppColors.roseSoft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: AppColors.rose),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cette patiente ne vous a pas ajouté à son équipe médicale : son suivi (symptômes, humeur, prises de médicaments) n\'est pas partagé avec vous. Vous pouvez lui écrire pour le lui proposer.',
                    style: TextStyle(fontSize: 13, color: AppColors.ink, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle(title: 'Prochain rendez-vous'),
          _buildNextAppointment(f.nextAppointment),
        ],
      );
    }

    final week = _lastDays(f.entries, 7);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Suivi de la semaine'),
        _buildWeekSummary(week),
        const SizedBox(height: 12),
        _buildHeatmap(f.entries),
        const SizedBox(height: 24),
        const SectionTitle(title: 'Évolution'),
        FollowUpChart(
          periods: const [7, 30],
          initialPeriod: 30,
          emptyMessage:
              'Cette patiente n\'a pas encore assez de suivis pour tracer une courbe.',
          points: [
            for (final e in f.entries)
              ChartPoint(
                day: e.day,
                fatigue: e.fatigue,
                pain: e.pain,
                mood: e.mood,
              ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle(title: 'Traitements'),
        _buildAdherence(f),
        const SizedBox(height: 24),
        const SectionTitle(title: 'Derniers commentaires'),
        _buildComments(f.entries),
        const SizedBox(height: 24),
        const SectionTitle(title: 'Prochain rendez-vous'),
        _buildNextAppointment(f.nextAppointment),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fiche patiente')),
      body: RefreshIndicator(
        color: AppColors.rose,
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildActions(),
            const SizedBox(height: 28),
            _buildFollowUpSections(),
            const SizedBox(height: 24),
            const SectionTitle(title: 'Coordonnées'),
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }
}
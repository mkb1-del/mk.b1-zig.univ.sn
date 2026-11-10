import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../services/care_reminder_service.dart';
import '../../services/prescription_service.dart';
import '../../theme/app_role.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/ribbon_background.dart';

/// Prises d'un médicament sur les 7 derniers jours.
class _MedStat {
  final String name;
  int expected = 0;
  int taken = 0;

  _MedStat(this.name);
}

/// Résultat du calcul d'observance sur 7 jours.
class _Adherence {
  final int expected;
  final int taken;

  /// Jour par jour, du plus ancien au plus récent.
  final List<DateTime> days;
  final List<int> dayExpected;
  final List<int> dayTaken;
  final List<_MedStat> medStats;

  const _Adherence({
    required this.expected,
    required this.taken,
    required this.days,
    required this.dayExpected,
    required this.dayTaken,
    required this.medStats,
  });

  static const _Adherence empty = _Adherence(
    expected: 0,
    taken: 0,
    days: [],
    dayExpected: [],
    dayTaken: [],
    medStats: [],
  );
}

/// Statistiques de la patiente : chiffres clés, évolution de l'humeur (7 jours,
/// 30 jours, 3 mois) et observance de ses traitements.
class StatisticsView extends StatefulWidget {
  const StatisticsView({super.key});

  @override
  State<StatisticsView> createState() => _StatisticsViewState();
}

class _StatisticsViewState extends State<StatisticsView> {
  final AuthService _authService = AuthService();
  final PrescriptionService _prescriptionService = PrescriptionService();
  final CareReminderService _care = CareReminderService();

  static const List<String> _dayLabels = [
    'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'
  ];
  static const List<String> _months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];

  // Humeur : 0 = très bien ... 4 = difficile (mêmes libellés que l'accueil).
  static const List<IconData> _moodIcons = [
    Icons.sentiment_very_satisfied,
    Icons.sentiment_satisfied,
    Icons.sentiment_neutral,
    Icons.sentiment_dissatisfied,
    Icons.sentiment_very_dissatisfied,
  ];
  static const List<String> _moodLabels = [
    'Très bien',
    'Bien',
    'Moyen',
    'Fatiguée',
    'Difficile',
  ];

  /// Couleurs de l'humeur : vert (très bien) vers rouge (difficile).
  static const List<Color> _moodScale = [
    Color(0xFF2E9E6B),
    Color(0xFF8DBE3F),
    Color(0xFFF2B705),
    Color(0xFFF28C28),
    Color(0xFFE5484D),
  ];

  bool _isLoading = true;
  bool _hasError = false;

  int _prescriptions = 0;
  int _appointments = 0;
  int _consultations = 0;
  int _symptoms = 0;
  int _moodDays = 0;
  int _dosesExpected = 0;
  int _dosesTaken = 0;

  /// Date (aaaa-mm-jj) -> humeur de 0 à 4.
  Map<String, int> _moodByDate = {};
  int _moodPeriod = 7;

  /// Observance jour par jour (du plus ancien au plus récent) et par médicament.
  List<DateTime> _adhDays = [];
  List<int> _adhExpected = [];
  List<int> _adhTaken = [];
  List<_MedStat> _medStats = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// silent = true : rafraîchit sans remplacer la page par un spinner.
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    try {
      final patient = await _authService.getCurrentUser();
      if (patient == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final id = patient.id;
      final client = Supabase.instance.client;
      final now = DateTime.now();

      // Les cinq lectures sont indépendantes : elles sont lancées ensemble
      // (le temps d'attente est celui de la plus lente, et non leur somme).
      final (prescriptions, appointments, symptoms, allMoods, adherence) = await (
        _prescriptionService.getPatientPrescriptions(id),
        client.from('appointments').select('id, status').eq('patient_id', id),
        _countSymptomDays(client, id),
        client.from('mood_entries').select('entry_date, mood').eq('patient_id', id),
        _loadAdherence(id, now),
      ).wait;

      final consultations =
          appointments.where((a) => a['status'] == 'completed').length;

      final moodByDate = <String, int>{
        for (final m in allMoods)
          if (m['mood'] != null) m['entry_date'].toString(): (m['mood'] as num).toInt(),
      };

      if (!mounted) return;
      setState(() {
        _prescriptions = prescriptions.length;
        _appointments = appointments.length;
        _consultations = consultations;
        _symptoms = symptoms;
        _moodDays = allMoods.length;
        _moodByDate = moodByDate;
        _dosesExpected = adherence.expected;
        _dosesTaken = adherence.taken;
        _adhDays = adherence.days;
        _adhExpected = adherence.dayExpected;
        _adhTaken = adherence.dayTaken;
        _medStats = adherence.medStats;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erreur chargement statistiques: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  /// Nombre de jours de suivi des symptômes (0 si la table est indisponible).
  Future<int> _countSymptomDays(SupabaseClient client, String id) async {
    try {
      final res = await client.from('symptoms').select('date').eq('patient_id', id);
      return res.length;
    } catch (e) {
      debugPrint('ℹ️ Symptômes non lus: $e');
      return 0;
    }
  }

  /// Observance sur 7 jours : les prises cochées sont lues en UNE requête
  /// (au lieu d'une par jour), puis comparées aux prises prévues.
  Future<_Adherence> _loadAdherence(String id, DateTime now) async {
    final treatments = await _care.loadTreatments(id);
    if (treatments.isEmpty) return _Adherence.empty;

    final first = DateTime(now.year, now.month, now.day - 6);
    final (prefs, takenByDay) = await (
      _care.getPreferences(id),
      _care.loadTakenKeysByDay(id, first, now),
    ).wait;

    var expected = 0;
    var taken = 0;
    final days = <DateTime>[];
    final dayExpected = <int>[];
    final dayTaken = <int>[];
    final byMedication = <String, _MedStat>{};

    for (var i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day - i);
      final doses = _care.buildDoses(
        day: day,
        treatments: treatments,
        prefs: prefs,
        taken: takenByDay[CareReminderService.dateString(day)] ?? const <String>{},
      );
      // Aujourd'hui : seulement les prises dont l'heure est déjà passée.
      final due = i == 0 ? doses.where((d) => !d.time.isAfter(now)).toList() : doses;

      var dayTakenCount = 0;
      for (final dose in due) {
        final stat = byMedication.putIfAbsent(
          dose.treatment.medicationId,
          () => _MedStat(dose.treatment.name),
        );
        stat.expected++;
        if (dose.taken) {
          stat.taken++;
          dayTakenCount++;
        }
      }

      days.add(day);
      dayExpected.add(due.length);
      dayTaken.add(dayTakenCount);
      expected += due.length;
      taken += dayTakenCount;
    }

    final meds = byMedication.values.toList()
      ..sort((a, b) => _rate(a.taken, a.expected).compareTo(_rate(b.taken, b.expected)));

    return _Adherence(
      expected: expected,
      taken: taken,
      days: days,
      dayExpected: dayExpected,
      dayTaken: dayTaken,
      medStats: meds,
    );
  }

  // ------------------------------------------------------------------ Outils

  double _rate(int taken, int expected) => expected == 0 ? 0 : taken / expected;

  Color _tone(double rate) => rate >= 0.8
      ? AppColors.success
      : (rate >= 0.5 ? AppColors.amber : AppColors.danger);

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Les jours d'une période, du plus ancien au plus récent.
  List<DateTime> _daysOf(int period) {
    final t = _today;
    return [for (var i = period - 1; i >= 0; i--) DateTime(t.year, t.month, t.day - i)];
  }

  int? _moodOn(DateTime d) => _moodByDate[CareReminderService.dateString(d)];

  String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  // ------------------------------------------------------------------ Héros et compteurs

  Widget _buildHero() {
    return Container(
      width: double.infinity,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: const Stack(
          children: [
            Positioned(
              right: 14,
              bottom: -22,
              child: Opacity(
                opacity: 0.18,
                child: RibbonLogo(size: 120, color: Colors.white),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mes statistiques',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Votre suivi de santé en un coup d\'œil',
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    Widget row(StatCard a, StatCard b) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ],
        );

    return Column(
      children: [
        row(
          StatCard(
            icon: Icons.description_outlined,
            value: '$_prescriptions',
            label: 'Ordonnances',
            color: AppColors.violet,
          ),
          StatCard(
            icon: Icons.event_available_outlined,
            value: '$_appointments',
            label: 'Rendez-vous',
            color: AppColors.rose,
          ),
        ),
        const SizedBox(height: 12),
        row(
          StatCard(
            icon: Icons.medical_services_outlined,
            value: '$_consultations',
            label: 'Consultations',
            color: AppColors.teal,
          ),
          StatCard(
            icon: Icons.healing_outlined,
            value: '$_symptoms',
            label: 'Jours de suivi',
            color: AppColors.sky,
          ),
        ),
        const SizedBox(height: 12),
        row(
          StatCard(
            icon: Icons.favorite_border,
            value: '$_moodDays',
            label: 'Humeurs notées',
            color: AppColors.rose,
          ),
          StatCard(
            icon: Icons.medication_outlined,
            value: '$_dosesTaken',
            label: 'Prises cochées (7 j)',
            color: AppColors.plum,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ Humeur

  Widget _periodSelector() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment<int>(value: 7, label: Text('7 jours')),
          ButtonSegment<int>(value: 30, label: Text('30 jours')),
          ButtonSegment<int>(value: 90, label: Text('3 mois')),
        ],
        selected: {_moodPeriod},
        onSelectionChanged: (set) => setState(() => _moodPeriod = set.first),
      ),
    );
  }

  /// Barres colorées des 7 derniers jours, avec l'icône d'humeur sous chaque barre.
  Widget _buildMoodBars() {
    final days = _daysOf(7);

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          minY: 0,
          maxY: 5,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= days.length) return const SizedBox.shrink();
                  final mood = _moodOn(days[i]);
                  final isToday = i == days.length - 1;

                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          mood == null ? Icons.remove : _moodIcons[mood],
                          size: 20,
                          color: mood == null ? AppColors.muted : _moodScale[mood],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _dayLabels[days[i].weekday - 1],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                            color: isToday ? AppColors.rose : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final d = days[group.x];
                final mood = _moodOn(d);
                return BarTooltipItem(
                  '${_shortDate(d)}\n${mood == null ? 'Non noté' : _moodLabels[mood]}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.35,
                  ),
                );
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    // Plus la barre est haute, mieux vous vous sentiez.
                    toY: _moodOn(days[i]) == null ? 0.3 : (5 - _moodOn(days[i])!).toDouble(),
                    width: 24,
                    color: _moodOn(days[i]) == null
                        ? AppColors.border
                        : _moodScale[_moodOn(days[i])!],
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: 5,
                      color: AppColors.roseSoft.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _calendarCell(DateTime d, DateTime start, double size, double gap) {
    final today = _today;
    if (d.isBefore(start) || d.isAfter(today)) {
      return SizedBox(width: size + gap, height: size);
    }
    final mood = _moodOn(d);
    final isToday = d == today;

    return Padding(
      padding: EdgeInsets.only(right: gap),
      child: Tooltip(
        message: '${_shortDate(d)} : ${mood == null ? 'non noté' : _moodLabels[mood]}',
        triggerMode: TooltipTriggerMode.tap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: mood == null
                ? AppColors.border.withValues(alpha: 0.6)
                : _moodScale[mood],
            borderRadius: BorderRadius.circular(size * 0.25),
            border: isToday ? Border.all(color: AppColors.ink, width: 1.6) : null,
          ),
        ),
      ),
    );
  }

  /// Calendrier en cases colorées (une colonne par semaine) pour 30 jours et 3 mois.
  Widget _buildMoodCalendar() {
    final today = _today;
    final start = DateTime(today.year, today.month, today.day - (_moodPeriod - 1));
    // On aligne la première colonne sur un lundi.
    final aligned = DateTime(start.year, start.month, start.day - (start.weekday - 1));
    final totalDays = DateTime.utc(today.year, today.month, today.day)
            .difference(DateTime.utc(aligned.year, aligned.month, aligned.day))
            .inDays +
        1;
    final weeks = (totalDays / 7).ceil();

    return LayoutBuilder(
      builder: (context, constraints) {
        const labelWidth = 18.0;
        const gap = 3.0;
        final size = ((constraints.maxWidth - labelWidth) / weeks - gap)
            .clamp(8.0, 30.0)
            .toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var r = 0; r < 7; r++)
              Padding(
                padding: const EdgeInsets.only(bottom: gap),
                child: Row(
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: Text(
                        const ['L', 'M', 'M', 'J', 'V', 'S', 'D'][r],
                        style: const TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ),
                    for (var w = 0; w < weeks; w++)
                      _calendarCell(
                        DateTime(aligned.year, aligned.month, aligned.day + w * 7 + r),
                        start,
                        size,
                        gap,
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _moodLegend() {
    Widget dot(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        );

    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (var i = 0; i < _moodLabels.length; i++) dot(_moodScale[i], _moodLabels[i]),
        dot(AppColors.border, 'Non noté'),
      ],
    );
  }

  Widget _buildMoodCard() {
    final days = _daysOf(_moodPeriod);
    final values = [
      for (final d in days)
        if (_moodOn(d) != null) _moodOn(d)!,
    ];
    final hasData = values.isNotEmpty;

    // Moyenne
    final average = hasData ? values.reduce((a, b) => a + b) / values.length : 0.0;
    final averageIndex = average.round().clamp(0, 4).toInt();

    // Tendance : seconde moitié de la période comparée à la première.
    // Plus le chiffre est bas, mieux la patiente se sent.
    _TileTrend trend = const _TileTrend(Icons.remove, 'Peu de données', AppColors.muted);
    if (values.length >= 4) {
      final half = values.length ~/ 2;
      double mean(Iterable<int> list) => list.reduce((a, b) => a + b) / list.length;
      final diff = mean(values.skip(values.length - half)) - mean(values.take(half));
      if (diff.abs() < 0.5) {
        trend = const _TileTrend(Icons.trending_flat, 'Stable', AppColors.muted);
      } else if (diff < 0) {
        trend = const _TileTrend(Icons.trending_up, 'En amélioration', AppColors.success);
      } else {
        trend = const _TileTrend(Icons.trending_down, 'En baisse', AppColors.danger);
      }
    }

    final periodText = _moodPeriod >= 90 ? '3 mois' : '$_moodPeriod jours';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mon humeur',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _moodPeriod == 7
                ? 'Plus la barre est haute, mieux vous vous sentiez.'
                : 'Une case par jour : du vert (très bien) au rouge (difficile).',
            style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35),
          ),
          const SizedBox(height: 14),
          _periodSelector(),
          const SizedBox(height: 14),
          Row(
            children: [
              _InsightTile(
                label: 'Humeur moyenne',
                value: hasData ? _moodLabels[averageIndex] : '—',
                icon: hasData ? _moodIcons[averageIndex] : null,
                color: hasData ? _moodScale[averageIndex] : AppColors.muted,
                caption: 'sur $periodText',
              ),
              const SizedBox(width: 8),
              _InsightTile(
                label: 'Jours notés',
                value: '${values.length}',
                unit: '/$_moodPeriod',
                color: AppColors.rose,
                caption: values.isEmpty
                    ? 'Aucun pour l\'instant'
                    : '${(values.length * 100 / _moodPeriod).round()} % des jours',
              ),
              const SizedBox(width: 8),
              _InsightTile(
                label: 'Tendance',
                value: trend.label,
                icon: trend.icon,
                color: trend.color,
                caption: 'sur $periodText',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasData)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Notez votre humeur depuis l\'accueil pour voir votre évolution.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ),
            )
          else ...[
            _moodPeriod == 7 ? _buildMoodBars() : _buildMoodCalendar(),
            const SizedBox(height: 14),
            _moodLegend(),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ Observance

  /// Jours complets d'affilée (tous les médicaments prévus ont été cochés).
  int _streak() {
    var count = 0;
    for (var i = _adhDays.length - 1; i >= 0; i--) {
      final expected = _adhExpected[i];
      if (expected == 0) {
        // Aujourd'hui sans prise encore due : on ne casse pas la série.
        if (i == _adhDays.length - 1) continue;
        break;
      }
      if (_adhTaken[i] < expected) break;
      count++;
    }
    return count;
  }

  Widget _buildAdherenceBars() {
    final days = _adhDays;

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          minY: 0,
          maxY: 100,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 50,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.black.withValues(alpha: 0.07),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: 80,
                color: AppColors.success.withValues(alpha: 0.75),
                strokeWidth: 1.5,
                dashArray: [6, 4],
              ),
            ],
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: 50,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt()} %',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= days.length) return const SizedBox.shrink();
                  final isToday = i == days.length - 1;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _dayLabels[days[i].weekday - 1],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                        color: isToday ? AppColors.rose : AppColors.muted,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final i = group.x;
                final expected = _adhExpected[i];
                return BarTooltipItem(
                  '${_shortDate(days[i])}\n${expected == 0 ? 'Aucune prise prévue' : '${_adhTaken[i]}/$expected prises'}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.35,
                  ),
                );
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: _adhExpected[i] == 0
                        ? 4
                        : _rate(_adhTaken[i], _adhExpected[i]) * 100,
                    width: 22,
                    color: _adhExpected[i] == 0
                        ? AppColors.border
                        : _tone(_rate(_adhTaken[i], _adhExpected[i])),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: 100,
                      color: AppColors.roseSoft.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicationList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Par médicament',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        for (final m in _medStats)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.ink),
                      ),
                    ),
                    Text(
                      '${m.taken}/${m.expected}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _tone(_rate(m.taken, m.expected)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _rate(m.taken, m.expected),
                    minHeight: 7,
                    backgroundColor: AppColors.roseSoft,
                    color: _tone(_rate(m.taken, m.expected)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAdherenceCard() {
    final hasData = _dosesExpected > 0;
    final rate = _rate(_dosesTaken, _dosesExpected);
    final percent = (rate * 100).round();
    final tone = _tone(rate);
    final streak = _streak();

    String message;
    if (rate >= 0.8) {
      message = 'Excellent suivi, continuez ainsi.';
    } else if (rate >= 0.5) {
      message = 'Bon suivi. Quelques oublis : vos rappels peuvent vous aider.';
    } else {
      message = 'Pensez à activer vos rappels pour ne rien oublier.';
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Suivi de mes traitements',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Prises cochées sur les 7 derniers jours.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          if (!hasData)
            const Text(
              'Aucune prise prévue sur cette période. Vos traitements apparaîtront ici dès qu\'une ordonnance est active.',
              style: TextStyle(color: AppColors.muted, height: 1.4),
            )
          else ...[
            Row(
              children: [
                _RingGauge(progress: rate, color: tone, label: '$percent %'),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_dosesTaken prises sur $_dosesExpected',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.ink,
                          height: 1.4,
                        ),
                      ),
                      if (streak > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.local_fire_department_outlined,
                              size: 18,
                              color: AppColors.amber,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '$streak jour${streak > 1 ? 's' : ''} complet${streak > 1 ? 's' : ''} d\'affilée',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.amberText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildAdherenceBars(),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 18,
                  height: 2,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Objectif : 80 % des prises',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
            if (_medStats.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 16),
              _buildMedicationList(),
            ],
            if (rate < 0.8) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/reminders'),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Régler mes rappels'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ Page

  Widget _buildContent() {
    if (_isLoading) {
      return const SkeletonPage();
    }

    if (_hasError) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Impossible de charger vos statistiques',
        message: 'Vérifiez votre connexion internet puis réessayez.',
        actionLabel: 'Réessayer',
        onAction: _load,
      );
    }

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildHero(),
          const SizedBox(height: 24),
          const SectionTitle(title: 'En un coup d\'œil'),
          _buildStatsGrid(),
          const SizedBox(height: 24),
          _buildMoodCard(),
          const SizedBox(height: 16),
          _buildAdherenceCard(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: _buildContent(),
    );
  }
}

/// Tendance affichée dans une tuile.
class _TileTrend {
  final IconData icon;
  final String label;
  final Color color;

  const _TileTrend(this.icon, this.label, this.color);
}

/// Petite tuile de synthèse : un titre, une valeur, une légende.
class _InsightTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Color color;
  final String caption;

  const _InsightTile({
    required this.label,
    required this.value,
    required this.color,
    required this.caption,
    this.unit,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: color),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  if (unit != null)
                    Text(
                      unit!,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}

/// Jauge circulaire de progression, avec le pourcentage au centre.
class _RingGauge extends StatelessWidget {
  final double progress;
  final Color color;
  final String label;

  const _RingGauge({
    required this.progress,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      height: 108,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(108, 108),
            painter: _RingPainter(progress: progress, color: color),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    final track = Paint()
      ..color = AppColors.roseSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);

    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

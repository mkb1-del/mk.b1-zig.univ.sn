import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_widgets.dart';

/// Une journée de suivi (valeurs de 0 à 5).
class ChartPoint {
  final DateTime day;
  final int fatigue;
  final int pain;
  final int mood;

  const ChartPoint({
    required this.day,
    required this.fatigue,
    required this.pain,
    required this.mood,
  });

  /// Journée à surveiller : douleur ou fatigue élevées, ou moral très bas.
  bool get needsAttention => pain >= 4 || fatigue >= 4 || mood <= 1;
}

enum _Metric { fatigue, pain, mood }

/// Une colonne de la grille : un jour (7 ou 30 jours) ou une semaine (3 mois).
class _Col {
  final DateTime from;
  final DateTime to;
  final double? fatigue;
  final double? pain;
  final double? mood;
  final int count;

  const _Col({
    required this.from,
    required this.to,
    required this.fatigue,
    required this.pain,
    required this.mood,
    required this.count,
  });

  bool get isWeek => to.difference(from).inDays > 0;

  double? value(_Metric m) {
    switch (m) {
      case _Metric.fatigue:
        return fatigue;
      case _Metric.pain:
        return pain;
      case _Metric.mood:
        return mood;
    }
  }
}

class _Trend {
  final IconData icon;
  final String label;
  final Color color;

  const _Trend(this.icon, this.label, this.color);
}

/// Suivi de la fatigue, de la douleur et du moral, présenté comme un outil
/// de suivi clinique :
///
/// - un **résumé en mots** (« Fatigue légère, en baisse ») ;
/// - une **grille de couleurs** : une case par jour, du vert (bien) au rouge
///   (difficile), avec le chiffre dans la case ;
/// - le **détail d'un jour** en touchant sa case ;
/// - une **courbe** seulement à la demande, avec des zones de couleur.
class FollowUpChart extends StatefulWidget {
  final List<ChartPoint> points;

  /// Périodes proposées, en jours.
  final List<int> periods;
  final int initialPeriod;
  final String title;
  final String emptyMessage;

  const FollowUpChart({
    super.key,
    required this.points,
    this.periods = const [7, 30, 90],
    this.initialPeriod = 30,
    this.title = 'Évolution',
    this.emptyMessage =
        'Pas assez de suivis sur cette période. Il en faut au moins 2 pour afficher l\'évolution.',
  });

  @override
  State<FollowUpChart> createState() => _FollowUpChartState();
}

class _FollowUpChartState extends State<FollowUpChart> {
  /// 0 = très bien ... 5 = très difficile (inversé pour le moral).
  static const List<Color> _scale = [
    Color(0xFF2E9E6B),
    Color(0xFF8DBE3F),
    Color(0xFFF2C94C),
    Color(0xFFF28C28),
    Color(0xFFE8603C),
    Color(0xFFE5484D),
  ];
  static const Color _missing = Color(0xFFF1E8EC);

  static const List<String> _symptomWords = [
    'Aucune', 'Très légère', 'Légère', 'Modérée', 'Forte', 'Très forte'
  ];
  static const List<String> _moodWords = [
    'Très bas', 'Bas', 'Moyen', 'Correct', 'Bon', 'Très bon'
  ];
  static const List<String> _weekdays = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
  ];
  static const List<String> _months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];

  static const List<_Metric> _metrics = [_Metric.fatigue, _Metric.pain, _Metric.mood];

  late int _period;
  int? _selected;
  _Metric? _curve;

  @override
  void initState() {
    super.initState();
    _period = widget.periods.contains(widget.initialPeriod)
        ? widget.initialPeriod
        : widget.periods.first;
  }

  // ------------------------------------------------------------------ Aides

  String _name(_Metric m) {
    switch (m) {
      case _Metric.fatigue:
        return 'Fatigue';
      case _Metric.pain:
        return 'Douleur';
      case _Metric.mood:
        return 'Moral';
    }
  }

  int _intValue(ChartPoint p, _Metric m) {
    switch (m) {
      case _Metric.fatigue:
        return p.fatigue;
      case _Metric.pain:
        return p.pain;
      case _Metric.mood:
        return p.mood;
    }
  }

  /// Le mot qui décrit un niveau (« Légère », « Bon »...).
  String _word(_Metric m, double v) {
    final i = v.round().clamp(0, 5).toInt();
    return (m == _Metric.mood ? _moodWords : _symptomWords)[i];
  }

  Color _levelColor(double v, _Metric m) {
    final i = v.round().clamp(0, 5).toInt();
    return _scale[m == _Metric.mood ? 5 - i : i];
  }

  Color _textOn(Color c) => c.computeLuminance() > 0.45 ? AppColors.ink : Colors.white;

  Color _darker(Color c) => Color.lerp(c, Colors.black, 0.5)!;

  String _fmt(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime get _start {
    final t = _today;
    return DateTime(t.year, t.month, t.day - (_period - 1));
  }

  String _dayLabel(DateTime d) =>
      '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  /// Les suivis de la période, un par jour, du plus ancien au plus récent.
  List<ChartPoint> get _inPeriod {
    final start = _start;
    final end = _today;
    final byDay = <String, ChartPoint>{};
    for (final p in widget.points) {
      final d = DateTime(p.day.year, p.day.month, p.day.day);
      if (d.isBefore(start) || d.isAfter(end)) continue;
      byDay['${d.year}-${d.month}-${d.day}'] =
          ChartPoint(day: d, fatigue: p.fatigue, pain: p.pain, mood: p.mood);
    }
    final list = byDay.values.toList()..sort((a, b) => a.day.compareTo(b.day));
    return list;
  }

  int _xOf(DateTime d) {
    final s = _start;
    return DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(s.year, s.month, s.day))
        .inDays;
  }

  /// Colonnes de la grille : un jour par colonne jusqu'à 30 jours, une semaine par colonne au-delà.
  List<_Col> _columns(List<ChartPoint> pts) {
    final start = _start;
    final today = _today;
    final cols = <_Col>[];

    if (_period <= 30) {
      final byDay = <String, ChartPoint>{
        for (final p in pts) '${p.day.year}-${p.day.month}-${p.day.day}': p,
      };
      for (var i = 0; i < _period; i++) {
        final d = DateTime(start.year, start.month, start.day + i);
        final p = byDay['${d.year}-${d.month}-${d.day}'];
        cols.add(_Col(
          from: d,
          to: d,
          fatigue: p?.fatigue.toDouble(),
          pain: p?.pain.toDouble(),
          mood: p?.mood.toDouble(),
          count: p == null ? 0 : 1,
        ));
      }
      return cols;
    }

    for (var i = 0; i * 7 < _period; i++) {
      final from = DateTime(start.year, start.month, start.day + i * 7);
      var to = DateTime(from.year, from.month, from.day + 6);
      if (to.isAfter(today)) to = today;
      final inWeek = pts.where((p) => !p.day.isBefore(from) && !p.day.isAfter(to)).toList();
      double? avg(int Function(ChartPoint) f) =>
          inWeek.isEmpty ? null : inWeek.fold<int>(0, (t, p) => t + f(p)) / inWeek.length;
      cols.add(_Col(
        from: from,
        to: to,
        fatigue: avg((p) => p.fatigue),
        pain: avg((p) => p.pain),
        mood: avg((p) => p.mood),
        count: inWeek.length,
      ));
    }
    return cols;
  }

  double? _average(List<ChartPoint> pts, _Metric m) {
    if (pts.isEmpty) return null;
    return pts.fold<int>(0, (t, p) => t + _intValue(p, m)) / pts.length;
  }

  int _hardDays(List<ChartPoint> pts, _Metric m) {
    return pts.where((p) {
      final v = _intValue(p, m);
      return m == _Metric.mood ? v <= 1 : v >= 4;
    }).length;
  }

  /// Tendance : seconde moitié de la période comparée à la première.
  _Trend _trend(List<ChartPoint> pts, _Metric m) {
    if (pts.length < 4) {
      return const _Trend(Icons.remove, 'peu de données', AppColors.muted);
    }
    final half = pts.length ~/ 2;
    double mean(Iterable<ChartPoint> list) =>
        list.fold<int>(0, (t, p) => t + _intValue(p, m)) / list.length;
    final diff = mean(pts.skip(pts.length - half)) - mean(pts.take(half));
    if (diff.abs() < 0.5) {
      return const _Trend(Icons.trending_flat, 'stable', AppColors.muted);
    }
    final up = diff > 0;
    final good = m == _Metric.mood ? up : !up;
    final label = m == _Metric.mood
        ? (up ? 'en amélioration' : 'en baisse')
        : (up ? 'en hausse' : 'en baisse');
    return _Trend(
      up ? Icons.trending_up : Icons.trending_down,
      label,
      good ? AppColors.successText : AppColors.dangerText,
    );
  }

  // ------------------------------------------------------------------ Résumé en mots

  Widget _summaryRow(_Metric m, List<ChartPoint> pts) {
    final avg = _average(pts, m);
    final trend = _trend(pts, m);
    final hard = _hardDays(pts, m);
    final color = avg == null ? AppColors.muted : _levelColor(avg, m);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 58,
            child: Text(
              _name(m),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              avg == null ? '—' : _word(m, avg),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _darker(color)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Icon(trend.icon, size: 15, color: trend.color),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    hard > 0
                        ? '${trend.label} · $hard jour${hard > 1 ? 's' : ''} difficile${hard > 1 ? 's' : ''}'
                        : trend.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: trend.color, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ Grille de couleurs

  Widget _cell(_Col col, _Metric m, int index, double w, double h, bool showNumber) {
    final v = col.value(m);
    final color = v == null ? _missing : _levelColor(v, m);
    final selected = _selected == index;
    final today = _today;
    final isToday = !col.from.isAfter(today) && !col.to.isBefore(today);

    return GestureDetector(
      onTap: () => setState(() => _selected = selected ? null : index),
      child: Container(
        width: w,
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(w > 14 ? 6 : 3),
          border: selected
              ? Border.all(color: AppColors.ink, width: 2)
              : (isToday ? Border.all(color: AppColors.rose, width: 1.6) : null),
        ),
        child: showNumber
            ? Text(
                v == null ? '–' : v.round().toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: v == null ? AppColors.muted : _textOn(color),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildGrid(List<_Col> cols) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const labelW = 64.0;
        final n = cols.length;
        final gap = n <= 14 ? 4.0 : 1.5;
        final cell = ((constraints.maxWidth - labelW - gap * (n - 1)) / n).floorToDouble().clamp(3.0, 60.0).toDouble();
        final cellH = n <= 14 ? 36.0 : 28.0;
        final showNumber = n <= 14;

        Widget header() {
          return Row(
            children: [
              const SizedBox(width: labelW),
              for (var i = 0; i < n; i++) ...[
                SizedBox(
                  width: cell,
                  child: _headerLabel(cols[i], i, n),
                ),
                if (i < n - 1) SizedBox(width: gap),
              ],
            ],
          );
        }

        return Column(
          children: [
            header(),
            const SizedBox(height: 4),
            for (final m in _metrics)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: labelW,
                      child: Text(
                        _name(m),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ),
                    for (var i = 0; i < n; i++) ...[
                      _cell(cols[i], m, i, cell, cellH, showNumber),
                      if (i < n - 1) SizedBox(width: gap),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _headerLabel(_Col col, int i, int n) {
    const style = TextStyle(fontSize: 10, color: AppColors.muted, height: 1.1);
    if (n <= 7) {
      return Text(
        '${_weekdays[col.from.weekday - 1].substring(0, 3)}\n${col.from.day}',
        textAlign: TextAlign.center,
        style: style,
      );
    }
    if (n <= 14) {
      return Text('${col.from.day}', textAlign: TextAlign.center, style: style);
    }
    final every = col.isWeek ? 3 : 5;
    if (i % every != 0) return const SizedBox(height: 12);
    return SizedBox(
      height: 12,
      child: OverflowBox(
        maxWidth: 40,
        child: Text(
          col.isWeek ? '${col.from.day}/${col.from.month}' : '${col.from.day}',
          textAlign: TextAlign.center,
          softWrap: false,
          style: style,
        ),
      ),
    );
  }

  Widget _legend() {
    Widget text(String t) =>
        Text(t, style: const TextStyle(fontSize: 11, color: AppColors.muted));

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            text('Bien'),
            const SizedBox(width: 6),
            for (final c in _scale)
              Container(
                width: 18,
                height: 10,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
              ),
            const SizedBox(width: 4),
            text('Difficile'),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 10,
              decoration: BoxDecoration(color: _missing, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 4),
            text('Non noté'),
          ],
        ),
      ],
    );
  }

  /// Détail du jour (ou de la semaine) touché dans la grille.
  Widget _buildSelectedDetail(List<_Col> cols) {
    final i = _selected;
    if (i == null || i >= cols.length) return const SizedBox.shrink();
    final col = cols[i];
    final title = col.isWeek
        ? 'Semaine du ${_shortDate(col.from)} au ${_shortDate(col.to)}'
        : _dayLabel(col.from);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.roseSoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title[0].toUpperCase() + title.substring(1),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          if (col.count == 0)
            const Text(
              'Aucun suivi ce jour-là.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            )
          else
            for (final m in _metrics)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(color: _levelColor(col.value(m)!, m), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_name(m)} : ',
                      style: const TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                    Text(
                      col.isWeek
                          ? '${_word(m, col.value(m)!)} (moyenne ${_fmt(col.value(m)!)}/5)'
                          : '${_word(m, col.value(m)!)} (${col.value(m)!.round()}/5)',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ Courbe (à la demande)

  Widget _buildCurveChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Voir la courbe :', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        for (final m in _metrics)
          ChoiceChip(
            label: Text(_name(m)),
            selected: _curve == m,
            visualDensity: VisualDensity.compact,
            onSelected: (on) => setState(() => _curve = on ? m : null),
          ),
      ],
    );
  }

  Widget _buildCurve(List<ChartPoint> pts, _Metric m) {
    final isMood = m == _Metric.mood;
    const maxGap = 3;

    final spots = <FlSpot>[];
    int? previous;
    for (final p in pts) {
      final x = _xOf(p.day);
      if (previous != null && x - previous > maxGap) spots.add(FlSpot.nullSpot);
      spots.add(FlSpot(x.toDouble(), _intValue(p, m).toDouble()));
      previous = x;
    }

    // Zones de couleur : vert (bien), orange (à surveiller), rouge (difficile).
    HorizontalRangeAnnotation band(double a, double b, Color c) =>
        HorizontalRangeAnnotation(y1: a, y2: b, color: c.withValues(alpha: 0.10));
    final bands = isMood
        ? [band(0, 1.5, _scale[5]), band(1.5, 3.5, _scale[3]), band(3.5, 5, _scale[0])]
        : [band(0, 1.5, _scale[0]), band(1.5, 3.5, _scale[3]), band(3.5, 5, _scale[5])];

    final avg = _average(pts, m);
    final interval = _period <= 7 ? 1.0 : (_period <= 30 ? 5.0 : 15.0);
    final words = isMood ? _moodWords : _symptomWords;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Courbe : ${_name(m).toLowerCase()}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            isMood
                ? 'Plus la courbe est haute, mieux vous vous sentiez.'
                : 'Plus la courbe est basse, mieux vous vous sentiez.',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 210,
            child: Padding(
              padding: const EdgeInsets.only(right: 12, top: 8),
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (_period - 1).toDouble(),
                  minY: 0,
                  maxY: 5,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: Colors.black.withValues(alpha: 0.06), strokeWidth: 1),
                  ),
                  rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: bands),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      if (avg != null)
                        HorizontalLine(
                          y: avg,
                          color: AppColors.ink.withValues(alpha: 0.45),
                          strokeWidth: 1.4,
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
                        reservedSize: 64,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final v = value.toInt();
                          if (v != 0 && v != 3 && v != 5) return const SizedBox.shrink();
                          return Text(
                            words[v],
                            style: const TextStyle(fontSize: 10, color: AppColors.muted),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: interval,
                        getTitlesWidget: (value, meta) {
                          if (value % 1 != 0) return const SizedBox.shrink();
                          final s = _start;
                          final d = DateTime(s.year, s.month, s.day + value.toInt());
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${d.day}/${d.month}',
                              style: const TextStyle(fontSize: 10, color: AppColors.muted),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touched) => [
                        for (final t in touched)
                          LineTooltipItem(
                            '${_shortDate(DateTime(_start.year, _start.month, _start.day + t.x.round()))}\n'
                            '${_word(m, t.y)} (${t.y.toInt()}/5)',
                            const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12, height: 1.3),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.2,
                      preventCurveOverShooting: true,
                      color: AppColors.ink.withValues(alpha: 0.55),
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: pts.length <= 45,
                        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                          radius: 4.5,
                          color: _levelColor(spot.y, m),
                          strokeWidth: 2,
                          strokeColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (avg != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Container(width: 18, height: 2, color: AppColors.ink.withValues(alpha: 0.45)),
                  const SizedBox(width: 6),
                  Text(
                    'Moyenne : ${_word(m, avg)} (${_fmt(avg)}/5)',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ Page

  Widget _buildPeriodSelector() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          for (final p in widget.periods)
            ButtonSegment<int>(value: p, label: Text(p >= 90 ? '3 mois' : '$p jours')),
        ],
        selected: {_period},
        onSelectionChanged: (set) => setState(() {
          _period = set.first;
          _selected = null;
        }),
      ),
    );
  }

  Widget _buildFooter(List<ChartPoint> pts) {
    final hard = pts.where((p) => p.needsAttention).length;
    final tracked = pts.length;
    return Row(
      children: [
        const Icon(Icons.event_available_outlined, size: 16, color: AppColors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Suivi renseigné $tracked jour${tracked > 1 ? 's' : ''} sur $_period',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
        if (hard > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$hard jour${hard > 1 ? 's' : ''} à surveiller',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.dangerText),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pts = _inPeriod;
    final cols = _columns(pts);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            _period >= 90
                ? 'Chaque case est une semaine : vert = bien, rouge = difficile.'
                : 'Chaque case est un jour : vert = bien, rouge = difficile.',
            style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35),
          ),
          const SizedBox(height: 14),
          if (widget.periods.length > 1) ...[
            _buildPeriodSelector(),
            const SizedBox(height: 16),
          ],
          if (pts.length < 2)
            SizedBox(
              height: 150,
              child: Center(
                child: Text(
                  widget.emptyMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ),
            )
          else ...[
            const Text(
              'En résumé',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            for (final m in _metrics) _summaryRow(m, pts),
            const SizedBox(height: 8),
            _buildGrid(cols),
            const SizedBox(height: 8),
            _legend(),
            _buildSelectedDetail(cols),
            const SizedBox(height: 14),
            _buildCurveChips(),
            if (_curve != null) _buildCurve(pts, _curve!),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _buildFooter(pts),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';

/// Un suivi quotidien : fatigue, douleur et moral de 0 à 5, plus un commentaire.
class _DailyEntry {
  final DateTime day;
  final int fatigue;
  final int pain;
  final int mood;
  final String comment;

  const _DailyEntry({
    required this.day,
    required this.fatigue,
    required this.pain,
    required this.mood,
    required this.comment,
  });

  /// Jour à surveiller : douleur ou fatigue élevées, ou moral très bas.
  bool get needsAttention => pain >= 4 || fatigue >= 4 || mood <= 1;
}

/// Historique du suivi quotidien de la patiente, du plus récent au plus ancien.
class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  List<_DailyEntry> _entries = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _filter = 'all';

  static const List<MapEntry<String, String>> _filters = [
    MapEntry('all', 'Tous'),
    MapEntry('7', '7 jours'),
    MapEntry('30', '30 jours'),
  ];

  static const List<String> _weekdays = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
  ];
  static const List<String> _months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];

  /// Même échelle que l'écran de saisie : 0 = vert ... 5 = rouge.
  static const List<Color> _scale = [
    Color(0xFF2E9E6B),
    Color(0xFF8DBE3F),
    Color(0xFFF2B705),
    Color(0xFFF28C28),
    Color(0xFFE8603C),
    Color(0xFFE5484D),
  ];

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
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final response = await Supabase.instance.client
          .from('symptoms')
          .select()
          .eq('patient_id', userId)
          .order('date', ascending: false);

      final entries = <_DailyEntry>[];
      for (final row in response) {
        final day = DateTime.tryParse(row['date']?.toString() ?? '');
        if (day == null) continue;
        entries.add(
          _DailyEntry(
            day: day,
            fatigue: (row['fatigue_level'] as num?)?.toInt() ?? 0,
            pain: (row['pain_level'] as num?)?.toInt() ?? 0,
            mood: (row['mood_level'] as num?)?.toInt() ?? 3,
            comment: (row['comment'] as String?)?.trim() ?? '',
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erreur chargement historique: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  // ------------------------------------------------------------- Calculs

  List<_DailyEntry> _since(int days) {
    final now = DateTime.now();
    final limit = DateTime(now.year, now.month, now.day - (days - 1));
    return _entries.where((e) => !e.day.isBefore(limit)).toList();
  }

  List<_DailyEntry> get _filtered {
    if (_filter == '7') return _since(7);
    if (_filter == '30') return _since(30);
    return _entries;
  }

  double _average(List<_DailyEntry> list, int Function(_DailyEntry) pick) {
    if (list.isEmpty) return 0;
    return list.map(pick).reduce((a, b) => a + b) / list.length;
  }

  Color _levelColor(num v, {bool reverse = false}) {
    final rounded = v.round().clamp(0, 5).toInt();
    return _scale[reverse ? 5 - rounded : rounded];
  }

  String _dateLabel(DateTime d) =>
      '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  Future<void> _openAdd() async {
    await Navigator.pushNamed(context, '/symptoms');
    if (mounted) _load(silent: true);
  }

  // ------------------------------------------------------------------ UI

  Widget _averageColumn(String label, double value, {bool reverse = false}) {
    final color = _levelColor(value, reverse: reverse);
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

  Widget _buildSummary() {
    final week = _since(7);

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
                ? 'Aucun suivi cette semaine.'
                : '${week.length} suivi${week.length > 1 ? 's' : ''} sur 7 jours · sur 5',
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

  Widget _levelChip(String label, int value, {bool reverse = false}) {
    final color = _levelColor(value, reverse: reverse);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label $value/5',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _buildItem(_DailyEntry e) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 15, color: AppColors.rose),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _dateLabel(e.day),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (e.needsAttention)
                const StatusPill(label: 'À surveiller', color: AppColors.amber),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _levelChip('Fatigue', e.fatigue),
              _levelChip('Douleur', e.pain),
              _levelChip('Moral', e.mood, reverse: true),
            ],
          ),
          if (e.comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              e.comment,
              style: const TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final f = _filters[index];
          return FilterChip(
            label: Text(f.value),
            selected: _filter == f.key,
            onSelected: (_) => setState(() => _filter = f.key),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const SkeletonList(avatar: false);
    }

    if (_hasError) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Impossible de charger l\'historique',
        message: 'Vérifiez votre connexion internet puis réessayez.',
        actionLabel: 'Réessayer',
        onAction: _load,
      );
    }

    if (_entries.isEmpty) {
      return EmptyState(
        icon: Icons.favorite_border,
        title: 'Aucun suivi enregistré',
        message:
            'Notez chaque jour votre fatigue, votre douleur et votre moral : cela aide votre médecin à mieux vous suivre.',
        actionLabel: 'Noter aujourd\'hui',
        onAction: _openAdd,
      );
    }

    final list = _filtered;

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildSummary(),
          ),
          const SizedBox(height: 16),
          _buildFilters(),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Aucun suivi sur cette période.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        _buildItem(list[i]),
                        if (i < list.length - 1) const SizedBox(height: 12),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique du suivi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.show_chart),
            tooltip: 'Graphiques',
            onPressed: () => Navigator.pushNamed(context, '/symptoms-history'),
          ),
        ],
      ),
      body: _buildContent(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        icon: const Icon(Icons.add),
        label: const Text('Noter aujourd\'hui'),
      ),
    );
  }
}

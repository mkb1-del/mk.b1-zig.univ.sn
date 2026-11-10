import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/follow_up_chart.dart';

/// Évolution de la fatigue, de la douleur et du moral (sur 7 jours, 30 jours ou
/// 3 mois), suivie de la liste des entrées récentes.
class SymptomsHistoryView extends StatefulWidget {
  const SymptomsHistoryView({super.key});

  @override
  State<SymptomsHistoryView> createState() => _SymptomsHistoryViewState();
}

class _SymptomsHistoryViewState extends State<SymptomsHistoryView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _symptoms = [];
  List<ChartPoint> _chartPoints = [];
  bool _isLoading = true;
  bool _hasError = false;


  /// Échelle de couleur : 0 = vert ... 5 = rouge (inversée pour le moral).
  static const List<Color> _scale = [
    Color(0xFF2E9E6B),
    Color(0xFF8DBE3F),
    Color(0xFFF2B705),
    Color(0xFFF28C28),
    Color(0xFFE8603C),
    Color(0xFFE5484D),
  ];

  static const List<String> _months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
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
      final me = _supabase.auth.currentUser?.id;
      if (me == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      // 3 mois de suivi pour le graphique ; la liste en garde les 30 derniers.
      final since = DateTime.now().subtract(const Duration(days: 89));
      final sinceText =
          '${since.year}-${since.month.toString().padLeft(2, '0')}-${since.day.toString().padLeft(2, '0')}';
      final res = await _supabase
          .from('symptoms')
          .select()
          .eq('patient_id', me)
          .gte('date', sinceText)
          .order('date', ascending: true);
      if (!mounted) return;

      final all = List<Map<String, dynamic>>.from(res);
      setState(() {
        _symptoms = all.length > 30 ? all.sublist(all.length - 30) : all;
        _chartPoints = [
          for (final row in all)
            if (_toPoint(row) != null) _toPoint(row)!,
        ];
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erreur historique symptômes : $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  ChartPoint? _toPoint(Map<String, dynamic> row) {
    final d = DateTime.tryParse(row['date'].toString());
    if (d == null) return null;
    return ChartPoint(
      day: DateTime(d.year, d.month, d.day),
      fatigue: (row['fatigue_level'] as num?)?.toInt() ?? 0,
      pain: (row['pain_level'] as num?)?.toInt() ?? 0,
      mood: (row['mood_level'] as num?)?.toInt() ?? 0,
    );
  }

  String _formatDate(dynamic v) {
    final d = DateTime.tryParse(v.toString()) ?? DateTime.now();
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  Color _levelColor(int v, {bool reverse = false}) {
    final clamped = v.clamp(0, 5).toInt();
    return _scale[reverse ? 5 - clamped : clamped];
  }

  Future<void> _openAdd() async {
    await Navigator.pushNamed(context, '/symptoms');
    if (mounted) _load(silent: true);
  }

  // ------------------------------------------------------------------ UI

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

  Widget _buildEntryCard(Map<String, dynamic> s) {
    final fatigue = (s['fatigue_level'] as num?)?.toInt() ?? 0;
    final pain = (s['pain_level'] as num?)?.toInt() ?? 0;
    final mood = (s['mood_level'] as num?)?.toInt() ?? 3;
    final comment = ((s['comment'] as String?) ?? '').trim();

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
                  _formatDate(s['date']),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _levelChip('Fatigue', fatigue),
              _levelChip('Douleur', pain),
              _levelChip('Moral', mood, reverse: true),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              comment,
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

  Widget _buildContent() {
    if (_isLoading) {
      return const SkeletonPage();
    }

    if (_hasError) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Impossible de charger le suivi',
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          FollowUpChart(points: _chartPoints),
          const SizedBox(height: 24),
          SectionTitle(title: 'Entrées récentes (${_symptoms.length})'),
          if (_symptoms.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Aucune donnée pour le moment.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            )
          else
            for (final s in _symptoms.reversed) ...[
              _buildEntryCard(s),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Graphiques du suivi')),
      body: _buildContent(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        icon: const Icon(Icons.add),
        label: const Text('Noter aujourd\'hui'),
      ),
    );
  }
}

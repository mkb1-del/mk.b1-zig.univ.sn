import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/app_errors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/ribbon_background.dart';
import '../../widgets/skeleton.dart';

/// Description d'une échelle de 0 à 5 : mots et exemples pour chaque niveau.
class _Scale {
  final String title;
  final String question;
  final IconData icon;
  final bool reverse; // true : 5 = très bien (moral)
  final String low;
  final String high;
  final List<String> words;
  final List<String> hints;

  const _Scale({
    required this.title,
    required this.question,
    required this.icon,
    required this.reverse,
    required this.low,
    required this.high,
    required this.words,
    required this.hints,
  });
}

/// Suivi quotidien : fatigue, douleur et moral de 0 à 5, symptômes signalés et
/// commentaire. Une saisie par jour (créée ou mise à jour), pour aujourd'hui ou
/// l'un des 6 jours précédents.
class SymptomsView extends StatefulWidget {
  const SymptomsView({super.key});

  @override
  State<SymptomsView> createState() => _SymptomsViewState();
}

class _SymptomsViewState extends State<SymptomsView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _commentController = TextEditingController();

  // Réponses : null tant que la patiente n'a pas répondu (pas de valeur par défaut).
  int? _fatigue;
  int? _pain;
  int? _mood;
  final Set<String> _tags = {};

  bool _loading = true;
  bool _isSaving = false;
  bool _hasExisting = false;
  bool _dirty = false;

  late DateTime _selected;

  /// Saisies des 7 derniers jours : date (aaaa-mm-jj) -> ligne.
  Map<String, Map<String, dynamic>> _week = {};

  /// 0 = vert (tout va bien) ... 5 = rouge (très difficile).
  static const List<Color> _scale = [
    Color(0xFF2E9E6B),
    Color(0xFF8DBE3F),
    Color(0xFFF2C94C),
    Color(0xFFF28C28),
    Color(0xFFE8603C),
    Color(0xFFE5484D),
  ];

  static const _fatigueScale = _Scale(
    title: 'Fatigue',
    question: 'Quel a été votre niveau de fatigue ?',
    icon: Icons.bedtime_outlined,
    reverse: false,
    low: 'Aucune',
    high: 'Extrême',
    words: ['Aucune', 'Très légère', 'Légère', 'Modérée', 'Forte', 'Très forte'],
    hints: [
      'Je me sens en forme.',
      'Je fais tout normalement.',
      'Un peu fatiguée, mais je fais mes activités.',
      'Je dois me reposer plusieurs fois dans la journée.',
      'J\'ai du mal à faire mes activités habituelles.',
      'Je suis épuisée, je reste allongée.',
    ],
  );

  static const _painScale = _Scale(
    title: 'Douleur',
    question: 'Quel a été votre niveau de douleur ?',
    icon: Icons.healing_outlined,
    reverse: false,
    low: 'Aucune',
    high: 'Insupportable',
    words: ['Aucune', 'Très légère', 'Légère', 'Modérée', 'Forte', 'Insupportable'],
    hints: [
      'Je n\'ai pas mal.',
      'Je la remarque à peine.',
      'Gênante, mais supportable.',
      'Elle m\'empêche parfois de faire mes activités.',
      'Elle est difficile à supporter.',
      'C\'est la pire douleur que j\'aie connue.',
    ],
  );

  static const _moodScale = _Scale(
    title: 'Moral',
    question: 'Comment a été votre moral ?',
    icon: Icons.sentiment_satisfied_outlined,
    reverse: true,
    low: 'Très bas',
    high: 'Très bon',
    words: ['Très bas', 'Bas', 'Moyen', 'Correct', 'Bon', 'Très bon'],
    hints: [
      'Je me sens très mal moralement.',
      'Je me sens triste ou découragée.',
      'Mon moral change beaucoup.',
      'Je me sens plutôt bien.',
      'Je me sens bien.',
      'Je me sens très bien.',
    ],
  );

  static const List<String> _tagOptions = [
    'Nausées',
    'Vomissements',
    'Sommeil perturbé',
    'Perte d\'appétit',
    'Fourmillements',
    'Bouffées de chaleur',
    'Essoufflement',
    'Fièvre',
  ];

  static const String _tagPrefix = 'Symptômes signalés : ';

  static const List<String> _weekdays = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
  ];
  static const List<String> _months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
  ];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _selected = DateTime(n.year, n.month, n.day);
    _loadWeek();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ Données

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

  int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(a.year, a.month, a.day).difference(DateTime.utc(b.year, b.month, b.day)).inDays;

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic>? _entryOf(DateTime d) => _week[_dateStr(d)];

  Future<void> _loadWeek() async {
    try {
      final me = _supabase.auth.currentUser?.id;
      if (me == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final since = _addDays(_today, -6);
      final res = await _supabase
          .from('symptoms')
          .select()
          .eq('patient_id', me)
          .gte('date', _dateStr(since));
      final map = <String, Map<String, dynamic>>{
        for (final r in res) r['date'].toString(): Map<String, dynamic>.from(r),
      };
      if (!mounted) return;
      setState(() {
        _week = map;
        _loading = false;
      });
      _applyDate(_selected);
    } catch (e) {
      AppErrors.log('chargement du suivi', e);
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Affiche la saisie enregistrée pour ce jour, ou un formulaire vierge.
  void _applyDate(DateTime d) {
    final row = _entryOf(d);
    setState(() {
      _selected = d;
      _dirty = false;
      _tags.clear();
      if (row == null) {
        _fatigue = null;
        _pain = null;
        _mood = null;
        _commentController.clear();
        _hasExisting = false;
      } else {
        _fatigue = (row['fatigue_level'] as num?)?.toInt();
        _pain = (row['pain_level'] as num?)?.toInt();
        _mood = (row['mood_level'] as num?)?.toInt();
        _hasExisting = true;
        _parseComment((row['comment'] as String?) ?? '');
      }
    });
  }

  /// Sépare les symptômes cochés du commentaire libre.
  void _parseComment(String raw) {
    final m = RegExp(r'^Symptômes signalés : ([^.]+)\.\s*(.*)$', dotAll: true).firstMatch(raw);
    if (m == null) {
      _commentController.text = raw;
      return;
    }
    for (final t in m.group(1)!.split(', ')) {
      if (_tagOptions.contains(t)) _tags.add(t);
    }
    _commentController.text = m.group(2) ?? '';
  }

  String _composeComment() {
    final free = _commentController.text.trim();
    if (_tags.isEmpty) return free;
    final ordered = _tagOptions.where(_tags.contains).join(', ');
    return '$_tagPrefix$ordered.${free.isEmpty ? '' : ' $free'}';
  }

  Future<void> _save() async {
    final f = _fatigue, p = _pain, m = _mood;
    if (f == null || p == null || m == null) return;

    setState(() => _isSaving = true);
    try {
      final me = _supabase.auth.currentUser?.id;
      if (me == null) return;
      final comment = _composeComment();

      // upsert : crée OU met à jour la saisie de ce jour
      await _supabase.from('symptoms').upsert(
        {
          'patient_id': me,
          'date': _dateStr(_selected),
          'fatigue_level': f,
          'pain_level': p,
          'mood_level': m,
          'comment': comment,
        },
        onConflict: 'patient_id,date',
      );

      if (!mounted) return;
      setState(() {
        _week[_dateStr(_selected)] = {
          'date': _dateStr(_selected),
          'fatigue_level': f,
          'pain_level': p,
          'mood_level': m,
          'comment': comment,
        };
        _hasExisting = true;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Suivi du ${_selected.day} ${_months[_selected.month - 1]} enregistré'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      AppErrors.log('sauvegarde du suivi', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ${AppErrors.message(e)}'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ------------------------------------------------------------------ Aides

  int get _answered => [_fatigue, _pain, _mood].where((v) => v != null).length;

  Color _levelColor(int v, bool reverse) => _scale[reverse ? 5 - v : v];

  Color _darker(Color c) => Color.lerp(c, Colors.black, 0.5)!;

  /// Gravité d'une journée (0 à 5) : le pire des trois indicateurs.
  int _severity(Map<String, dynamic> row) {
    final f = (row['fatigue_level'] as num?)?.toInt() ?? 0;
    final p = (row['pain_level'] as num?)?.toInt() ?? 0;
    final m = (row['mood_level'] as num?)?.toInt() ?? 5;
    return [f, p, 5 - m].reduce((a, b) => a > b ? a : b).clamp(0, 5).toInt();
  }

  bool get _severe => _pain == 5 || _fatigue == 5 || _mood == 0;
  bool get _high => (_pain ?? 0) >= 4 || (_fatigue ?? 0) >= 4 || (_mood ?? 5) <= 1;

  String _dayTitle(DateTime d) {
    final base = '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
    final diff = _daysBetween(_today, d);
    final cap = base[0].toUpperCase() + base.substring(1);
    if (diff == 0) return 'Aujourd\'hui · $base';
    if (diff == 1) return 'Hier · $base';
    return cap;
  }

  /// Demande confirmation quand des réponses ne sont pas enregistrées.
  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandonner les modifications ?'),
        content: const Text('Vos réponses de ce jour ne sont pas enregistrées.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Rester')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Abandonner')),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _selectDate(DateTime d) async {
    if (d == _selected) return;
    if (!await _confirmLeave()) return;
    _applyDate(d);
  }

  /// Bouton retour : revient à l'écran précédent, ou à l'accueil s'il n'y en a pas
  /// (par exemple quand la page a été rechargée directement sur cet écran).
  Future<void> _goBack() async {
    if (!await _confirmLeave()) return;
    _leave();
  }

  void _leave() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed('/home');
    }
  }

  /// Reprend les réponses de la veille (quand rien n'a encore été saisi).
  void _copyYesterday() {
    final row = _entryOf(_addDays(_selected, -1));
    if (row == null) return;
    setState(() {
      _fatigue = (row['fatigue_level'] as num?)?.toInt();
      _pain = (row['pain_level'] as num?)?.toInt();
      _mood = (row['mood_level'] as num?)?.toInt();
      _tags.clear();
      _dirty = true;
      final raw = (row['comment'] as String?) ?? '';
      final m = RegExp(r'^Symptômes signalés : ([^.]+)\.').firstMatch(raw);
      if (m != null) {
        for (final t in m.group(1)!.split(', ')) {
          if (_tagOptions.contains(t)) _tags.add(t);
        }
      }
    });
  }

  // ------------------------------------------------------------------ En-tête et semaine

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            const Positioned(
              right: 14,
              bottom: -22,
              child: Opacity(opacity: 0.18, child: RibbonLogo(size: 120, color: Colors.white)),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _dayTitle(_selected),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 60),
                    child: Text(
                      _hasExisting
                          ? 'Suivi déjà rempli pour ce jour : vous pouvez le modifier.'
                          : 'Répondez aux 3 questions ci-dessous. Cela prend moins d\'une minute.',
                      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: _answered / 3,
                            minHeight: 8,
                            backgroundColor: Colors.white24,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$_answered sur 3',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeek() {
    final days = [for (var i = 6; i >= 0; i--) _addDays(_today, -i)];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ma semaine',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          const Text(
            'Touchez un jour pour le remplir ou le modifier.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final d in days) _weekDay(d),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Bien', style: TextStyle(fontSize: 11, color: AppColors.muted)),
              const SizedBox(width: 6),
              for (final c in _scale)
                Container(
                  width: 16,
                  height: 8,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
                ),
              const SizedBox(width: 4),
              const Text('Difficile', style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weekDay(DateTime d) {
    final row = _entryOf(d);
    final selected = d == _selected;
    final color = row == null ? null : _scale[_severity(row)];

    return GestureDetector(
      onTap: () => _selectDate(d),
      child: Semantics(
        button: true,
        label: '${_dayTitle(d)}, ${row == null ? 'non rempli' : 'rempli'}',
        child: SizedBox(
          width: 38,
          child: Column(
            children: [
              Text(
                _weekdays[d.weekday - 1].substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? AppColors.rose : AppColors.muted,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color ?? Colors.white,
                  border: Border.all(
                    color: selected ? AppColors.ink : (color ?? AppColors.border),
                    width: selected ? 2.5 : 1.5,
                  ),
                ),
                child: row == null
                    ? const Icon(Icons.add, size: 16, color: AppColors.muted)
                    : null,
              ),
              const SizedBox(height: 3),
              Text(
                '${d.day}',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ Questions

  /// Comparaison avec la veille : « Hier : Légère · plus qu'hier ».
  Widget? _yesterdayHint(_Scale scale, String key, int? value) {
    final row = _entryOf(_addDays(_selected, -1));
    final y = (row?[key] as num?)?.toInt();
    if (y == null) return null;

    String extra = '';
    Color color = AppColors.muted;
    if (value != null && value != y) {
      final higher = value > y;
      final good = scale.reverse ? higher : !higher;
      extra = higher ? ' · plus qu\'hier' : ' · moins qu\'hier';
      color = good ? AppColors.successText : AppColors.dangerText;
    } else if (value != null) {
      extra = ' · comme hier';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.history, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'Hier : ${scale.words[y]} ($y/5)$extra',
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion({
    required _Scale scale,
    required String key,
    required int? value,
    required ValueChanged<int> onChanged,
  }) {
    final color = value == null ? AppColors.muted : _levelColor(value, scale.reverse);
    final hint = _yesterdayHint(scale, key, value);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(scale.icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scale.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
                    ),
                    Text(
                      scale.question,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (value == null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'À remplir',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.amberText),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < 6; i++)
                Expanded(
                  child: Center(
                    child: Semantics(
                      button: true,
                      selected: value == i,
                      label: '${scale.title} $i sur 5, ${scale.words[i].toLowerCase()}',
                      child: GestureDetector(
                        onTap: () => onChanged(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: value == i ? _levelColor(i, scale.reverse) : Colors.white,
                            border: Border.all(color: _levelColor(i, scale.reverse), width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '$i',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: value == i
                                    ? (_levelColor(i, scale.reverse).computeLuminance() > 0.45 ? AppColors.ink : Colors.white)
                                    : AppColors.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(scale.low, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              Text(scale.high, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: value == null
                ? const SizedBox(width: double.infinity)
                : Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$value sur 5 · ${scale.words[value]}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _darker(color)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          scale.hints[value],
                          style: const TextStyle(fontSize: 13, color: AppColors.ink, height: 1.35),
                        ),
                      ],
                    ),
                  ),
          ),
          if (hint != null) hint,
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ Symptômes et commentaire

  Widget _buildOthers() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Autres symptômes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          const Text(
            'Cochez ce que vous avez ressenti (facultatif).',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in _tagOptions)
                FilterChip(
                  label: Text(t),
                  selected: _tags.contains(t),
                  visualDensity: VisualDensity.compact,
                  onSelected: (on) => setState(() {
                    if (on) {
                      _tags.add(t);
                    } else {
                      _tags.remove(t);
                    }
                    _dirty = true;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _commentController,
            maxLines: 3,
            onChanged: (_) {
              if (!_dirty) setState(() => _dirty = true);
            },
            decoration: const InputDecoration(
              labelText: 'Commentaire (facultatif)',
              hintText: 'Ex : nuit difficile, douleur au bras gauche après le traitement...',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ Alerte, récapitulatif, enregistrement

  Widget _buildAlert() {
    final severe = _severe;
    final color = severe ? AppColors.danger : AppColors.amber;

    return AppCard(
      color: color.withValues(alpha: 0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(severe ? Icons.warning_amber_rounded : Icons.info_outline,
                  color: severe ? AppColors.dangerText : AppColors.amberText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  severe
                      ? 'Vos réponses indiquent un état très difficile. Contactez rapidement votre médecin ou le service d\'urgence le plus proche, sans attendre votre prochain rendez-vous.'
                      : 'Certains niveaux sont élevés. Si cela vous inquiète ou dure, parlez-en à votre médecin.',
                  style: const TextStyle(color: AppColors.ink, height: 1.4, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/patient-messages'),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Écrire à mon médecin'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(_Scale s, int v) {
    final c = _levelColor(v, s.reverse);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
      child: Text(
        '${s.title} : ${s.words[v].toLowerCase()}',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _darker(c)),
      ),
    );
  }

  Widget _buildRecap() {
    final f = _fatigue, p = _pain, m = _mood;
    if (f == null || p == null || m == null) return const SizedBox.shrink();

    return AppCard(
      color: AppColors.roseSoft.withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Récapitulatif · ${_selected.day} ${_months[_selected.month - 1]}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [_pill(_fatigueScale, f), _pill(_painScale, p), _pill(_moodScale, m)],
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Symptômes : ${_tagOptions.where(_tags.contains).join(', ').toLowerCase()}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    final complete = _answered == 3;
    return Column(
      children: [
        SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_isSaving || !complete) ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    _hasExisting ? 'Mettre à jour mon suivi' : 'Enregistrer mon suivi',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
        if (!complete)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Répondez aux 3 questions pour enregistrer.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------------ Page

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmLeave()) _leave();
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retour',
          onPressed: _goBack,
        ),
        title: const Text('Suivi des symptômes'),
      ),
      body: _loading
          ? const SkeletonPage()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 12),
                  _buildWeek(),
                  const SizedBox(height: 10),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.visibility_outlined, size: 15, color: AppColors.muted),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Ce suivi est visible par les médecins de votre équipe.',
                            style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_answered == 0 && _entryOf(_addDays(_selected, -1)) != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _copyYesterday,
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        label: const Text('Remplir comme hier'),
                      ),
                    )
                  else
                    const SizedBox(height: 8),
                  _buildQuestion(
                    scale: _fatigueScale,
                    key: 'fatigue_level',
                    value: _fatigue,
                    onChanged: (v) => setState(() {
                      _fatigue = v;
                      _dirty = true;
                    }),
                  ),
                  const SizedBox(height: 12),
                  _buildQuestion(
                    scale: _painScale,
                    key: 'pain_level',
                    value: _pain,
                    onChanged: (v) => setState(() {
                      _pain = v;
                      _dirty = true;
                    }),
                  ),
                  const SizedBox(height: 12),
                  _buildQuestion(
                    scale: _moodScale,
                    key: 'mood_level',
                    value: _mood,
                    onChanged: (v) => setState(() {
                      _mood = v;
                      _dirty = true;
                    }),
                  ),
                  const SizedBox(height: 12),
                  _buildOthers(),
                  if (_high) ...[
                    const SizedBox(height: 12),
                    _buildAlert(),
                  ],
                  if (_answered == 3) ...[
                    const SizedBox(height: 12),
                    _buildRecap(),
                  ],
                  const SizedBox(height: 18),
                  _buildSaveButton(),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/symptoms-history'),
                    icon: const Icon(Icons.show_chart),
                    label: const Text('Voir l\'historique et l\'évolution'),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
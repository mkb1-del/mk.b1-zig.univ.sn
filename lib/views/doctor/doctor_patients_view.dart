import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/follow_up_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/user_avatar.dart';
import '../messages/chat_view.dart';
import 'create_prescription_view.dart';
import 'doctor_patient_detail_view.dart';

/// Prochain rendez-vous d'une patiente avec ce médecin.
class _Next {
  final DateTime date;
  final String time;
  final String status;

  const _Next({required this.date, required this.time, required this.status});
}

/// Ce qu'on sait d'une patiente pour décider qui contacter en priorité.
class _Info {
  final int alertDays;
  final int unread;
  final DateTime? lastFollowUp;
  final _Next? next;

  const _Info({
    required this.alertDays,
    required this.unread,
    required this.lastFollowUp,
    required this.next,
  });
}

enum _Sort { priority, name, followUp }

enum _Filter { all, watch, unread, noFollowUp }

/// « Mes patientes » : un tableau de suivi. Chaque patiente montre son dernier
/// suivi, son prochain rendez-vous, ses messages non lus et ses alertes ; la
/// liste se filtre, se trie, et permet d'écrire ou de prescrire en un geste.
class DoctorPatientsView extends StatefulWidget {
  /// true : utilisé comme contenu d'un onglet (sans barre du haut, car
  /// doctor_home_view en a déjà une).
  final bool embedded;

  const DoctorPatientsView({super.key, this.embedded = false});

  @override
  State<DoctorPatientsView> createState() => _DoctorPatientsViewState();
}

class _DoctorPatientsViewState extends State<DoctorPatientsView> {
  final AuthService _authService = AuthService();
  final FollowUpService _followUp = FollowUpService();
  final TextEditingController _searchController = TextEditingController();

  List<UserModel> _patients = [];
  Map<String, int> _alerts = {};
  Map<String, int> _unread = {};
  Map<String, DateTime> _lastFollowUp = {};
  Map<String, _Next> _next = {};
  String _query = '';
  _Sort _sort = _Sort.priority;
  _Filter _filter = _Filter.all;
  bool _isLoading = true;
  String? _errorMessage;

  /// Au-delà de ce nombre de jours sans suivi, la patiente est signalée.
  static const int _staleDays = 7;

  static const List<String> _weekdaysShort = [
    'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'
  ];
  static const List<String> _monthsShort = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ Données

  /// silent = true : rafraîchit sans remplacer la page par un spinner.
  Future<void> _loadPatients({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      // Patientes, alertes, non lus, derniers suivis et prochains rendez-vous :
      // cinq lectures indépendantes, lancées ensemble.
      final (patients, alerts, unread, last, next) = await (
        _authService.getAllPatients(),
        _followUp.loadAlerts(),
        _loadUnread(),
        _loadLastFollowUp(),
        _loadNext(),
      ).wait;

      if (!mounted) return;
      setState(() {
        _patients = patients;
        _alerts = alerts;
        _unread = unread;
        _lastFollowUp = last;
        _next = next;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erreur chargement patientes: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossible de charger vos patientes.';
      });
    }
  }

  String? get _me => Supabase.instance.client.auth.currentUser?.id;

  /// Messages non lus de chaque patiente (identifiant -> nombre).
  Future<Map<String, int>> _loadUnread() async {
    final out = <String, int>{};
    final me = _me;
    if (me == null) return out;
    try {
      final rows = await Supabase.instance.client
          .from('messages')
          .select('sender_id')
          .eq('receiver_id', me)
          .eq('is_read', false);
      for (final r in rows) {
        final id = r['sender_id']?.toString();
        if (id != null) out[id] = (out[id] ?? 0) + 1;
      }
    } catch (e) {
      debugPrint('❌ Erreur comptage des non lus : $e');
    }
    return out;
  }

  /// Date du dernier suivi de chaque patiente : le plus récent entre le suivi
  /// complet (symptoms) et le bilan rapide d'humeur (mood_entries).
  Future<Map<String, DateTime>> _loadLastFollowUp() async {
    final out = <String, DateTime>{};
    void keepLatest(String? id, String? raw) {
      final d = DateTime.tryParse(raw ?? '');
      if (id == null || d == null) return;
      final day = DateTime(d.year, d.month, d.day);
      final current = out[id];
      if (current == null || day.isAfter(current)) out[id] = day;
    }

    try {
      final client = Supabase.instance.client;
      final results = await Future.wait([
        client.from('symptoms').select('patient_id, date').order('date', ascending: false).limit(2000),
        client.from('mood_entries').select('patient_id, entry_date').order('entry_date', ascending: false).limit(2000),
      ]);
      for (final r in results[0]) {
        keepLatest(r['patient_id']?.toString(), r['date']?.toString());
      }
      for (final r in results[1]) {
        keepLatest(r['patient_id']?.toString(), r['entry_date']?.toString());
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement des derniers suivis : $e');
    }
    return out;
  }

  /// Prochain rendez-vous (à venir, ni annulé ni terminé) de chaque patiente.
  Future<Map<String, _Next>> _loadNext() async {
    final out = <String, _Next>{};
    final me = _me;
    if (me == null) return out;
    try {
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final rows = await Supabase.instance.client
          .from('appointments')
          .select('patient_id, date, time, status')
          .eq('doctor_id', me)
          .gte('date', today)
          .neq('status', 'cancelled')
          .neq('status', 'completed')
          .order('date', ascending: true)
          .order('time', ascending: true)
          .limit(500);
      for (final r in rows) {
        final id = r['patient_id']?.toString();
        final d = DateTime.tryParse(r['date']?.toString() ?? '');
        if (id == null || d == null || out.containsKey(id)) continue;
        out[id] = _Next(
          date: DateTime(d.year, d.month, d.day),
          time: (r['time']?.toString() ?? '').length >= 5
              ? r['time'].toString().substring(0, 5)
              : (r['time']?.toString() ?? ''),
          status: r['status']?.toString() ?? 'pending',
        );
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement des prochains rendez-vous : $e');
    }
    return out;
  }

  // ------------------------------------------------------------ Aides

  Color _darker(Color c) => Color.lerp(c, Colors.black, 0.4)!;

  _Info _infoOf(UserModel p) => _Info(
        alertDays: _alerts[p.id] ?? 0,
        unread: _unread[p.id] ?? 0,
        lastFollowUp: _lastFollowUp[p.id],
        next: _next[p.id],
      );

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Nombre de jours depuis le dernier suivi (null : aucun suivi).
  int? _daysSince(DateTime? d) {
    if (d == null) return null;
    return DateTime.utc(_today.year, _today.month, _today.day)
        .difference(DateTime.utc(d.year, d.month, d.day))
        .inDays;
  }

  bool _isStale(_Info i) {
    final n = _daysSince(i.lastFollowUp);
    return n == null || n >= _staleDays;
  }

  /// Plus le score est haut, plus la patiente demande de l'attention.
  int _priority(_Info i) => i.alertDays * 100 + i.unread * 10 + (_isStale(i) ? 5 : 0);

  bool _matches(UserModel p) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty || p.name.toLowerCase().contains(q);
  }

  bool _passes(UserModel p, _Info i) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.watch:
        return i.alertDays > 0;
      case _Filter.unread:
        return i.unread > 0;
      case _Filter.noFollowUp:
        return _isStale(i);
    }
  }

  List<UserModel> _visible() {
    final list = _patients.where((p) => _matches(p) && _passes(p, _infoOf(p))).toList();
    list.sort((a, b) {
      final ia = _infoOf(a);
      final ib = _infoOf(b);
      int byName() => a.name.toLowerCase().compareTo(b.name.toLowerCase());
      switch (_sort) {
        case _Sort.name:
          return byName();
        case _Sort.followUp:
          // Les plus anciens suivis d'abord (sans suivi en tête).
          final da = ia.lastFollowUp;
          final db = ib.lastFollowUp;
          if (da == null && db == null) return byName();
          if (da == null) return -1;
          if (db == null) return 1;
          final byDate = da.compareTo(db);
          return byDate != 0 ? byDate : byName();
        case _Sort.priority:
          final byPriority = _priority(ib).compareTo(_priority(ia));
          return byPriority != 0 ? byPriority : byName();
      }
    });
    return list;
  }

  String _sortLabel(_Sort s) {
    switch (s) {
      case _Sort.priority:
        return 'Priorité';
      case _Sort.name:
        return 'Nom (A à Z)';
      case _Sort.followUp:
        return 'Suivi le plus ancien';
    }
  }

  void _open(UserModel patient) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DoctorPatientDetailView(patient: patient),
      ),
    ).then((_) {
      if (mounted) _loadPatients(silent: true);
    });
  }

  void _write(UserModel patient) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatView(
          receiverId: patient.id,
          receiverName: patient.name,
          receiverAvatar: patient.avatarUrl,
        ),
      ),
    ).then((_) {
      if (mounted) _loadPatients(silent: true);
    });
  }

  Future<void> _prescribe(UserModel patient) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CreatePrescriptionView(
          patientId: patient.id,
          patientName: patient.name,
        ),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Ordonnance envoyée à ${patient.name}'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _addPatient() {
    Navigator.pushNamed(context, '/add-patient').then((_) {
      if (mounted) _loadPatients(silent: true);
    });
  }

  // ------------------------------------------------------------ Éléments d'interface

  Widget _buildHeader(int total, int watch) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mes patientes',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            '$total patiente${total > 1 ? 's' : ''}'
            '${watch > 0 ? ' · $watch à surveiller' : ' · aucune alerte'}',
            style: TextStyle(
              fontSize: 13,
              color: watch > 0 ? AppColors.dangerText : AppColors.muted,
              fontWeight: watch > 0 ? FontWeight.w700 : FontWeight.w400,
            ),
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
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(int total, int watch, int stale) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _stat(Icons.people_alt_outlined, AppColors.rose, total, 'Patientes'),
            const VerticalDivider(width: 1),
            _stat(Icons.monitor_heart_outlined, AppColors.danger, watch, 'À surveiller'),
            const VerticalDivider(width: 1),
            _stat(Icons.hourglass_bottom, AppColors.amber, stale, 'Sans suivi ($_staleDays j)'),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
        hintText: 'Rechercher une patiente',
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

  Widget _buildFilters(int watch, int unreadPatients, int stale) {
    Widget chip(_Filter f, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _filter == f,
            showCheckmark: false,
            onSelected: (_) => setState(() => _filter = f),
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(_Filter.all, 'Toutes'),
          chip(_Filter.watch, 'À surveiller ($watch)'),
          chip(_Filter.unread, 'Messages ($unreadPatients)'),
          chip(_Filter.noFollowUp, 'Sans suivi ($stale)'),
        ],
      ),
    );
  }

  Widget _buildSortBar(int shown) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$shown patiente${shown > 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted),
          ),
        ),
        PopupMenuButton<_Sort>(
          tooltip: 'Trier',
          initialValue: _sort,
          onSelected: (s) => setState(() => _sort = s),
          itemBuilder: (context) => [
            for (final s in _Sort.values)
              PopupMenuItem(value: s, child: Text(_sortLabel(s))),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sort, size: 18, color: AppColors.rose),
                const SizedBox(width: 4),
                Text(
                  _sortLabel(_sort),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.rose),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// « Suivi renseigné hier », « il y a 5 jours », « Aucun suivi enregistré ».
  Widget _followUpLine(_Info i) {
    final n = _daysSince(i.lastFollowUp);
    String text;
    Color color;
    if (n == null) {
      text = 'Aucun suivi enregistré';
      color = AppColors.dangerText;
    } else if (n <= 0) {
      text = 'Suivi renseigné aujourd\'hui';
      color = AppColors.successText;
    } else if (n == 1) {
      text = 'Dernier suivi : hier';
      color = AppColors.successText;
    } else {
      text = 'Dernier suivi : il y a $n jours';
      color = n >= _staleDays ? AppColors.dangerText : (n >= 3 ? AppColors.amberText : AppColors.successText);
    }
    return _infoLine(Icons.favorite_border, text, color);
  }

  Widget _nextLine(_Info i) {
    final nx = i.next;
    if (nx == null) {
      return _infoLine(Icons.event_busy_outlined, 'Aucun rendez-vous prévu', AppColors.muted);
    }
    final d = nx.date;
    final when = '${_weekdaysShort[d.weekday - 1]} ${d.day} ${_monthsShort[d.month - 1]}'
        '${nx.time.isEmpty ? '' : ' à ${nx.time}'}';
    return _infoLine(
      Icons.event_outlined,
      'Prochain RDV : $when${nx.status == 'pending' ? ' (à confirmer)' : ''}',
      AppColors.ink,
    );
  }

  Widget _infoLine(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertChip(_Info i) {
    final c = i.alertDays >= 2 ? AppColors.danger : AppColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.monitor_heart_outlined, size: 13, color: _darker(c)),
          const SizedBox(width: 4),
          Text(
            'À surveiller · ${i.alertDays} jour${i.alertDays > 1 ? 's' : ''} difficile${i.alertDays > 1 ? 's' : ''}',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _darker(c)),
          ),
        ],
      ),
    );
  }

  Widget _unreadChip(int n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.rose.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chat_bubble_outline, size: 13, color: AppColors.roseDark),
          const SizedBox(width: 4),
          Text(
            '$n message${n > 1 ? 's' : ''} non lu${n > 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.roseDark),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(UserModel patient) {
    final i = _infoOf(patient);
    final railColor = i.alertDays >= 2
        ? AppColors.danger
        : (i.alertDays == 1 || i.unread > 0
            ? AppColors.amber
            : (_isStale(i) ? AppColors.muted : AppColors.success));
    final hasChips = i.alertDays > 0 || i.unread > 0;

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => _open(patient),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: railColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          UserAvatar(name: patient.name, url: patient.avatarUrl, radius: 25),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  patient.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
                                ),
                                _followUpLine(i),
                                _nextLine(i),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppColors.muted),
                        ],
                      ),
                      if (hasChips) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (i.alertDays > 0) _alertChip(i),
                            if (i.unread > 0) _unreadChip(i.unread),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      const Divider(height: 14),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _write(patient),
                            icon: const Icon(Icons.chat_bubble_outline, size: 18),
                            label: const Text('Écrire'),
                          ),
                          TextButton.icon(
                            onPressed: () => _prescribe(patient),
                            icon: const Icon(Icons.edit_note, size: 20),
                            label: const Text('Prescrire'),
                          ),
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

  Widget _emptyBlock(IconData icon, String title, String message, {String? actionLabel, VoidCallback? onAction}) {
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
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const SkeletonList();
    }

    if (_errorMessage != null) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: _errorMessage!,
        message: 'Vérifiez votre connexion internet puis réessayez.',
        actionLabel: 'Réessayer',
        onAction: _loadPatients,
      );
    }

    if (_patients.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.embedded) _buildHeader(0, 0),
          _emptyBlock(
            Icons.people_outline,
            'Aucune patiente suivie pour le moment',
            'Une patiente apparaît ici dès qu\'elle vous ajoute à son équipe médicale, prend rendez-vous avec vous ou vous écrit.',
            actionLabel: 'Ajouter une patiente',
            onAction: _addPatient,
          ),
        ],
      );
    }

    final infos = {for (final p in _patients) p.id: _infoOf(p)};
    final watch = infos.values.where((i) => i.alertDays > 0).length;
    final unreadPatients = infos.values.where((i) => i.unread > 0).length;
    final stale = infos.values.where(_isStale).length;
    final list = _visible();

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _loadPatients(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (widget.embedded) _buildHeader(_patients.length, watch),
          _buildStats(_patients.length, watch, stale),
          const SizedBox(height: 16),
          _buildSearch(),
          const SizedBox(height: 12),
          _buildFilters(watch, unreadPatients, stale),
          const SizedBox(height: 4),
          _buildSortBar(list.length),
          const SizedBox(height: 4),
          if (list.isEmpty)
            _emptyBlock(
              Icons.search_off,
              'Aucune patiente trouvée',
              _query.trim().isNotEmpty
                  ? 'Aucun résultat pour « ${_query.trim()} ».'
                  : 'Aucune patiente ne correspond à ce filtre.',
              actionLabel: _filter == _Filter.all ? null : 'Voir toutes les patientes',
              onAction: () => setState(() => _filter = _Filter.all),
            )
          else
            for (var i = 0; i < list.length; i++) ...[
              _buildItem(list[i]),
              if (i < list.length - 1) const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Mes patientes')),
      body: _buildContent(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPatient,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Ajouter'),
      ),
    );
  }
}
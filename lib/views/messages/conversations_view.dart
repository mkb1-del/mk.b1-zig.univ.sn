import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/care_team_service.dart';
import '../../services/message_service.dart';
import '../../services/realtime_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/user_avatar.dart';
import 'chat_view.dart';

/// Dernier message échangé avec un médecin.
class _Last {
  final String content;
  final DateTime at;
  final bool mine;

  const _Last({required this.content, required this.at, required this.mine});
}

/// Messagerie de la patiente : les conversations en cours (dernier message,
/// heure, messages non lus), puis les médecins avec qui démarrer une conversation.
class ConversationsView extends StatefulWidget {
  /// true : utilisé comme contenu d'un onglet (sans barre du haut).
  final bool embedded;

  const ConversationsView({super.key, this.embedded = false});

  @override
  State<ConversationsView> createState() => _ConversationsViewState();
}

class _ConversationsViewState extends State<ConversationsView> {
  final AuthService _authService = AuthService();
  final CareTeamService _careTeam = CareTeamService();
  final MessageService _messageService = MessageService();
  final TextEditingController _searchController = TextEditingController();

  final Map<String, int> _unreadCounts = {};
  Map<String, _Last> _lastMessages = {};
  List<UserModel> _doctors = [];
  Set<String> _teamIds = {};
  bool _isLoading = true;
  bool _unreadOnly = false;
  String _query = '';
  StreamSubscription<LiveEvent>? _liveSub;

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
    _load();
    // Les conversations et les pastilles se mettent à jour en direct.
    _liveSub = RealtimeService.instance.events.listen((event) {
      if (event.type == LiveEventType.message || event.type == LiveEventType.refresh) {
        _load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _searchController.dispose();
    _messageService.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ Données

  /// silent = true : rafraîchit sans remplacer la page par un spinner.
  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Médecins, équipe, non lus et derniers messages : quatre lectures indépendantes.
      final (doctors, teamIds, counts, last) = await (
        _authService.getAllDoctors(),
        _careTeam.getTeamIds(),
        _messageService.getUnreadCountsBySender(user.id),
        _loadLastMessages(user.id),
      ).wait;

      if (!mounted) return;
      setState(() {
        _doctors = doctors;
        _teamIds = teamIds;
        _lastMessages = last;
        _unreadCounts
          ..clear()
          ..addAll(counts);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erreur chargement conversations: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Le dernier message de chaque interlocuteur : une seule requête sur les
  /// messages les plus récents, regroupés ensuite par interlocuteur.
  Future<Map<String, _Last>> _loadLastMessages(String me) async {
    final out = <String, _Last>{};
    try {
      final rows = await Supabase.instance.client
          .from('messages')
          .select('sender_id, receiver_id, content, created_at')
          .or('sender_id.eq.$me,receiver_id.eq.$me')
          .order('created_at', ascending: false)
          .limit(300);
      for (final r in rows) {
        final sender = r['sender_id']?.toString() ?? '';
        final receiver = r['receiver_id']?.toString() ?? '';
        final other = sender == me ? receiver : sender;
        if (other.isEmpty || out.containsKey(other)) continue;
        final at = DateTime.tryParse(r['created_at']?.toString() ?? '');
        if (at == null) continue;
        out[other] = _Last(
          content: (r['content']?.toString() ?? '').replaceAll('\n', ' ').trim(),
          at: at.toLocal(),
          mine: sender == me,
        );
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement des derniers messages: $e');
    }
    return out;
  }

  // ------------------------------------------------------------ Aides

  /// « 14:32 » aujourd'hui, « Hier », « lun. » cette semaine, sinon « 5 nov. ».
  String _timeLabel(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) {
      return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) return 'Hier';
    if (diff < 7) return _weekdaysShort[at.weekday - 1];
    return '${at.day} ${_monthsShort[at.month - 1]}';
  }

  bool _matches(UserModel d) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return d.name.toLowerCase().contains(q) ||
        (d.specialty ?? '').toLowerCase().contains(q);
  }

  void _open(UserModel doctor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatView(
          receiverId: doctor.id,
          receiverName: doctor.name,
          receiverAvatar: doctor.avatarUrl,
          receiverSubtitle: (doctor.specialty ?? '').trim().isEmpty ? 'Médecin' : doctor.specialty,
        ),
      ),
    ).then((_) {
      if (mounted) _load(silent: true);
    });
  }

  // ------------------------------------------------------------ Éléments d'interface

  Widget _buildHeader(int unread) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Messages',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            unread > 0
                ? '$unread message${unread > 1 ? 's' : ''} non lu${unread > 1 ? 's' : ''}'
                : 'Aucun message non lu',
            style: TextStyle(
              fontSize: 13,
              color: unread > 0 ? AppColors.rose : AppColors.muted,
              fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: 'Rechercher un médecin...',
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

  Widget _buildFilters(int unread) {
    return Row(
      children: [
        ChoiceChip(
          label: const Text('Toutes'),
          selected: !_unreadOnly,
          showCheckmark: false,
          onSelected: (_) => setState(() => _unreadOnly = false),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: Text('Non lues ($unread)'),
          selected: _unreadOnly,
          showCheckmark: false,
          onSelected: (_) => setState(() => _unreadOnly = true),
        ),
      ],
    );
  }

  Widget _teamPill() {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.rose.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'Mon équipe',
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.roseDark),
      ),
    );
  }

  /// Une conversation : avatar, nom, aperçu du dernier message, heure et non lus.
  Widget _conversationTile(UserModel doctor) {
    final last = _lastMessages[doctor.id]!;
    final unread = _unreadCounts[doctor.id] ?? 0;
    final hasUnread = unread > 0;
    final preview = last.content.isEmpty ? 'Message' : last.content;

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _open(doctor),
      child: Row(
        children: [
          UserAvatar(name: doctor.name, url: doctor.avatarUrl, radius: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Dr ${doctor.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (_teamIds.contains(doctor.id)) _teamPill(),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  last.mine ? 'Vous : $preview' : preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: hasUnread ? AppColors.ink : AppColors.muted,
                    fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _timeLabel(last.at),
                style: TextStyle(
                  fontSize: 12,
                  color: hasUnread ? AppColors.rose : AppColors.muted,
                  fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 6),
              if (hasUnread)
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.rose,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                )
              else
                const SizedBox(height: 22),
            ],
          ),
        ],
      ),
    );
  }

  /// Un médecin avec qui aucun message n'a encore été échangé.
  Widget _startTile(UserModel doctor) {
    final specialty = (doctor.specialty ?? '').trim();
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _open(doctor),
      child: Row(
        children: [
          UserAvatar(name: doctor.name, url: doctor.avatarUrl, radius: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Dr ${doctor.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ),
                    if (_teamIds.contains(doctor.id)) _teamPill(),
                  ],
                ),
                if (specialty.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      specialty,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.rose),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _open(doctor),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14)),
            child: const Text('Écrire'),
          ),
        ],
      ),
    );
  }

  List<Widget> _spaced(List<Widget> items) {
    return [
      for (var i = 0; i < items.length; i++) ...[
        items[i],
        if (i < items.length - 1) const SizedBox(height: 12),
      ],
    ];
  }

  Widget _emptyBlock(IconData icon, String title, String message) {
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
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const SkeletonList();
    }

    if (_doctors.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.embedded) _buildHeader(0),
          _emptyBlock(
            Icons.chat_bubble_outline,
            'Aucun médecin disponible',
            'Dès qu\'un médecin est inscrit, vous pourrez lui écrire ici.',
          ),
        ],
      );
    }

    final totalUnread = _unreadCounts.values.fold<int>(0, (a, b) => a + b);

    // Conversations : les médecins qui ont déjà échangé avec moi, du plus récent
    // au plus ancien. Les autres médecins sont proposés pour démarrer.
    final withMessages = _doctors
        .where((d) => _lastMessages.containsKey(d.id))
        .where(_matches)
        .toList()
      ..sort((a, b) => _lastMessages[b.id]!.at.compareTo(_lastMessages[a.id]!.at));
    final conversations = _unreadOnly
        ? withMessages.where((d) => (_unreadCounts[d.id] ?? 0) > 0).toList()
        : withMessages;

    final others = _doctors
        .where((d) => !_lastMessages.containsKey(d.id))
        .where(_matches)
        .toList()
      ..sort((a, b) {
        final ta = _teamIds.contains(a.id) ? 0 : 1;
        final tb = _teamIds.contains(b.id) ? 0 : 1;
        if (ta != tb) return ta - tb;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final nothingFound = conversations.isEmpty && (others.isEmpty || _unreadOnly);

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (widget.embedded) _buildHeader(totalUnread),
          if (_doctors.length >= 5) ...[
            _buildSearch(),
            const SizedBox(height: 12),
          ],
          if (_lastMessages.isNotEmpty) ...[
            _buildFilters(totalUnread),
            const SizedBox(height: 16),
          ],
          if (conversations.isNotEmpty) ...[
            SectionTitle(title: 'Conversations (${conversations.length})'),
            ..._spaced([for (final d in conversations) _conversationTile(d)]),
          ],
          if (!_unreadOnly && others.isNotEmpty) ...[
            SizedBox(height: conversations.isNotEmpty ? 24 : 0),
            SectionTitle(title: _lastMessages.isEmpty ? 'Écrire à un médecin' : 'Démarrer une conversation'),
            if (_lastMessages.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Choisissez un médecin pour lui poser une question sur votre traitement ou un rendez-vous.',
                  style: TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.4),
                ),
              ),
            ..._spaced([for (final d in others) _startTile(d)]),
          ],
          if (nothingFound)
            _emptyBlock(
              _unreadOnly ? Icons.mark_email_read_outlined : Icons.search_off,
              _unreadOnly ? 'Tout est lu' : 'Aucun résultat',
              _unreadOnly
                  ? 'Vous n\'avez aucun message non lu.'
                  : 'Aucun médecin ne correspond à « ${_query.trim()} ».',
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Messages')),
      body: _buildContent(),
    );
  }
}
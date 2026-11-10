import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/message_service.dart';
import '../../services/realtime_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/user_avatar.dart';
import 'chat_view.dart';

/// Messagerie du médecin : liste de ses patientes (comptes), avec recherche et
/// nombre de messages non lus.
class SelectPatientChatView extends StatefulWidget {
  const SelectPatientChatView({super.key});

  @override
  State<SelectPatientChatView> createState() => _SelectPatientChatViewState();
}

class _SelectPatientChatViewState extends State<SelectPatientChatView> {
  final AuthService _authService = AuthService();
  final MessageService _messageService = MessageService();
  final TextEditingController _searchController = TextEditingController();

  final Map<String, int> _unreadCounts = {};
  List<UserModel> _patients = [];
  String _query = '';
  bool _isLoading = true;
  StreamSubscription<LiveEvent>? _liveSub;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
    // Les pastilles de messages non lus se mettent à jour en direct.
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

  /// silent = true : rafraîchit sans remplacer la page par un spinner.
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final doctorId = Supabase.instance.client.auth.currentUser?.id;
      // Patientes (comptes) et messages non lus : deux lectures indépendantes.
      final (patients, counts) = await (
        _authService.getAllPatients(),
        doctorId == null
            ? Future.value(<String, int>{})
            : _messageService.getUnreadCountsBySender(doctorId),
      ).wait;
      patients.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));


      if (!mounted) return;
      setState(() {
        _patients = patients;
        _unreadCounts
          ..clear()
          ..addAll(counts);
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

  void _open(UserModel patient) {
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
      if (mounted) _load(silent: true);
    });
  }

  List<UserModel> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _patients;
    return _patients.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  Widget _buildItem(UserModel patient) {
    final unread = _unreadCounts[patient.id] ?? 0;

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _open(patient),
      child: Row(
        children: [
          UserAvatar(name: patient.name, url: patient.avatarUrl, radius: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Appuyer pour discuter',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.rose,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else
            const Icon(Icons.chevron_right, color: AppColors.muted),
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
        onAction: _load,
      );
    }

    if (_patients.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline,
        title: 'Aucune patiente disponible',
        message: 'Seules les patientes ayant un compte peuvent être contactées ici.',
      );
    }

    final list = _filtered;

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
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
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'Aucune patiente ne correspond à votre recherche.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
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
      appBar: AppBar(title: const Text('Messages')),
      body: _buildContent(),
    );
  }
}

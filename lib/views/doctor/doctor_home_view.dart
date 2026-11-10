import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../../services/app_errors.dart';
import '../../services/auth_service.dart';
import '../../services/follow_up_service.dart';
import '../../services/realtime_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/user_avatar.dart';
import 'doctor_patient_detail_view.dart';
import 'doctor_profile_view.dart';
import 'doctor_patients_view.dart';
import 'doctor_appointments_view.dart';
import 'select_patient_prescription_view.dart';

/// Accueil du médecin : ce qui demande une action (demandes de rendez-vous,
/// messages, patientes à surveiller), l'agenda du jour avec confirmation en un
/// geste, et les actions fréquentes.
class DoctorHomeView extends StatefulWidget {
  const DoctorHomeView({super.key});

  @override
  State<DoctorHomeView> createState() => _DoctorHomeViewState();
}

class _DoctorHomeViewState extends State<DoctorHomeView> {
  final AuthService _authService = AuthService();
  final FollowUpService _followUp = FollowUpService();

  // Onglets : 0 Accueil, 1 Patientes, 2 Prescrire, 3 RDV, 4 Profil
  static const int _tabHome = 0;
  static const int _tabPatients = 1;
  static const int _tabPrescribe = 2;
  static const int _tabAppointments = 3;
  static const int _tabProfile = 4;

  int _currentIndex = _tabHome;
  StreamSubscription<LiveEvent>? _liveSub;
  String? _doctorName;
  int _unreadMessages = 0;

  /// Rendez-vous d'aujourd'hui et à venir (hors annulés), du plus proche au plus lointain.
  List<Map<String, dynamic>> _agenda = [];
  List<MapEntry<UserModel, int>> _watchList = [];
  bool _isLoading = true;

  static const List<String> _months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];

  @override
  void initState() {
    super.initState();
    _loadDoctorData();
    _liveSub = RealtimeService.instance.events.listen(_onLiveEvent);
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }

  /// Un événement arrive en direct (message, demande de rendez-vous) : le
  /// tableau de bord se met à jour et une alerte s'affiche avec « Voir ».
  void _onLiveEvent(LiveEvent event) {
    if (!mounted) return;
    _loadDoctorData(silent: true);
    if (event.type == LiveEventType.refresh || event.quiet) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${event.title} · ${event.body}'),
        backgroundColor: AppColors.rose,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Voir',
          textColor: Colors.white,
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
            if (event.type == LiveEventType.message) {
              _showMessages();
            } else {
              _onTabSelected(_tabAppointments);
            }
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------ Données

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _todayStr => _dateStr(DateTime.now());

  /// Rendez-vous d'aujourd'hui (les terminés restent visibles, en grisé).
  List<Map<String, dynamic>> get _todayList =>
      _agenda.where((a) => a['date']?.toString() == _todayStr).toList();

  /// Les prochains rendez-vous des jours suivants (4 au maximum).
  List<Map<String, dynamic>> get _laterList => _agenda
      .where((a) => a['date']?.toString() != _todayStr && a['status'] != 'completed')
      .take(4)
      .toList();

  /// Demandes en attente de confirmation (aujourd'hui et à venir).
  int get _pendingCount => _agenda.where((a) => a['status'] == 'pending').length;

  /// silent = true : rafraîchit sans remplacer la page par un spinner.
  Future<void> _loadDoctorData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final doctor = await _authService.getCurrentUser();
      if (doctor == null) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        }
        return;
      }

      // Les quatre lectures sont indépendantes : elles partent ensemble.
      final (agenda, patients, alerts, unread) = await (
        _loadAgenda(doctor.id),
        _authService.getAllPatients(),
        _followUp.loadAlerts(),
        _countUnread(doctor.id),
      ).wait;

      final watchList = <MapEntry<UserModel, int>>[
        for (final p in patients)
          if ((alerts[p.id] ?? 0) > 0) MapEntry(p, alerts[p.id]!),
      ]..sort((a, b) => b.value.compareTo(a.value));

      if (mounted) {
        setState(() {
          _doctorName = doctor.name;
          _agenda = agenda;
          _unreadMessages = unread;
          _watchList = watchList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement données médecin: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadAgenda(String doctorId) async {
    try {
      final res = await Supabase.instance.client
          .from('appointments')
          .select('id, patient_id, patient_name, date, time, reason, status')
          .eq('doctor_id', doctorId)
          .gte('date', _todayStr)
          .neq('status', 'cancelled')
          .order('date', ascending: true)
          .order('time', ascending: true)
          .limit(100);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('❌ Erreur chargement agenda: $e');
      return [];
    }
  }

  Future<int> _countUnread(String doctorId) async {
    try {
      final res = await Supabase.instance.client
          .from('messages')
          .select('id')
          .eq('receiver_id', doctorId)
          .eq('is_read', false);
      return res.length;
    } catch (e) {
      debugPrint('❌ Erreur comptage messages non lus: $e');
      return 0;
    }
  }

  // ------------------------------------------------------------ Actions

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
    if (index == _tabHome) _loadDoctorData(silent: true);
  }

  void _showAddPatient() {
    Navigator.pushNamed(context, '/add-patient').then((_) {
      if (mounted) _loadDoctorData(silent: true);
    });
  }

  void _showCreateAppointment() {
    Navigator.pushNamed(context, '/create-appointment').then((_) {
      if (mounted) _loadDoctorData(silent: true);
    });
  }

  void _showMessages() {
    Navigator.pushNamed(context, '/doctor-messages');
  }

  void _showPrescriptions() {
    Navigator.pushNamed(context, '/doctor-prescriptions');
  }

  void _openPatient(UserModel patient) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DoctorPatientDetailView(patient: patient)),
    ).then((_) {
      if (mounted) _loadDoctorData(silent: true);
    });
  }

  /// Confirme ou refuse une demande directement depuis l'accueil.
  Future<void> _setStatus(String id, String status, String message) async {
    try {
      await Supabase.instance.client
          .from('appointments')
          .update({'status': status}).eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: status == 'cancelled' ? AppColors.amber : AppColors.success,
        ),
      );
      _loadDoctorData(silent: true);
    } catch (e) {
      debugPrint('❌ Erreur mise à jour RDV: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Mise à jour impossible. ${AppErrors.message(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _refuse(Map<String, dynamic> a) async {
    final name = a['patient_name']?.toString() ?? 'cette patiente';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refuser la demande ?'),
        content: Text('La demande de $name sera annulée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Oui, refuser'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _setStatus(a['id'].toString(), 'cancelled', 'Demande refusée');
    }
  }

  // ------------------------------------------------------------ Aides d'affichage

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bonjour';
    if (h < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  /// Une phrase qui résume la journée : ce qui demande l'attention.
  String get _summary {
    final today = _todayList.length;
    final pending = _pendingCount;
    final watch = _watchList.length;
    final parts = <String>[
      if (today > 0) '$today rendez-vous aujourd\'hui',
      if (pending > 0) '$pending demande${pending > 1 ? 's' : ''} à confirmer',
      if (watch > 0) '$watch patiente${watch > 1 ? 's' : ''} à surveiller',
    ];
    return parts.isEmpty ? 'Aucun rendez-vous aujourd\'hui, rien d\'urgent.' : parts.join(' · ');
  }

  String _hhmm(String t) => t.length >= 5 ? t.substring(0, 5) : t;

  /// « Demain », « Dans 3 jours » pour une date aaaa-mm-jj (ou rien si c'est loin).
  String? _relative(String dateStr) {
    final d = DateTime.tryParse(dateStr);
    if (d == null) return null;
    final now = DateTime.now();
    final n = DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
    if (n == 1) return 'Demain';
    if (n >= 2 && n <= 14) return 'Dans $n jours';
    return null;
  }

  Color _darker(Color c) => Color.lerp(c, Colors.black, 0.4)!;

  Widget _badged(IconData icon, int count) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: Icon(icon),
    );
  }

  // ---------------------------------------------------------------- Accueil : éléments

  /// Une case « à traiter », compacte : icône, chiffre et libellé côte à côte.
  /// Un toucher ouvre l'écran concerné.
  Widget _kpi({
    required IconData icon,
    required Color color,
    required int value,
    required String label,
    required VoidCallback onTap,
    bool attention = true,
  }) {
    final highlight = attention && value > 0;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: highlight ? _darker(color) : AppColors.ink,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpis() {
    final pairs = <List<Widget>>[
      [
        _kpi(
          icon: Icons.mark_email_unread_outlined,
          color: AppColors.amber,
          value: _pendingCount,
          label: 'RDV à confirmer',
          onTap: () => _onTabSelected(_tabAppointments),
        ),
        _kpi(
          icon: Icons.chat_bubble_outline,
          color: AppColors.rose,
          value: _unreadMessages,
          label: 'Messages non lus',
          onTap: _showMessages,
        ),
      ],
      [
        _kpi(
          icon: Icons.monitor_heart_outlined,
          color: AppColors.danger,
          value: _watchList.length,
          label: 'À surveiller',
          onTap: () => _onTabSelected(_tabPatients),
        ),
        _kpi(
          icon: Icons.event_available_outlined,
          color: AppColors.teal,
          value: _todayList.length,
          label: 'RDV aujourd\'hui',
          attention: false,
          onTap: () => _onTabSelected(_tabAppointments),
        ),
      ],
    ];

    return Column(
      children: [
        for (var i = 0; i < pairs.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < pairs.length - 1 ? 10 : 0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: pairs[i][0]),
                  const SizedBox(width: 10),
                  Expanded(child: pairs[i][1]),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _quickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink, height: 1.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          _quickAction(Icons.person_add_alt_1, 'Ajouter une patiente', AppColors.rose, _showAddPatient),
          _quickAction(Icons.edit_note, 'Prescrire', AppColors.teal, () => _onTabSelected(_tabPrescribe)),
          _quickAction(Icons.edit_calendar_outlined, 'Planifier un RDV', AppColors.plum, _showCreateAppointment),
          _quickAction(Icons.description_outlined, 'Mes ordonnances', AppColors.violet, _showPrescriptions),
        ],
      ),
    );
  }

  /// Patientes ayant des journées difficiles récentes (3 au maximum).
  Widget _buildWatchList() {
    if (_watchList.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline, color: AppColors.successText),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aucune alerte',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Aucune journée difficile signalée ces 3 derniers jours.',
                    style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final shown = _watchList.take(3).toList();
    return Column(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          _watchCard(shown[i].key, shown[i].value),
          if (i < shown.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _watchCard(UserModel patient, int days) {
    final color = days >= 2 ? AppColors.danger : AppColors.amber;
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _openPatient(patient),
      child: Row(
        children: [
          UserAvatar(name: patient.name, url: patient.avatarUrl, radius: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$days journée${days > 1 ? 's' : ''} difficile${days > 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _darker(color)),
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'sur les 3 derniers jours',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    );
  }

  Widget _emptyBlock(IconData icon, String title, String message) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AppColors.roseSoft, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.rose),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bloc « quand » d'un rendez-vous : l'heure pour aujourd'hui, la date et l'heure sinon.
  Widget _whenBlock(Map<String, dynamic> a, {required bool showDate, required bool inactive}) {
    final tint = inactive ? AppColors.muted : AppColors.rose;
    final time = _hhmm(a['time']?.toString() ?? '');
    final parts = (a['date']?.toString() ?? '').split('-');
    final day = parts.length == 3 ? parts[2] : '--';
    final m = parts.length == 3 ? int.tryParse(parts[1]) : null;
    final month = (m != null && m >= 1 && m <= 12) ? _months[m - 1] : '';

    return Container(
      width: 62,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: showDate
          ? Column(
              children: [
                Text(day, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tint, height: 1)),
                const SizedBox(height: 2),
                Text(month, style: TextStyle(fontSize: 11, color: tint)),
                const SizedBox(height: 3),
                Text(time, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tint)),
              ],
            )
          : Center(
              child: Text(
                time.isEmpty ? '--:--' : time,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: tint),
              ),
            ),
    );
  }

  Widget _statusChip(String status) {
    final c = status == 'completed' ? AppColors.muted : StatusStyle.color(status);
    final label = status == 'pending' ? 'À confirmer' : StatusStyle.label(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _darker(c)),
      ),
    );
  }

  /// Un rendez-vous de l'agenda ; une demande en attente se confirme ou se refuse ici.
  Widget _agendaCard(Map<String, dynamic> a, {required bool showDate}) {
    final status = a['status']?.toString() ?? 'pending';
    final name = a['patient_name']?.toString() ?? 'Patiente';
    final reason = (a['reason']?.toString() ?? '').trim();
    final inactive = status == 'completed';
    final rel = showDate ? _relative(a['date']?.toString() ?? '') : null;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _whenBlock(a, showDate: showDate, inactive: inactive),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: inactive ? AppColors.muted : AppColors.ink,
                            ),
                          ),
                        ),
                        if (rel != null)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.roseSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              rel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.roseDark,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reason.isEmpty ? 'Consultation' : reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    _statusChip(status),
                  ],
                ),
              ),
            ],
          ),
          if (status == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _setStatus(a['id'].toString(), 'confirmed', 'Rendez-vous confirmé'),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Confirmer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 42),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _refuse(a),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Refuser'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.dangerText,
                      side: const BorderSide(color: AppColors.danger),
                      minimumSize: const Size(0, 42),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToday() {
    final today = _todayList;
    if (today.isEmpty) {
      return _emptyBlock(
        Icons.event_available,
        'Aucun rendez-vous aujourd\'hui',
        'Votre agenda est libre pour le reste de la journée.',
      );
    }
    return Column(
      children: [
        for (var i = 0; i < today.length; i++) ...[
          _agendaCard(today[i], showDate: false),
          if (i < today.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildLater() {
    final later = _laterList;
    return Column(
      children: [
        for (var i = 0; i < later.length; i++) ...[
          _agendaCard(later[i], showDate: true),
          if (i < later.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- Accueil

  Widget _buildHomePage() {
    if (_isLoading) {
      return const SkeletonHome();
    }

    final later = _laterList;

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _loadDoctorData(silent: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GradientHeader(
              dateLabel: frenchDateLabel(DateTime.now()),
              greeting: '$_greeting Dr ${_doctorName ?? 'Médecin'}',
              subtitle: _summary,
              initial: (_doctorName != null && _doctorName!.isNotEmpty)
                  ? _doctorName![0].toUpperCase()
                  : 'D',
            ),
            const SizedBox(height: 20),
            const SectionTitle(title: 'À traiter'),
            _buildKpis(),
            const SizedBox(height: 24),
            const SectionTitle(title: 'Actions rapides'),
            _buildQuickActions(),
            const SizedBox(height: 28),
            SectionTitle(
              title: 'Patientes à surveiller',
              actionLabel: _watchList.length > 3 ? 'Voir tout' : null,
              onAction: _watchList.length > 3 ? () => _onTabSelected(_tabPatients) : null,
            ),
            _buildWatchList(),
            const SizedBox(height: 28),
            SectionTitle(
              title: 'Aujourd\'hui (${_todayList.length})',
              actionLabel: 'Planning',
              onAction: () => _onTabSelected(_tabAppointments),
            ),
            _buildToday(),
            if (later.isNotEmpty) ...[
              const SizedBox(height: 28),
              SectionTitle(
                title: 'À venir',
                actionLabel: 'Voir tout',
                onAction: () => _onTabSelected(_tabAppointments),
              ),
              _buildLater(),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ Autres onglets

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case _tabHome:
        return _buildHomePage();
      case _tabPatients:
        return const DoctorPatientsView(embedded: true);
      case _tabPrescribe:
        return const SelectPatientPrescriptionView(embedded: true);
      case _tabAppointments:
        return const DoctorAppointmentsView(embedded: true);
      case _tabProfile:
        return const DoctorProfileView(embedded: true);
      default:
        return _buildHomePage();
    }
  }

  String get _title {
    switch (_currentIndex) {
      case _tabPatients:
        return 'Mes patientes';
      case _tabPrescribe:
        return 'Prescrire';
      case _tabAppointments:
        return 'Rendez-vous';
      case _tabProfile:
        return 'Mon profil';
      default:
        return 'Espace Médecin';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHome = _currentIndex == _tabHome;

    return PopScope(
      // Hors de l'accueil, le retour (flèche ou bouton système) ramène à l'accueil.
      canPop: isHome,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onTabSelected(_tabHome);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: isHome
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Retour à l\'accueil',
                  onPressed: () => _onTabSelected(_tabHome),
                ),
          title: Text(_title),
          actions: [
            IconButton(
              tooltip: _unreadMessages > 0
                  ? 'Messages ($_unreadMessages non lus)'
                  : 'Messages',
              icon: _badged(Icons.chat_bubble_outline, _unreadMessages),
              onPressed: _showMessages,
            ),
            IconButton(
              tooltip: 'Mon profil',
              icon: const Icon(Icons.person_outline),
              onPressed: () => setState(() => _currentIndex = _tabProfile),
            ),
          ],
        ),
        body: _buildCurrentPage(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onTabSelected,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Accueil',
            ),
            NavigationDestination(
              icon: Badge(
                smallSize: 9,
                isLabelVisible: _watchList.isNotEmpty,
                child: const Icon(Icons.people_outline),
              ),
              selectedIcon: Badge(
                smallSize: 9,
                isLabelVisible: _watchList.isNotEmpty,
                child: const Icon(Icons.people),
              ),
              label: 'Patientes',
            ),
            const NavigationDestination(
              icon: Icon(Icons.edit_note_outlined),
              selectedIcon: Icon(Icons.edit_note),
              label: 'Prescrire',
            ),
            NavigationDestination(
              icon: _badged(Icons.calendar_today_outlined, _pendingCount),
              selectedIcon: _badged(Icons.calendar_today, _pendingCount),
              label: 'RDV',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}
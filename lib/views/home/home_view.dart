import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/ribbon_background.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../services/doctor_directory_service.dart';
import '../../services/care_reminder_service.dart';
import '../../services/realtime_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../messages/conversations_view.dart';
import '../patiente/patient_appointments_view.dart';
import '../patiente/patient_prescriptions_view.dart';
import '../patiente/patient_profile_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final AuthService _authService = AuthService();
  final CareReminderService _careService = CareReminderService();

  String? _patientId;
  String? _patientName;
  Map<String, dynamic>? _nextAppointment;
  int _unreadMessages = 0;
  int _unreadPrescriptions = 0;
  int? _mood;
  List<DoseEntry> _todayDoses = [];
  bool _isLoading = true;

  // Onglets de la barre du bas
  static const int _tabHome = 0;
  static const int _tabAppointments = 1;
  static const int _tabMessages = 2;
  static const int _tabPrescriptions = 3;
  static const int _tabProfile = 4;
  int _currentIndex = _tabHome;
  StreamSubscription<LiveEvent>? _liveSub;

  // Suivi d'humeur : icônes Material (rendu identique sur tous les appareils)
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
  static const List<Color> _moodColors = [
    AppColors.teal,
    AppColors.sky,
    AppColors.amber,
    AppColors.rose,
    AppColors.plum,
  ];
  static const List<String> _moodMessages = [
    'Ravie de l\'entendre. Profitez de cette belle journée.',
    'C\'est une bonne nouvelle. Continuez à prendre soin de vous.',
    'Une journée en demi-teinte. Accordez-vous un peu de repos.',
    'Prenez le temps de vous reposer. N\'hésitez pas à en parler à votre médecin.',
    'Nous sommes là pour vous. Écrivez à votre médecin si vous en ressentez le besoin.',
  ];

  @override
  void initState() {
    super.initState();
    _loadPatientData();
    _liveSub = RealtimeService.instance.events.listen(_onLiveEvent);
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }

  /// Un événement arrive en direct : les pastilles se mettent à jour, et une
  /// alerte s'affiche avec un bouton « Voir ».
  void _onLiveEvent(LiveEvent event) {
    if (!mounted) return;
    _loadPatientData(silent: true);
    if (event.type == LiveEventType.refresh || event.quiet) return;

    final tab = event.type == LiveEventType.message
        ? _tabMessages
        : (event.type == LiveEventType.prescription
            ? _tabPrescriptions
            : _tabAppointments);

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
            _onTabSelected(tab);
          },
        ),
      ),
    );
  }

  /// silent = true : rafraîchit sans remplacer la page par un spinner.
  Future<void> _loadPatientData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final patient = await _authService.getCurrentUser();
      if (patient == null) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        }
        return;
      }

      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // Les cinq lectures sont indépendantes : elles partent ensemble, et
      // l'accueil s'affiche après la plus lente (et non après leur somme).
      final (next, unreadMessages, unreadPrescriptions, todayMood, doses) = await (
        _loadNextAppointment(patient.id, todayStr),
        _countUnread('messages', 'receiver_id', patient.id),
        _countUnread('prescriptions', 'patient_id', patient.id),
        _loadTodayMood(patient.id, todayStr),
        _careService.loadTodayDoses(patient.id),
      ).wait;
      // Reprogramme les notifications du téléphone (sans effet sur le web).
      _careService.syncDeviceNotifications(patient.id);

      if (mounted) {
        setState(() {
          _patientId = patient.id;
          _todayDoses = doses;
          _mood = todayMood ?? _mood;
          _patientName = patient.name.split(' ').first;
          _nextAppointment = next;
          _unreadMessages = unreadMessages;
          _unreadPrescriptions = unreadPrescriptions;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement données patiente: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<Map<String, dynamic>?> _loadNextAppointment(
      String patientId, String todayStr) async {
    try {
      final res = await Supabase.instance.client
          .from('appointments')
          .select('id, doctor_id, date, time, reason, status')
          .eq('patient_id', patientId)
          .gte('date', todayStr)
          .neq('status', 'cancelled')
          .neq('status', 'completed')
          .order('date', ascending: true)
          .order('time', ascending: true)
          .limit(1);

      if (res.isEmpty) return null;

      final appointment = Map<String, dynamic>.from(res.first);
      final doctorId = appointment['doctor_id']?.toString();
      if (doctorId != null) {
        final (doctor, hospital) = await (
          _authService.getUserById(doctorId),
          DoctorDirectoryService().hospitalOf(doctorId),
        ).wait;
        appointment['doctor_name'] = doctor?.name;
        appointment['doctor_hospital'] = hospital;
      }
      return appointment;
    } catch (e) {
      debugPrint('❌ Erreur chargement prochain RDV: $e');
      return null;
    }
  }

  Future<int> _countUnread(String table, String column, String patientId) async {
    try {
      final res = await Supabase.instance.client
          .from(table)
          .select('id')
          .eq(column, patientId)
          .eq('is_read', false);
      return res.length;
    } catch (e) {
      debugPrint('❌ Erreur comptage non lus ($table): $e');
      return 0;
    }
  }

  String _todayString() {
    final t = DateTime.now();
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  /// Humeur déjà enregistrée aujourd'hui (table mood_entries), ou null.
  Future<int?> _loadTodayMood(String patientId, String todayStr) async {
    try {
      final res = await Supabase.instance.client
          .from('mood_entries')
          .select('mood')
          .eq('patient_id', patientId)
          .eq('entry_date', todayStr)
          .limit(1);
      if (res.isEmpty) return null;
      return (res.first['mood'] as num?)?.toInt();
    } catch (e) {
      debugPrint('❌ Erreur chargement humeur: $e');
      return null;
    }
  }

  /// Enregistre (ou met à jour) l'humeur du jour : une seule entrée par jour.
  Future<void> _selectMood(int mood) async {
    setState(() => _mood = mood);

    final patientId = _patientId;
    if (patientId == null) return;

    try {
      await Supabase.instance.client.from('mood_entries').upsert(
        {
          'patient_id': patientId,
          'entry_date': _todayString(),
          'mood': mood,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'patient_id,entry_date',
      );
    } catch (e) {
      debugPrint('❌ Erreur enregistrement humeur: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Votre humeur n\'a pas pu être enregistrée'),
            backgroundColor: AppColors.amber,
          ),
        );
      }
    }
  }

  // ------------------------------------------------------------ Navigation

  void _open(String route) {
    Navigator.pushNamed(context, route).then((_) {
      if (mounted) _loadPatientData(silent: true);
    });
  }

  /// Change d'onglet sans quitter l'écran : la barre du bas reste affichée.
  void _onTabSelected(int index) {
    final previous = _currentIndex;
    setState(() => _currentIndex = index);

    // Les pastilles (messages, ordonnances non lus) se rafraîchissent au retour
    // à l'accueil et quand on quitte les onglets qui les font varier.
    if (index == _tabHome ||
        previous == _tabMessages ||
        previous == _tabPrescriptions) {
      _loadPatientData(silent: true);
    }
  }

  // ----------------------------------------------------------------- Widgets

  Widget _circle(double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }

  Widget _buildHeader() {
    final hello = DateTime.now().hour >= 18 ? 'Bonsoir' : 'Bonjour';
    final name = (_patientName ?? '').trim();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.rose.withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(gradient: AppColors.heroGradient),
          child: Stack(
            children: [
              Positioned(top: -40, right: -30, child: _circle(160, 0.08)),
              Positioned(bottom: -60, left: -40, child: _circle(140, 0.06)),
              const Positioned(
                right: 86,
                bottom: -20,
                child: Opacity(
                  opacity: 0.16,
                  child: RibbonLogo(size: 140, color: Colors.white),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            frenchDateLabel(DateTime.now()),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            name.isEmpty ? hello : '$hello $name',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Prenez soin de vous.',
                            style: TextStyle(color: Colors.white70, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      child: const Center(
                        child: RibbonLogo(size: 30, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoodButton(int i) {
    final selected = _mood == i;
    final color = _moodColors[i];

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _selectMood(i),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: selected ? color : color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _moodIcons[i],
                color: selected ? Colors.white : color,
                size: 28,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _moodLabels[i],
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? color : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodResponse(int mood) {
    final color = _moodColors[mood];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _moodMessages[mood],
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.ink,
              height: 1.4,
            ),
          ),
          if (mood >= 3) ...[
            const SizedBox(height: 8),
            if (mood == 4) ...[
              const Text(
                'En cas d\'urgence, contactez immédiatement les services d\'urgence.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 4),
            ],
            TextButton.icon(
              onPressed: () => _onTabSelected(_tabMessages),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Écrire à mon médecin'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMoodCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Comment vous sentez-vous aujourd\'hui ?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var i = 0; i < _moodIcons.length; i++)
                Expanded(child: _buildMoodButton(i)),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            alignment: Alignment.topCenter,
            child: _mood == null
                ? const SizedBox(width: double.infinity)
                : _buildMoodResponse(_mood!),
          ),
        ],
      ),
    );
  }

  List<String> _dateParts(String dateStr) {
    const months = [
      'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
      'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
    ];
    final parts = dateStr.split('-');
    if (parts.length == 3) {
      final m = int.tryParse(parts[1]);
      return [
        parts[2],
        (m != null && m >= 1 && m <= 12) ? months[m - 1] : '',
      ];
    }
    return ['--', ''];
  }

  Widget _buildDosesCard() {
    final total = _todayDoses.length;
    final done = _todayDoses.where((d) => d.taken).length;
    final now = DateTime.now();
    final pending = _todayDoses.where((d) => !d.taken).toList();

    DoseEntry? next;
    for (final d in pending) {
      if (!d.time.isBefore(now)) {
        next = d;
        break;
      }
    }
    next ??= pending.isNotEmpty ? pending.first : null;

    String message;
    if (pending.isEmpty) {
      message = 'Toutes vos prises du jour sont faites. Bravo !';
    } else if (next != null && next.time.isBefore(now)) {
      message =
          'À prendre : ${next.treatment.name} (prévu à ${CareReminderService.timeString(next.time)})';
    } else if (next != null) {
      message =
          'Prochaine prise à ${CareReminderService.timeString(next.time)} · ${next.treatment.name}';
    } else {
      message = '';
    }

    return AppCard(
      onTap: () => _open('/medications'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.medication_outlined,
                    color: AppColors.teal, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Mes prises du jour',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                '$done / $total',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 8,
              backgroundColor: AppColors.roseSoft,
              color: AppColors.teal,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildNextAppointment() {
    final a = _nextAppointment;

    if (a == null) {
      return AppCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppColors.roseSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.event_available, color: AppColors.rose),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aucun rendez-vous à venir',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Votre médecin vous proposera un créneau.',
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final dateParts = _dateParts(a['date']?.toString() ?? '');
    final doctorName = a['doctor_name']?.toString();
    final hospital = a['doctor_hospital']?.toString() ?? '';
    final time = a['time']?.toString() ?? '';
    final reason = a['reason']?.toString() ?? '';
    final status = a['status']?.toString() ?? 'pending';

    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: () => _onTabSelected(_tabAppointments),
      child: Row(
        children: [
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.roseSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  dateParts[0],
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.rose,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  dateParts[1],
                  style: const TextStyle(fontSize: 12, color: AppColors.rose),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doctorName == null ? 'Consultation' : 'Dr $doctorName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reason.isEmpty ? time : '$time · $reason',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: AppColors.muted),
                ),
                if (hospital.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.local_hospital_outlined,
                        size: 14,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          hospital,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                StatusPill(
                  label: StatusStyle.label(status),
                  color: StatusStyle.color(status),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Grille de 2 colonnes à hauteurs égales, sans risque de débordement.
  Widget _buildTileGrid(List<Widget> tiles) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final second = i + 1 < tiles.length ? tiles[i + 1] : const SizedBox();
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < tiles.length ? 12 : 0),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 12),
                Expanded(child: second),
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _buildHelpCard() {
    return AppCard(
      color: AppColors.roseSoft,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.support_agent, color: AppColors.rose),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Une question ou un doute ?',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Votre équipe soignante est là pour vous accompagner.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _onTabSelected(_tabMessages),
                  child: const Text(
                    'Écrire à mon médecin  →',
                    style: TextStyle(
                      color: AppColors.rose,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomePage() {
    final prescriptionsBadge = _unreadPrescriptions > 0
        ? (_unreadPrescriptions == 1
            ? '1 nouvelle'
            : '$_unreadPrescriptions nouvelles')
        : null;
    final messagesBadge = _unreadMessages > 0
        ? (_unreadMessages == 1 ? '1 non lu' : '$_unreadMessages non lus')
        : null;

    final remainingDoses = _todayDoses.where((d) => !d.taken).length;
    final dosesBadge = remainingDoses > 0 ? '$remainingDoses à prendre' : null;

    final tiles = <Widget>[
      ActionTile(
        icon: Icons.description_outlined,
        title: 'Mes ordonnances',
        subtitle: 'Lire et télécharger',
        color: AppColors.violet,
        badge: prescriptionsBadge,
        onTap: () => _onTabSelected(_tabPrescriptions),
      ),
      ActionTile(
        icon: Icons.chat_bubble_outline,
        title: 'Messages',
        subtitle: 'Écrire à mon médecin',
        color: AppColors.sky,
        badge: messagesBadge,
        onTap: () => _onTabSelected(_tabMessages),
      ),
      ActionTile(
        icon: Icons.healing_outlined,
        title: 'Mes symptômes',
        subtitle: 'Noter comment je vais',
        color: AppColors.rose,
        onTap: () => _open('/symptoms'),
      ),
      ActionTile(
        icon: Icons.medication_outlined,
        title: 'Mes traitements',
        subtitle: 'Médicaments et rappels',
        color: AppColors.teal,
        badge: dosesBadge,
        onTap: () => _open('/medications'),
      ),
      ActionTile(
        icon: Icons.history,
        title: 'Mon historique',
        subtitle: 'Mon suivi dans le temps',
        color: AppColors.plum,
        onTap: () => _open('/history'),
      ),
      ActionTile(
        icon: Icons.photo_library_outlined,
        title: 'Mes photos',
        subtitle: 'Partager avec mon médecin',
        color: AppColors.amber,
        onTap: () => _open('/photo-gallery'),
      ),
    ];

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _loadPatientData(silent: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildMoodCard(),
            if (_todayDoses.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildDosesCard(),
            ],
            const SizedBox(height: 28),
            SectionTitle(
              title: 'Prochain rendez-vous',
              actionLabel: 'Voir tout',
              onAction: () => _onTabSelected(_tabAppointments),
            ),
            _buildNextAppointment(),
            const SizedBox(height: 28),
            const SectionTitle(title: 'Mon suivi'),
            _buildTileGrid(tiles),
            const SizedBox(height: 28),
            _buildHelpCard(),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ Onglets

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case _tabAppointments:
        return const PatientAppointmentsView(embedded: true);
      case _tabMessages:
        return const ConversationsView(embedded: true);
      case _tabPrescriptions:
        return const PatientPrescriptionsView(embedded: true);
      case _tabProfile:
        return const PatientProfileView(embedded: true);
      default:
        return _isLoading
            ? const SkeletonHome()
            : _buildHomePage();
    }
  }

  String get _title {
    switch (_currentIndex) {
      case _tabAppointments:
        return 'Rendez-vous';
      case _tabMessages:
        return 'Messages';
      case _tabPrescriptions:
        return 'Ordonnances';
      case _tabProfile:
        return 'Mon profil';
      default:
        return 'Sunu Yaakaar';
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
          title: isHome
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RibbonLogo(size: 24, color: AppColors.rose),
                    SizedBox(width: 8),
                    Text('Sunu Yaakaar'),
                  ],
                )
              : Text(_title),
          actions: [
            if (isHome)
              IconButton(
                icon: const Icon(Icons.person_outline),
                tooltip: 'Mon profil',
                onPressed: () => _onTabSelected(_tabProfile),
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
            const NavigationDestination(
              icon: Icon(Icons.calendar_today_outlined),
              selectedIcon: Icon(Icons.calendar_today),
              label: 'RDV',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _unreadMessages > 0,
                label: Text('$_unreadMessages'),
                child: const Icon(Icons.chat_bubble_outline),
              ),
              selectedIcon: Badge(
                isLabelVisible: _unreadMessages > 0,
                label: Text('$_unreadMessages'),
                child: const Icon(Icons.chat_bubble),
              ),
              label: 'Messages',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _unreadPrescriptions > 0,
                label: Text('$_unreadPrescriptions'),
                child: const Icon(Icons.description_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: _unreadPrescriptions > 0,
                label: Text('$_unreadPrescriptions'),
                child: const Icon(Icons.description),
              ),
              label: 'Ordonnances',
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

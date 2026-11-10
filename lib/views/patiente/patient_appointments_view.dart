import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/skeleton.dart';
import '../../services/app_errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../../services/appointment_ticket.dart';
import '../../services/auth_service.dart';
import '../../services/care_reminder_service.dart';
import '../../services/care_team_service.dart';
import '../../services/doctor_directory_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/user_avatar.dart';
import 'appointment_ticket_view.dart';

/// Rendez-vous de la patiente : le prochain en évidence, la liste à venir,
/// l'historique par mois, et une prise de rendez-vous guidée en quatre étapes.
class PatientAppointmentsView extends StatefulWidget {
  /// true : utilisé comme contenu d'un onglet (sans barre du haut).
  final bool embedded;

  const PatientAppointmentsView({super.key, this.embedded = false});

  @override
  State<PatientAppointmentsView> createState() => _PatientAppointmentsViewState();
}

class _PatientAppointmentsViewState extends State<PatientAppointmentsView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _appointments = [];
  Map<String, String> _doctorNames = {};
  Map<String, String> _doctorSpecialties = {};
  Map<String, String> _doctorHospitals = {};
  List<UserModel> _doctors = [];
  UserModel? _me;
  bool _isLoading = true;

  /// 0 = à venir, 1 = historique.
  int _tab = 0;

  static const List<String> _weekdays = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
  ];
  static const List<String> _monthsShort = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];
  static const List<String> _monthsFull = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
  ];

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  // ------------------------------------------------------------- Helpers

  String _two(int n) => n.toString().padLeft(2, '0');

  String _timeOf(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _fullDate(DateTime d) =>
      '${_weekdays[d.weekday - 1]} ${d.day} ${_monthsFull[d.month - 1]}';

  Color _darker(Color c) => Color.lerp(c, Colors.black, 0.4)!;

  /// Date et heure d'un rendez-vous : colonnes date + time (utilisées partout
  /// dans l'application), avec repli sur l'ancienne colonne appointment_date.
  DateTime? _dateTimeOf(Map<String, dynamic> a) {
    final date = a['date']?.toString() ?? '';
    final time = a['time']?.toString() ?? '';
    if (date.isNotEmpty) {
      return DateTime.tryParse(time.isEmpty ? date : '$date $time');
    }
    final legacy = a['appointment_date']?.toString() ?? '';
    if (legacy.isNotEmpty) return DateTime.tryParse(legacy)?.toLocal();
    return null;
  }

  bool _isUpcoming(Map<String, dynamic> a) {
    final status = a['status']?.toString();
    if (status == 'cancelled' || status == 'completed') return false;
    final dt = _dateTimeOf(a);
    if (dt == null) return false;
    final now = DateTime.now();
    return !dt.isBefore(DateTime(now.year, now.month, now.day));
  }

  /// Nombre de jours entre aujourd'hui et ce rendez-vous (0 = aujourd'hui).
  int _daysFromToday(DateTime dt) {
    final now = DateTime.now();
    return DateTime.utc(dt.year, dt.month, dt.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
  }

  /// « Aujourd'hui », « Demain », « Dans 5 jours » (ou rien si c'est loin).
  String? _relativeLabel(DateTime? dt) {
    if (dt == null) return null;
    final n = _daysFromToday(dt);
    if (n < 0) return null;
    if (n == 0) return 'Aujourd\'hui';
    if (n == 1) return 'Demain';
    if (n <= 14) return 'Dans $n jours';
    return null;
  }

  String _statusLabel(String status) =>
      status == 'pending' ? 'En attente de confirmation' : StatusStyle.label(status);

  Color _statusColor(String status) =>
      status == 'completed' ? AppColors.muted : StatusStyle.color(status);

  IconData _statusIcon(String status) {
    switch (status) {
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'pending':
        return Icons.schedule;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.task_alt;
    }
  }

  /// Les informations affichées pour un rendez-vous, au même endroit pour la
  /// grande carte et pour les cartes de la liste.
  ({
    String status,
    DateTime? dt,
    String name,
    String specialty,
    String hospital,
    String reason,
    String code,
  }) _info(Map<String, dynamic> a) {
    final doctorId = a['doctor_id']?.toString() ?? '';
    final doctorName = _doctorNames[doctorId] ?? '';
    // Lieu enregistré à la création du rendez-vous ; à défaut (rendez-vous
    // ancien), l'hôpital actuel du médecin.
    final savedHospital = (a['hospital']?.toString() ?? '').trim();
    return (
      status: a['status']?.toString() ?? 'pending',
      dt: _dateTimeOf(a),
      name: doctorName.isEmpty ? 'Consultation' : 'Dr $doctorName',
      specialty: (_doctorSpecialties[doctorId] ?? '').trim(),
      hospital: savedHospital.isNotEmpty ? savedHospital : (_doctorHospitals[doctorId] ?? ''),
      reason: (a['reason']?.toString() ?? '').trim(),
      code: AppointmentTicket.codeFor(a['id'].toString()),
    );
  }

  // ------------------------------------------------------------ Chargement

  Future<void> _loadAppointments({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final response =
          await _supabase.from('appointments').select().eq('patient_id', userId);
      final list = List<Map<String, dynamic>>.from(response);

      final ids = list
          .map((a) => a['doctor_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      // Médecins (noms, spécialités) et hôpitaux : deux lectures indépendantes.
      final ((names, specialties), hospitals) = await (
        _fetchDoctors(ids),
        DoctorDirectoryService().loadHospitals(),
      ).wait;

      if (!mounted) return;
      setState(() {
        _appointments = list;
        _doctorNames = names;
        _doctorSpecialties = specialties;
        _doctorHospitals = hospitals;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erreur chargement RDV : $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<(Map<String, String>, Map<String, String>)> _fetchDoctors(List<String> ids) async {
    final names = <String, String>{};
    final specialties = <String, String>{};
    if (ids.isEmpty) return (names, specialties);
    final docs = await _supabase
        .from('profiles')
        .select('id, name, specialty')
        .inFilter('id', ids);
    for (final d in docs) {
      final id = d['id'].toString();
      names[id] = d['name']?.toString() ?? '';
      specialties[id] = d['specialty']?.toString() ?? '';
    }
    return (names, specialties);
  }

  // ------------------------------------------------------ Prise de rendez-vous

  Future<void> _openBooking() async {
    if (_doctors.isEmpty) _doctors = await _authService.getAllDoctors();
    _me ??= await _authService.getCurrentUser();
    if (!mounted) return;

    if (_doctors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun médecin disponible pour le moment'),
          backgroundColor: AppColors.amber,
        ),
      );
      return;
    }

    // Les médecins de mon équipe d'abord (le référent en tête), puis les autres.
    // Équipe et hôpitaux : deux lectures indépendantes.
    final (team, hospitals) = await (
      CareTeamService().getTeam(),
      DoctorDirectoryService().loadHospitals(),
    ).wait;
    if (!mounted) return;
    final teamIds = team.map((m) => m.doctor.id).toSet();
    final ordered = [
      ...team.map((m) => m.doctor),
      ..._doctors.where((d) => !teamIds.contains(d.id)),
    ];
    final defaultId =
        team.isNotEmpty ? team.first.doctor.id : _me?.treatingDoctorId;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _BookingSheet(
        doctors: ordered,
        defaultDoctorId: defaultId,
        hospitals: hospitals,
        teamIds: teamIds,
      ),
    );

    if (result != null) await _createAppointment(result);
  }

  /// Ouvre le ticket d'un rendez-vous : numéro, code QR, détails, PDF.
  Future<void> _openTicket(Map<String, dynamic> row) async {
    final doctorId = row['doctor_id']?.toString() ?? '';
    final doctor = doctorId.isEmpty ? null : await _authService.getUserById(doctorId);
    _me ??= await _authService.getCurrentUser();
    if (!mounted) return;

    final savedName = (row['patient_name']?.toString() ?? '').trim();
    final ticket = AppointmentTicket.fromRow(
      row,
      patientName: savedName.isNotEmpty ? savedName : (_me?.name ?? ''),
      doctorName: doctor?.name ?? _doctorNames[doctorId] ?? '',
      doctorSpecialty: doctor?.specialty ?? '',
      hospital: _doctorHospitals[doctorId] ?? '',
    );

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AppointmentTicketView(ticket: ticket)),
    );
  }

  Future<void> _createAppointment(Map<String, dynamic> result) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final doctorId = result['doctorId'] as String;
      final date = result['date'] as DateTime;
      final time = result['time'] as TimeOfDay;
      final reason = (result['reason'] as String).trim();

      final created = await _supabase.from('appointments').insert({
        'doctor_id': doctorId,
        'patient_id': userId,
        'patient_name': _me?.name ?? '',
        'date': '${date.year}-${_two(date.month)}-${_two(date.day)}',
        'time': '${_two(time.hour)}:${_two(time.minute)}',
        'reason': reason.isEmpty ? 'Consultation' : reason,
        'status': 'pending',
      }).select().single();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Demande envoyée. Votre médecin va la confirmer.'),
          backgroundColor: AppColors.teal,
        ),
      );
      _loadAppointments(silent: true);
      _syncReminders();

      // La patiente reçoit son ticket tout de suite.
      await _openTicket(Map<String, dynamic>.from(created));
    } catch (e) {
      debugPrint('❌ Erreur création RDV : $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Impossible d\'envoyer la demande. ${AppErrors.message(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // ------------------------------------------------------------ Annulation

  /// Reprogramme les notifications du téléphone après un changement.
  void _syncReminders() {
    final id = _supabase.auth.currentUser?.id;
    if (id != null) CareReminderService().syncDeviceNotifications(id);
  }

  Future<void> _cancelAppointment(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler le rendez-vous'),
        content: const Text('Voulez-vous vraiment annuler ce rendez-vous ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _supabase.rpc('cancel_my_appointment', params: {'p_id': id});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rendez-vous annulé'),
          backgroundColor: AppColors.amber,
        ),
      );
      _loadAppointments(silent: true);
      _syncReminders();
    } catch (e) {
      debugPrint('❌ Erreur annulation RDV : $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Annulation impossible. ${AppErrors.message(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Numéro $code copié'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ------------------------------------------------------------------ UI : prochain rendez-vous

  Widget _heroLine(IconData icon, String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: bold ? Colors.white : Colors.white.withValues(alpha: 0.88),
                fontSize: 14,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Le prochain rendez-vous, en grand : quand, avec qui, où, et les actions.
  Widget _buildNextCard(Map<String, dynamic> a) {
    final i = _info(a);
    final dt = i.dt;
    final rel = _relativeLabel(dt);

    final headline = dt == null
        ? 'Date à confirmer'
        : (rel != null ? '$rel à ${_timeOf(dt)}' : _cap(_fullDate(dt)));
    final subtitle = dt == null
        ? ''
        : (rel != null ? _cap(_fullDate(dt)) : 'à ${_timeOf(dt)}');
    final doctorLine = i.specialty.isEmpty ? i.name : '${i.name} · ${i.specialty}';

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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'PROCHAIN RENDEZ-VOUS',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_statusIcon(i.status), size: 14, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      i.status == 'pending' ? 'En attente' : _statusLabel(i.status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
          const SizedBox(height: 14),
          Divider(color: Colors.white.withValues(alpha: 0.25), height: 1),
          const SizedBox(height: 4),
          _heroLine(Icons.medical_services_outlined, doctorLine, bold: true),
          if (i.hospital.isNotEmpty) _heroLine(Icons.local_hospital_outlined, i.hospital),
          if (i.reason.isNotEmpty) _heroLine(Icons.notes, i.reason),
          InkWell(
            onTap: () => _copyCode(i.code),
            borderRadius: BorderRadius.circular(8),
            child: _heroLine(Icons.confirmation_number_outlined, 'N° ${i.code}  ·  toucher pour copier'),
          ),
          if (i.status == 'pending') ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Votre médecin n\'a pas encore confirmé ce rendez-vous. Vous serez prévenue en direct.',
                style: TextStyle(color: Colors.white, fontSize: 12.5, height: 1.35),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openTicket(a),
                  icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                  label: const Text('Mon ticket'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.rose,
                    minimumSize: const Size(0, 46),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => _cancelAppointment(a['id'].toString()),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 46),
                ),
                child: const Text('Annuler'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ UI : liste

  Widget _dateBlock(DateTime? dt, Color tint) {
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            dt == null ? '' : '${_weekdays[dt.weekday - 1].substring(0, 3)}.',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tint),
          ),
          const SizedBox(height: 2),
          Text(
            dt == null ? '--' : _two(dt.day),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: tint,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            dt == null ? '' : _monthsShort[dt.month - 1],
            style: TextStyle(fontSize: 12, color: tint),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(IconData icon, String text, {Color color = AppColors.muted}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: color, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 14, color: _darker(c)),
          const SizedBox(width: 5),
          Text(
            _statusLabel(status),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _darker(c)),
          ),
        ],
      ),
    );
  }

  Widget _ticketChip(String code) {
    return InkWell(
      onTap: () => _copyCode(code),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.muted.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.confirmation_number_outlined, size: 13, color: AppColors.muted),
            const SizedBox(width: 4),
            Text(
              code,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.copy, size: 11, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> a, {required bool cancellable}) {
    final i = _info(a);
    final inactive = i.status == 'cancelled' || i.status == 'completed';
    final hasTicket = i.status == 'pending' || i.status == 'confirmed';
    final tint = inactive ? AppColors.muted : AppColors.rose;
    final rel = inactive ? null : _relativeLabel(i.dt);
    final time = i.dt == null ? '' : _timeOf(i.dt!);

    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: _statusColor(i.status)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _dateBlock(i.dt, tint),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        i.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
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
                                if (i.specialty.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1),
                                    child: Text(
                                      i.specialty,
                                      style: const TextStyle(fontSize: 12.5, color: AppColors.rose),
                                    ),
                                  ),
                                _infoLine(
                                  Icons.schedule,
                                  i.reason.isEmpty ? time : '$time · ${i.reason}',
                                ),
                                if (i.hospital.isNotEmpty)
                                  _infoLine(Icons.local_hospital_outlined, i.hospital),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _statusPill(i.status),
                          _ticketChip(i.code),
                        ],
                      ),
                      if (cancellable || hasTicket) ...[
                        const SizedBox(height: 6),
                        const Divider(),
                        Row(
                          children: [
                            if (hasTicket)
                              TextButton.icon(
                                onPressed: () => _openTicket(a),
                                icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                                label: const Text('Mon ticket'),
                              ),
                            const Spacer(),
                            if (cancellable)
                              TextButton.icon(
                                onPressed: () => _cancelAppointment(a['id'].toString()),
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('Annuler'),
                                style: TextButton.styleFrom(foregroundColor: AppColors.dangerText),
                              ),
                          ],
                        ),
                      ],
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

  Widget _buildHeader(int upcoming, int past) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mes rendez-vous',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            '$upcoming à venir · $past passé${past > 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(int upcoming, int past) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          ButtonSegment<int>(
            value: 0,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text('À venir ($upcoming)'),
          ),
          ButtonSegment<int>(
            value: 1,
            icon: const Icon(Icons.history, size: 18),
            label: Text('Historique ($past)'),
          ),
        ],
        selected: {_tab},
        onSelectionChanged: (set) => setState(() => _tab = set.first),
      ),
    );
  }

  Widget _emptyBlock(IconData icon, String title, String message, {bool withButton = false}) {
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
          if (withButton) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _openBooking,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Prendre un rendez-vous'),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildUpcoming(List<Map<String, dynamic>> upcoming) {
    if (upcoming.isEmpty) {
      return [
        _emptyBlock(
          Icons.event_available_outlined,
          'Aucun rendez-vous à venir',
          'Demandez un rendez-vous à votre médecin : choisissez un créneau, il le confirmera.',
          withButton: true,
        ),
      ];
    }
    final others = upcoming.skip(1).toList();
    return [
      _buildNextCard(upcoming.first),
      if (others.isNotEmpty) ...[
        const SizedBox(height: 24),
        SectionTitle(title: 'Ensuite (${others.length})'),
        for (var i = 0; i < others.length; i++) ...[
          _buildCard(others[i], cancellable: true),
          if (i < others.length - 1) const SizedBox(height: 12),
        ],
      ],
    ];
  }

  List<Widget> _buildHistory(List<Map<String, dynamic>> history) {
    if (history.isEmpty) {
      return [
        _emptyBlock(
          Icons.history,
          'Pas encore d\'historique',
          'Vos rendez-vous terminés ou annulés apparaîtront ici.',
        ),
      ];
    }
    final out = <Widget>[];
    String? currentMonth;
    for (var i = 0; i < history.length; i++) {
      final dt = _dateTimeOf(history[i]);
      final month = dt == null ? 'Date inconnue' : _cap('${_monthsFull[dt.month - 1]} ${dt.year}');
      if (month != currentMonth) {
        if (currentMonth != null) out.add(const SizedBox(height: 16));
        out.add(SectionTitle(title: month));
        currentMonth = month;
      }
      out.add(_buildCard(history[i], cancellable: false));
      if (i < history.length - 1) out.add(const SizedBox(height: 12));
    }
    return out;
  }

  Widget _buildList() {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);

    final upcoming = _appointments.where(_isUpcoming).toList()
      ..sort((a, b) => (_dateTimeOf(a) ?? epoch).compareTo(_dateTimeOf(b) ?? epoch));
    final history = _appointments.where((a) => !_isUpcoming(a)).toList()
      ..sort((a, b) => (_dateTimeOf(b) ?? epoch).compareTo(_dateTimeOf(a) ?? epoch));

    if (_appointments.isEmpty) {
      return const EmptyState(
        icon: Icons.event_available_outlined,
        title: 'Aucun rendez-vous',
        message:
            'Demandez un rendez-vous à votre médecin : il vous suffit de choisir un créneau.',
      );
    }

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _loadAppointments(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (widget.embedded) _buildHeader(upcoming.length, history.length),
          _buildTabs(upcoming.length, history.length),
          const SizedBox(height: 16),
          if (_tab == 0) ..._buildUpcoming(upcoming) else ..._buildHistory(history),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('Mes rendez-vous')),
      body: _isLoading
          ? const SkeletonList(avatar: false)
          : _buildList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openBooking,
        icon: const Icon(Icons.add),
        label: const Text('Prendre RDV'),
      ),
    );
  }
}

// ====================================================================
// Prise de rendez-vous : quatre étapes (médecin, jour, créneau, motif)
// ====================================================================

/// Feuille de saisie d'une demande de rendez-vous (interface seulement :
/// elle renvoie le choix à l'écran parent, qui enregistre la demande).
class _BookingSheet extends StatefulWidget {
  final List<UserModel> doctors;
  final String? defaultDoctorId;

  /// Identifiant du médecin -> son hôpital (le lieu du rendez-vous).
  final Map<String, String> hospitals;

  /// Identifiants des médecins de l'équipe médicale de la patiente.
  final Set<String> teamIds;

  const _BookingSheet({
    required this.doctors,
    this.defaultDoctorId,
    this.hospitals = const {},
    this.teamIds = const {},
  });

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  late String _doctorId;
  late DateTime _date;
  TimeOfDay? _time;
  String? _reasonChip;
  final _noteController = TextEditingController();
  String? _error;

  static const List<String> _morning = [
    '08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30'
  ];
  static const List<String> _afternoon = [
    '14:00', '14:30', '15:00', '15:30', '16:00', '16:30', '17:00', '17:30'
  ];
  static const List<String> _reasons = [
    'Consultation de suivi',
    'Résultats d\'examens',
    'Renouvellement d\'ordonnance',
    'Effets secondaires',
    'Autre',
  ];
  static const List<String> _weekdaysShort = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  static const List<String> _weekdays = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
  ];
  static const List<String> _monthsShort = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];
  static const List<String> _monthsFull = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
  ];

  @override
  void initState() {
    super.initState();
    final ids = widget.doctors.map((d) => d.id);
    final preferred = widget.defaultDoctorId;
    _doctorId = (preferred != null && ids.contains(preferred))
        ? preferred
        : widget.doctors.first.id;
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day + 1);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ Aides

  String _two(int n) => n.toString().padLeft(2, '0');

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _fullDate(DateTime d) =>
      '${_weekdays[d.weekday - 1]} ${d.day} ${_monthsFull[d.month - 1]}';

  UserModel get _doctor => widget.doctors.firstWhere((d) => d.id == _doctorId);

  String _timeText(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  TimeOfDay _parse(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  bool _slotPassed(String slot) {
    if (!_isToday(_date)) return false;
    final t = _parse(slot);
    final at = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);
    return !at.isAfter(DateTime.now());
  }

  String _reason() {
    final note = _noteController.text.trim();
    final base = (_reasonChip == null || _reasonChip == 'Autre') ? '' : _reasonChip!;
    if (base.isEmpty) return note;
    return note.isEmpty ? base : '$base : $note';
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = DateTime(picked.year, picked.month, picked.day);
        _error = null;
        // Un créneau déjà passé aujourd'hui ne peut pas être conservé.
        final t = _time;
        if (t != null && _slotPassed(_timeText(t))) _time = null;
      });
    }
  }

  Future<void> _pickOtherTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() {
        _time = picked;
        _error = null;
      });
    }
  }

  void _submit() {
    final t = _time;
    if (t == null) {
      setState(() => _error = 'Choisissez un créneau horaire.');
      return;
    }
    final chosen = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);
    if (!chosen.isAfter(DateTime.now())) {
      setState(() => _error = 'Choisissez une date et une heure à venir.');
      return;
    }
    Navigator.pop(context, {
      'doctorId': _doctorId,
      'date': _date,
      'time': t,
      'reason': _reason(),
    });
  }

  // ------------------------------------------------------------ Éléments d'interface

  Widget _step(int n, String title, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.rose, shape: BoxShape.circle),
            child: Text(
              '$n',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hint,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _doctorTile(UserModel d) {
    final selected = d.id == _doctorId;
    final specialty = (d.specialty ?? '').trim();
    final hospital = widget.hospitals[d.id] ?? '';
    final inTeam = widget.teamIds.contains(d.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _doctorId = d.id),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AppColors.roseSoft.withValues(alpha: 0.6) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.rose : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              UserAvatar(name: d.name, url: d.avatarUrl, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Dr ${d.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (inTeam) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.rose.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Mon équipe',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.roseDark,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (specialty.isNotEmpty)
                      Text(
                        specialty,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.rose),
                      ),
                    if (hospital.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.local_hospital_outlined, size: 13, color: AppColors.muted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                hospital,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? AppColors.rose : AppColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayChip(DateTime d) {
    final selected = d.year == _date.year && d.month == _date.month && d.day == _date.day;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() {
        _date = d;
        _error = null;
        final t = _time;
        if (t != null && _slotPassed(_timeText(t))) _time = null;
      }),
      child: Container(
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.rose : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.rose : AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              _weekdaysShort[d.weekday - 1],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.muted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${d.day}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.ink,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _monthsShort[d.month - 1],
              style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.white70 : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotChip(String slot) {
    final passed = _slotPassed(slot);
    final selected = _time != null && _timeText(_time!) == slot;
    return ChoiceChip(
      label: Text(slot),
      selected: selected,
      showCheckmark: false,
      onSelected: passed
          ? null
          : (on) => setState(() {
                _time = on ? _parse(slot) : null;
                _error = null;
              }),
    );
  }

  Widget _slotGroup(String title, List<String> slots) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [for (final s in slots) _slotChip(s)]),
      ],
    );
  }

  Widget _recapLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.rose),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, color: AppColors.ink, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecap() {
    final t = _time;
    if (t == null) return const SizedBox.shrink();
    final d = _doctor;
    final specialty = (d.specialty ?? '').trim();
    final hospital = widget.hospitals[d.id] ?? '';
    final reason = _reason();

    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.roseSoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Récapitulatif de votre demande',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          _recapLine(
            Icons.medical_services_outlined,
            specialty.isEmpty ? 'Dr ${d.name}' : 'Dr ${d.name} · $specialty',
          ),
          _recapLine(Icons.event_outlined, '${_cap(_fullDate(_date))} à ${_timeText(t)}'),
          if (hospital.isNotEmpty) _recapLine(Icons.local_hospital_outlined, hospital),
          if (reason.isNotEmpty) _recapLine(Icons.notes, reason),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = [
      for (var i = 0; i < 14; i++) DateTime(today.year, today.month, today.day + i),
    ];
    final customTime = _time != null &&
        !_morning.contains(_timeText(_time!)) &&
        !_afternoon.contains(_timeText(_time!));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Prendre un rendez-vous',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink),
            ),
            const SizedBox(height: 4),
            const Text(
              'Votre médecin confirmera votre demande. Vous recevrez aussitôt votre ticket.',
              style: TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.35),
            ),

            // 1. Médecin
            _step(1, 'Médecin'),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView(
                shrinkWrap: true,
                children: [for (final d in widget.doctors) _doctorTile(d)],
              ),
            ),

            // 2. Jour
            _step(2, 'Jour', hint: _cap(_fullDate(_date))),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: days.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _dayChip(days[i]),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('Choisir une autre date'),
              ),
            ),

            // 3. Créneau
            _step(3, 'Créneau', hint: _time == null ? 'Choisissez une heure' : _timeText(_time!)),
            _slotGroup('Matin', _morning),
            const SizedBox(height: 10),
            _slotGroup('Après-midi', _afternoon),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickOtherTime,
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(customTime ? 'Autre heure : ${_timeText(_time!)}' : 'Autre heure'),
              ),
            ),

            // 4. Motif
            _step(4, 'Motif', hint: 'facultatif'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final r in _reasons)
                  ChoiceChip(
                    label: Text(r),
                    selected: _reasonChip == r,
                    showCheckmark: false,
                    onSelected: (on) => setState(() => _reasonChip = on ? r : null),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Précisions (facultatif)',
                hintText: 'Ex : douleur au bras depuis 3 jours',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes),
              ),
            ),

            _buildRecap(),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.dangerText, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),

            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _time == null ? null : _submit,
                child: const Text(
                  'Envoyer la demande',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (_time == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Choisissez un créneau pour continuer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
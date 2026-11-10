import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

enum LiveEventType { message, prescription, appointment, refresh }

/// Un événement reçu en direct (nouveau message, nouvelle ordonnance, rendez-vous...).
class LiveEvent {
  final LiveEventType type;
  final String title;
  final String body;

  /// Pour un message : l'expéditeur.
  final String? senderId;

  /// true : ne pas alerter (ex. le message vient de la conversation ouverte).
  final bool quiet;

  const LiveEvent({
    required this.type,
    this.title = '',
    this.body = '',
    this.senderId,
    this.quiet = false,
  });
}

/// Reçoit en direct les changements de la base (Supabase Realtime) qui concernent
/// l'utilisateur connecté, et les diffuse à l'application.
///
/// - Application au premier plan : les écrans affichent une alerte à l'écran.
/// - Application en arrière-plan : une notification du téléphone est affichée.
/// - Application fermée : rien n'est reçu (cela demanderait de vraies
///   notifications push, avec Firebase).
///
/// Par confidentialité, le contenu d'un message n'apparaît jamais dans une alerte :
/// seulement « Nouveau message » et le nom de l'expéditeur.
class RealtimeService with WidgetsBindingObserver {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();

  final StreamController<LiveEvent> _controller =
      StreamController<LiveEvent>.broadcast();

  /// Flux des événements, à écouter depuis les écrans.
  Stream<LiveEvent> get events => _controller.stream;

  /// Interlocuteur de la conversation actuellement ouverte (pas d'alerte pour lui).
  String? activeChatPartnerId;

  bool _initialized = false;
  bool _starting = false;
  bool _foreground = true;
  RealtimeChannel? _channel;
  String? _channelUserId;
  int _notificationId = 0;
  final Map<String, String> _names = {};

  /// À appeler une fois, après l'initialisation de Supabase.
  void init() {
    if (_initialized) return;
    _initialized = true;

    try {
      WidgetsBinding.instance.addObserver(this);
      final client = Supabase.instance.client;

      // Connexion et déconnexion : on démarre ou on arrête l'écoute.
      client.auth.onAuthStateChange.listen((data) {
        if (data.session == null) {
          _stop();
        } else {
          _start();
        }
      });

      if (client.auth.currentSession != null) _start();
    } catch (e) {
      debugPrint('❌ Temps réel non démarré: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      // Au retour, les écrans se remettent à jour (événements éventuellement manqués).
      _controller.add(const LiveEvent(type: LiveEventType.refresh));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _foreground = false;
    }
  }

  // ------------------------------------------------------------- Écoute

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;

    try {
      final client = Supabase.instance.client;
      final me = client.auth.currentUser?.id;
      if (me == null) return;
      if (_channel != null && _channelUserId == me) return;

      await _stop();

      // Selon le profil, on n'écoute pas les mêmes tables.
      var role = 'patient';
      try {
        final res = await client
            .from('profiles')
            .select('user_type')
            .eq('id', me)
            .limit(1);
        if (res.isNotEmpty) role = res.first['user_type']?.toString() ?? 'patient';
      } catch (e) {
        debugPrint('❌ Profil non lu pour le temps réel: $e');
      }

      final channel = client.channel('live-$me');

      // Nouveaux messages reçus (patiente et médecin)
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'receiver_id',
          value: me,
        ),
        callback: _onMessage,
      );

      if (role == 'doctor') {
        // Nouvelle demande de rendez-vous d'une patiente
        channel.onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'appointments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'doctor_id',
            value: me,
          ),
          callback: _onAppointmentRequested,
        );
      } else {
        // Nouvelle ordonnance
        channel.onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'prescriptions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'patient_id',
            value: me,
          ),
          callback: _onPrescription,
        );
        // Rendez-vous confirmé par le médecin
        channel.onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'appointments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'patient_id',
            value: me,
          ),
          callback: _onAppointmentUpdated,
        );
      }

      channel.subscribe();
      _channel = channel;
      _channelUserId = me;
      debugPrint('✅ Temps réel actif ($role)');
    } catch (e) {
      debugPrint('❌ Erreur démarrage du temps réel: $e');
    } finally {
      _starting = false;
    }
  }

  Future<void> _stop() async {
    final channel = _channel;
    _channel = null;
    _channelUserId = null;
    if (channel == null) return;
    try {
      await Supabase.instance.client.removeChannel(channel);
    } catch (e) {
      debugPrint('❌ Erreur arrêt du temps réel: $e');
    }
  }

  // ---------------------------------------------------------- Événements

  Future<void> _onMessage(PostgresChangePayload payload) async {
    final row = payload.newRecord;
    final senderId = row['sender_id']?.toString() ?? '';
    final name = await _nameOf(senderId);

    _emit(LiveEvent(
      type: LiveEventType.message,
      title: 'Nouveau message',
      body: 'De $name',
      senderId: senderId,
      quiet: senderId == activeChatPartnerId,
    ));
  }

  Future<void> _onPrescription(PostgresChangePayload payload) async {
    final row = payload.newRecord;
    var doctor = (row['doctor_name']?.toString() ?? '').trim();
    if (doctor.isEmpty) doctor = await _nameOf(row['doctor_id']?.toString() ?? '');

    _emit(LiveEvent(
      type: LiveEventType.prescription,
      title: 'Nouvelle ordonnance',
      body: 'Dr $doctor vous a envoyé une ordonnance',
    ));
  }

  Future<void> _onAppointmentUpdated(PostgresChangePayload payload) async {
    final row = payload.newRecord;
    if (row['status']?.toString() != 'confirmed') return;

    final doctor = await _nameOf(row['doctor_id']?.toString() ?? '');
    _emit(LiveEvent(
      type: LiveEventType.appointment,
      title: 'Rendez-vous confirmé',
      body: 'Dr $doctor · ${_when(row)}',
    ));
  }

  Future<void> _onAppointmentRequested(PostgresChangePayload payload) async {
    final row = payload.newRecord;
    if (row['status']?.toString() != 'pending') return;

    var patient = (row['patient_name']?.toString() ?? '').trim();
    if (patient.isEmpty) patient = await _nameOf(row['patient_id']?.toString() ?? '');

    _emit(LiveEvent(
      type: LiveEventType.appointment,
      title: 'Nouvelle demande de rendez-vous',
      body: '$patient · ${_when(row)}',
    ));
  }

  // -------------------------------------------------------------- Outils

  void _emit(LiveEvent event) {
    _controller.add(event);
    if (event.quiet) return;

    // En arrière-plan : une notification du téléphone (sans effet sur le web).
    if (!_foreground) {
      _notificationId = (_notificationId + 1) % 500;
      NotificationService.instance.showNow(
        id: 2000 + _notificationId,
        title: event.title,
        body: event.body,
      );
    }
  }

  String _when(Map<String, dynamic> row) {
    final date = row['date']?.toString() ?? '';
    final time = row['time']?.toString() ?? '';
    final d = DateTime.tryParse(date);
    final day = d == null ? date : '${d.day}/${d.month}';
    return time.isEmpty ? day : '$day à $time';
  }

  Future<String> _nameOf(String id) async {
    if (id.isEmpty) return 'un utilisateur';
    final cached = _names[id];
    if (cached != null) return cached;

    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('name')
          .eq('id', id)
          .limit(1);
      if (res.isNotEmpty) {
        final name = res.first['name']?.toString() ?? '';
        if (name.isNotEmpty) {
          _names[id] = name;
          return name;
        }
      }
    } catch (e) {
      debugPrint('❌ Nom non lu: $e');
    }
    return 'un utilisateur';
  }
}
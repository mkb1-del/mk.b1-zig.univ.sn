import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import 'auth_service.dart';

/// Un médecin de l'équipe d'une patiente.
class TeamMember {
  final UserModel doctor;

  /// Médecin référent (l'ancien « médecin traitant »).
  final bool isPrimary;

  const TeamMember({required this.doctor, required this.isPrimary});
}

/// Équipe médicale de la patiente connectée : plusieurs médecins, de
/// spécialités différentes, dont un référent.
///
/// Ajouter un médecin à l'équipe l'autorise à consulter le suivi de la patiente.
/// Ce choix est définitif : il n'existe pas de retrait côté application. Les
/// modifications passent par des fonctions de la base (voir le script « équipe
/// médicale »).
class CareTeamService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();

  /// Dernier message d'erreur technique (utile pour informer ou déboguer).
  String? lastError;

  /// L'équipe, le référent en premier puis par ordre d'ajout.
  Future<List<TeamMember>> getTeam() async {
    lastError = null;
    try {
      final me = _supabase.auth.currentUser?.id;
      if (me == null) return [];

      final rows = await _supabase
          .from('care_team')
          .select('doctor_id, is_primary, created_at')
          .eq('patient_id', me)
          .order('is_primary', ascending: false)
          .order('created_at', ascending: true);

      if (rows.isEmpty) return [];

      final doctors = await _authService.getAllDoctors();
      final byId = {for (final d in doctors) d.id: d};

      final team = <TeamMember>[];
      for (final row in rows) {
        final doctor = byId[row['doctor_id'].toString()];
        if (doctor == null) continue;
        team.add(TeamMember(doctor: doctor, isPrimary: row['is_primary'] == true));
      }
      return team;
    } catch (e) {
      lastError = e.toString();
      debugPrint('❌ Erreur lecture de l\'équipe médicale: $e');
      return [];
    }
  }

  /// Identifiants des médecins de l'équipe.
  Future<Set<String>> getTeamIds() async {
    final team = await getTeam();
    return team.map((m) => m.doctor.id).toSet();
  }

  Future<bool> addDoctor(String doctorId) =>
      _call('add_to_care_team', doctorId);

  Future<bool> setPrimary(String doctorId) =>
      _call('set_primary_doctor', doctorId);

  Future<bool> _call(String function, String doctorId) async {
    lastError = null;
    try {
      await _supabase.rpc(function, params: {'p_doctor': doctorId});
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('❌ Erreur $function: $e');
      return false;
    }
  }
}
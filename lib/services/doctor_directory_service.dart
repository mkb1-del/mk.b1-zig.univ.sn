import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Informations des médecins qui ne sont pas dans le modèle utilisateur
/// (l'hôpital). Toute erreur (colonne pas encore créée sur le serveur) donne
/// simplement un résultat vide : l'application continue de fonctionner.
class DoctorDirectoryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Identifiant du médecin -> hôpital, pour ceux qui l'ont renseigné.
  Future<Map<String, String>> loadHospitals() async {
    try {
      final rows = await _supabase
          .from('profiles')
          .select('id, hospital')
          .eq('user_type', 'doctor');

      final result = <String, String>{};
      for (final row in rows) {
        final hospital = (row['hospital']?.toString() ?? '').trim();
        if (hospital.isNotEmpty) result[row['id'].toString()] = hospital;
      }
      return result;
    } catch (e) {
      debugPrint('ℹ️ Hôpitaux non lus: $e');
      return {};
    }
  }

  /// Lieu enregistré sur une ordonnance au moment de sa création (figé par la
  /// base de données). Vide s'il n'existe pas : l'appelant utilise alors
  /// l'hôpital actuel du médecin.
  Future<String> hospitalOfPrescription(String prescriptionId) =>
      _savedHospital('prescriptions', prescriptionId);

  /// Lieu enregistré sur un rendez-vous au moment de sa création.
  Future<String> hospitalOfAppointment(String appointmentId) =>
      _savedHospital('appointments', appointmentId);

  Future<String> _savedHospital(String table, String id) async {
    try {
      final rows =
          await _supabase.from(table).select('hospital').eq('id', id).limit(1);
      if (rows.isEmpty) return '';
      return (rows.first['hospital']?.toString() ?? '').trim();
    } catch (e) {
      debugPrint('ℹ️ Lieu enregistré non lu ($table): $e');
      return '';
    }
  }

  /// Lieux enregistrés de plusieurs rendez-vous, en une requête
  /// (identifiant du rendez-vous -> hôpital).
  Future<Map<String, String>> hospitalsOfAppointments(List<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final rows = await _supabase
          .from('appointments')
          .select('id, hospital')
          .inFilter('id', ids);

      final result = <String, String>{};
      for (final r in rows) {
        final hospital = (r['hospital']?.toString() ?? '').trim();
        if (hospital.isNotEmpty) result[r['id'].toString()] = hospital;
      }
      return result;
    } catch (e) {
      debugPrint('ℹ️ Lieux des rendez-vous non lus: $e');
      return {};
    }
  }

  /// Hôpital d'un utilisateur (vide si non renseigné).
  Future<String> hospitalOf(String userId) async {
    try {
      final rows = await _supabase
          .from('profiles')
          .select('hospital')
          .eq('id', userId)
          .limit(1);
      if (rows.isEmpty) return '';
      return (rows.first['hospital']?.toString() ?? '').trim();
    } catch (e) {
      debugPrint('ℹ️ Hôpital non lu: $e');
      return '';
    }
  }
}
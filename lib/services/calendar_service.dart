import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/appointment_model.dart';

class CalendarService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Récupère tous les rendez-vous d'un utilisateur
  Future<List<Appointment>> getAppointments(String userId) async {
    try {
      final response = await _supabase
          .from('appointments')
          .select()
          .eq('patient_id', userId)
          .order('date', ascending: true);

      return response.map((map) => Appointment.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur récupération rendez-vous: $e');
      return [];
    }
  }

  /// ✅ Récupère les rendez-vous d'un médecin
  Future<List<Appointment>> getDoctorAppointments(String doctorId) async {
    try {
      final response = await _supabase
          .from('appointments')
          .select()
          .eq('doctor_id', doctorId)
          .order('date', ascending: true);

      return response.map((map) => Appointment.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur récupération rendez-vous médecin: $e');
      return [];
    }
  }

  /// Récupère les rendez-vous d'une date spécifique
  Future<List<Appointment>> getAppointmentsByDate(String userId, String date) async {
    try {
      final response = await _supabase
          .from('appointments')
          .select()
          .eq('patient_id', userId)
          .eq('date', date)
          .order('time', ascending: true);

      return response.map((map) => Appointment.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur récupération rendez-vous par date: $e');
      return [];
    }
  }

  /// Crée un nouveau rendez-vous
  Future<bool> createAppointment(Appointment appointment) async {
    try {
      final response = await _supabase
          .from('appointments')
          .insert(appointment.toMap())
          .select();

      if (response.isNotEmpty) {
        debugPrint('✅ Rendez-vous créé avec succès');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint(' Erreur création rendez-vous: $e');
      return false;
    }
  }

  /// Met à jour un rendez-vous
  Future<bool> updateAppointment(String id, Map<String, dynamic> data) async {
    try {
      await _supabase
          .from('appointments')
          .update(data)
          .eq('id', id);

      debugPrint('✅ Rendez-vous mis à jour');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur mise à jour rendez-vous: $e');
      return false;
    }
  }

  /// Annule un rendez-vous
  Future<bool> cancelAppointment(String id) async {
    try {
      await _supabase
          .from('appointments')
          .update({'status': 'cancelled'})
          .eq('id', id);

      debugPrint('✅ Rendez-vous annulé');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur annulation rendez-vous: $e');
      return false;
    }
  }

  /// Supprime un rendez-vous
  Future<bool> deleteAppointment(String id) async {
    try {
      await _supabase
          .from('appointments')
          .delete()
          .eq('id', id);

      debugPrint('✅ Rendez-vous supprimé');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur suppression rendez-vous: $e');
      return false;
    }
  }
}
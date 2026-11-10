import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/photo_model.dart';
import '../models/appointment_model.dart';
import '../models/prescription_model.dart';
import '../models/symptom_model.dart';
import '../models/message_model.dart';

class SyncService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Récupère la liste des patients d'un médecin
  Future<List<UserModel>> getPatientsForDoctor(String doctorId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('user_type', 'patient')
          .eq('treating_doctor_id', doctorId);

      return response.map((map) => UserModel.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur getPatientsForDoctor: $e');
      return [];
    }
  }

  /// Récupère les photos d'un patient
  Future<List<Photo>> getPatientPhotos(String patientId) async {
    try {
      final response = await _supabase
          .from('photos')
          .select()
          .eq('user_id', patientId)
          .order('created_at', ascending: false);

      return response.map((map) => Photo.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur getPatientPhotos: $e');
      return [];
    }
  }

  /// Récupère les photos associées à un médecin
  Future<List<Photo>> getDoctorPhotos(String doctorId) async {
    try {
      final response = await _supabase
          .from('photos')
          .select()
          .eq('doctor_id', doctorId)
          .order('created_at', ascending: false);

      return response.map((map) => Photo.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur getDoctorPhotos: $e');
      return [];
    }
  }

  /// Marque une photo comme vue
  Future<bool> markPhotoAsViewed(String photoId) async {
    try {
      await _supabase
          .from('photos')
          .update({'is_viewed': true})
          .eq('id', photoId);
      return true;
    } catch (e) {
      debugPrint('❌ Erreur markPhotoAsViewed: $e');
      return false;
    }
  }

  /// Compte les photos non vues par un médecin
  Future<int> getUnviewedPhotosCount(String doctorId) async {
    try {
      final response = await _supabase
          .from('photos')
          .select()
          .eq('doctor_id', doctorId)
          .eq('is_viewed', false);

      return response.length;
    } catch (e) {
      debugPrint('❌ Erreur getUnviewedPhotosCount: $e');
      return 0;
    }
  }

  /// Récupère les rendez-vous d'un patient
  Future<List<Appointment>> getPatientAppointments(String patientId) async {
    try {
      final response = await _supabase
          .from('appointments')
          .select()
          .eq('patient_id', patientId)
          .order('date', ascending: false);

      return response.map((map) => Appointment.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur getPatientAppointments: $e');
      return [];
    }
  }

  /// Récupère les rendez-vous d'un médecin
  Future<List<Appointment>> getDoctorAppointments(String doctorId) async {
    try {
      final response = await _supabase
          .from('appointments')
          .select()
          .eq('doctor_id', doctorId)
          .order('date', ascending: false);

      return response.map((map) => Appointment.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur getDoctorAppointments: $e');
      return [];
    }
  }

  /// Récupère les ordonnances d'un patient
  Future<List<Prescription>> getPatientPrescriptions(String patientId) async {
    try {
      final response = await _supabase
          .from('prescriptions')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: false);

      return response.map((map) => Prescription.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur getPatientPrescriptions: $e');
      return [];
    }
  }

  /// Récupère les ordonnances d'un médecin
  Future<List<Prescription>> getDoctorPrescriptions(String doctorId) async {
    try {
      final response = await _supabase
          .from('prescriptions')
          .select()
          .eq('doctor_id', doctorId)
          .order('created_at', ascending: false);

      return response.map((map) => Prescription.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur getDoctorPrescriptions: $e');
      return [];
    }
  }

  /// Récupère les symptômes d'un patient
  Future<List<Symptom>> getPatientSymptoms(String patientId) async {
    try {
      final response = await _supabase
          .from('symptoms')
          .select()
          .eq('user_id', patientId)
          .order('date', ascending: false);

      return response.map((map) => Symptom.fromMap(map)).toList();
    } catch (e) {
      debugPrint(' Erreur getPatientSymptoms: $e');
      return [];
    }
  }

  /// Récupère les messages entre deux utilisateurs
  Future<List<Message>> getMessages(String userId, String otherUserId) async {
    try {
      final response = await _supabase
          .from('messages')
          .select()
          .or('sender_id.eq.$userId,and(receiver_id.eq.$otherUserId)')
          .or('sender_id.eq.$otherUserId,and(receiver_id.eq.$userId)')
          .order('created_at', ascending: true);

      return response.map((map) => Message.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur getMessages: $e');
      return [];
    }
  }

  /// Compte les messages non lus pour un utilisateur
  Future<int> getUnreadMessagesCount(String userId) async {
    try {
      final response = await _supabase
          .from('messages')
          .select()
          .eq('receiver_id', userId)
          .eq('is_read', false);

      return response.length;
    } catch (e) {
      debugPrint('❌ Erreur getUnreadMessagesCount: $e');
      return 0;
    }
  }

  /// Marque un message comme lu
  Future<bool> markMessageAsRead(String messageId) async {
    try {
      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('id', messageId);
      return true;
    } catch (e) {
      debugPrint('❌ Erreur markMessageAsRead: $e');
      return false;
    }
  }

  /// Statistiques globales pour un médecin
  Future<Map<String, int>> getDoctorStatistics(String doctorId) async {
    try {
      final patients = await _supabase
          .from('profiles')
          .select()
          .eq('user_type', 'patient')
          .eq('treating_doctor_id', doctorId);

      final appointments = await _supabase
          .from('appointments')
          .select()
          .eq('doctor_id', doctorId);

      final prescriptions = await _supabase
          .from('prescriptions')
          .select()
          .eq('doctor_id', doctorId);

      final photos = await _supabase
          .from('photos')
          .select()
          .eq('doctor_id', doctorId);

      final completedAppts = await _supabase
          .from('appointments')
          .select()
          .eq('doctor_id', doctorId)
          .eq('status', 'completed');

      final pendingAppts = await _supabase
          .from('appointments')
          .select()
          .eq('doctor_id', doctorId)
          .eq('status', 'pending');

      final unviewedPhotos = await _supabase
          .from('photos')
          .select()
          .eq('doctor_id', doctorId)
          .eq('is_viewed', false);

      return {
        'totalPatients': patients.length,
        'totalAppointments': appointments.length,
        'totalPrescriptions': prescriptions.length,
        'totalPhotos': photos.length,
        'completedAppointments': completedAppts.length,
        'pendingAppointments': pendingAppts.length,
        'unviewedPhotos': unviewedPhotos.length,
      };
    } catch (e) {
      debugPrint('❌ Erreur getDoctorStatistics: $e');
      return {};
    }
  }

  /// Statistiques globales pour un patient
  Future<Map<String, int>> getPatientStatistics(String patientId) async {
    try {
      final symptoms = await _supabase
          .from('symptoms')
          .select()
          .eq('user_id', patientId);

      final appointments = await _supabase
          .from('appointments')
          .select()
          .eq('patient_id', patientId);

      final prescriptions = await _supabase
          .from('prescriptions')
          .select()
          .eq('patient_id', patientId);

      final photos = await _supabase
          .from('photos')
          .select()
          .eq('user_id', patientId);

      final upcomingAppts = await _supabase
          .from('appointments')
          .select()
          .eq('patient_id', patientId)
          .eq('status', 'pending');

      final unreadPresc = await _supabase
          .from('prescriptions')
          .select()
          .eq('patient_id', patientId)
          .eq('is_read', false);

      return {
        'totalSymptoms': symptoms.length,
        'totalAppointments': appointments.length,
        'totalPrescriptions': prescriptions.length,
        'totalPhotos': photos.length,
        'upcomingAppointments': upcomingAppts.length,
        'unreadPrescriptions': unreadPresc.length,
      };
    } catch (e) {
      debugPrint('❌ Erreur getPatientStatistics: $e');
      return {};
    }
  }
}
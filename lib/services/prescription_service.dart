import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/prescription_model.dart';

class PrescriptionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Crée une nouvelle ordonnance
  Future<Prescription?> createPrescription(Prescription prescription) async {
    try {
      final response = await _supabase
          .from('prescriptions')
          .insert(prescription.toMap())
          .select()
          .single();

      final created = Prescription.fromMap(response);
      debugPrint('✅ Ordonnance créée pour ${created.patientName}');
      return created;
    } catch (e) {
      debugPrint('❌ Erreur création ordonnance: $e');
      return null;
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

      final prescriptions = response.map((map) => Prescription.fromMap(map)).toList();
      debugPrint('📋 Ordonnances patient $patientId: ${prescriptions.length}');
      return prescriptions;
    } catch (e) {
      debugPrint('❌ Erreur récupération ordonnances patient: $e');
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

      final prescriptions = response.map((map) => Prescription.fromMap(map)).toList();
      debugPrint('👨‍⚕️ Ordonnances médecin $doctorId: ${prescriptions.length}');
      return prescriptions;
    } catch (e) {
      debugPrint('❌ Erreur récupération ordonnances médecin: $e');
      return [];
    }
  }

  /// Marque une ordonnance comme lue
  Future<bool> markAsRead(String prescriptionId) async {
    try {
      await _supabase
          .from('prescriptions')
          .update({'is_read': true})
          .eq('id', prescriptionId);

      debugPrint('✅ Ordonnance marquée comme lue: $prescriptionId');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur markAsRead: $e');
      return false;
    }
  }

  /// Supprime une ordonnance
  Future<bool> deletePrescription(String prescriptionId) async {
    try {
      await _supabase
          .from('prescriptions')
          .delete()
          .eq('id', prescriptionId);

      debugPrint('✅ Ordonnance supprimée: $prescriptionId');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur suppression ordonnance: $e');
      return false;
    }
  }

  /// Récupère le nombre total d'ordonnances (CORRIGÉ)
  Future<int> getTotalPrescriptions() async {
    try {
      final response = await _supabase
          .from('prescriptions')
          .select();

      return response.length;
    } catch (e) {
      debugPrint('❌ Erreur getTotalPrescriptions: $e');
      return 0;
    }
  }

  /// Récupère une ordonnance par son ID
  Future<Prescription?> getPrescriptionById(String id) async {
    try {
      final response = await _supabase
          .from('prescriptions')
          .select()
          .eq('id', id)
          .single();

      return Prescription.fromMap(response);
    } catch (e) {
      debugPrint('❌ Erreur récupération ordonnance: $e');
      return null;
    }
  }

  /// Met à jour une ordonnance
  Future<bool> updatePrescription(String id, Map<String, dynamic> data) async {
    try {
      await _supabase
          .from('prescriptions')
          .update(data)
          .eq('id', id);

      debugPrint('✅ Ordonnance mise à jour: $id');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur mise à jour ordonnance: $e');
      return false;
    }
  }
}
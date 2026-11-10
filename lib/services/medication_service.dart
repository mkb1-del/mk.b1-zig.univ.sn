import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/medication_model.dart';

class MedicationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Récupère tous les médicaments d'une prescription
  Future<List<Medication>> getMedications(String prescriptionId) async {
    try {
      final response = await _supabase
          .from('medications')
          .select()
          .eq('prescription_id', prescriptionId);

      return response.map((map) => Medication.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur récupération médicaments: $e');
      return [];
    }
  }

  /// Ajoute un médicament à une prescription
  Future<bool> addMedication(Medication medication) async {
    try {
      final response = await _supabase
          .from('medications')
          .insert(medication.toMap())
          .select();

      if (response.isNotEmpty) {
        debugPrint('✅ Médicament ajouté avec succès');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Erreur ajout médicament: $e');
      return false;
    }
  }

  /// Met à jour un médicament
  Future<bool> updateMedication(String id, Map<String, dynamic> data) async {
    try {
      await _supabase
          .from('medications')
          .update(data)
          .eq('id', id);

      debugPrint('✅ Médicament mis à jour');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur mise à jour médicament: $e');
      return false;
    }
  }

  /// Supprime un médicament
  Future<bool> deleteMedication(String id) async {
    try {
      await _supabase
          .from('medications')
          .delete()
          .eq('id', id);

      debugPrint('✅ Médicament supprimé');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur suppression médicament: $e');
      return false;
    }
  }

  /// Supprime tous les médicaments d'une prescription
  Future<bool> deleteMedicationsByPrescription(String prescriptionId) async {
    try {
      await _supabase
          .from('medications')
          .delete()
          .eq('prescription_id', prescriptionId);

      debugPrint('✅ Tous les médicaments supprimés');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur suppression médicaments: $e');
      return false;
    }
  }
}
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'care_reminder_service.dart';

/// Un suivi quotidien saisi par la patiente (fatigue, douleur, moral de 0 à 5).
class DailyEntry {
  final DateTime day;
  final int fatigue;
  final int pain;
  final int mood;
  final String comment;

  const DailyEntry({
    required this.day,
    required this.fatigue,
    required this.pain,
    required this.mood,
    required this.comment,
  });

  /// Journée à surveiller : douleur ou fatigue élevées, ou moral très bas.
  bool get needsAttention => pain >= 4 || fatigue >= 4 || mood <= 1;
}

/// Synthèse du suivi d'une patiente, telle que son médecin la consulte.
class PatientFollowUp {
  /// Suivis des 30 derniers jours, du plus récent au plus ancien.
  final List<DailyEntry> entries;

  /// Traitements actifs aujourd'hui (issus des ordonnances de ce médecin).
  final List<Treatment> activeTreatments;

  /// Prises prévues et prises cochées sur les 7 derniers jours complets.
  final int expectedDoses;
  final int takenDoses;

  /// Prochain rendez-vous avec ce médecin (date, time, reason, status), s'il existe.
  final Map<String, dynamic>? nextAppointment;

  const PatientFollowUp({
    required this.entries,
    required this.activeTreatments,
    required this.expectedDoses,
    required this.takenDoses,
    required this.nextAppointment,
  });

  /// Des journées à surveiller sur les 3 derniers jours.
  bool get needsAttention {
    final now = DateTime.now();
    final limit = DateTime(now.year, now.month, now.day - 2);
    return entries.any((e) => !e.day.isBefore(limit) && e.needsAttention);
  }

  double? get adherenceRate =>
      expectedDoses == 0 ? null : takenDoses / expectedDoses;
}

/// Accès au suivi des patientes. Les règles de sécurité de la base garantissent
/// qu'un médecin ne lit que le suivi de SES patientes (voir le script SQL
/// « lier médecins et patientes ») : ce service n'a donc pas besoin de filtrer.
class FollowUpService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final CareReminderService _care = CareReminderService();

  DailyEntry? _parse(Map<String, dynamic> row) {
    final day = DateTime.tryParse(row['date']?.toString() ?? '');
    if (day == null) return null;
    return DailyEntry(
      day: day,
      fatigue: (row['fatigue_level'] as num?)?.toInt() ?? 0,
      pain: (row['pain_level'] as num?)?.toInt() ?? 0,
      mood: (row['mood_level'] as num?)?.toInt() ?? 3,
      comment: (row['comment'] as String?)?.trim() ?? '',
    );
  }

  /// patient_id -> nombre de journées « à surveiller » sur les [days] derniers
  /// jours. Ne contient que les patientes concernées.
  Future<Map<String, int>> loadAlerts({int days = 3}) async {
    try {
      final now = DateTime.now();
      final since = CareReminderService.dateString(
        DateTime(now.year, now.month, now.day - (days - 1)),
      );

      final rows = await _supabase
          .from('symptoms')
          .select('patient_id, date, fatigue_level, pain_level, mood_level')
          .gte('date', since);

      final result = <String, int>{};
      for (final row in rows) {
        final entry = _parse(row);
        if (entry == null || !entry.needsAttention) continue;
        final id = row['patient_id'].toString();
        result[id] = (result[id] ?? 0) + 1;
      }
      return result;
    } catch (e) {
      debugPrint('❌ Erreur chargement des alertes: $e');
      return {};
    }
  }

  /// La patiente a-t-elle ajouté ce médecin à son équipe (partage de son suivi) ?
  /// En cas d'erreur (fonction non activée), on suppose que oui.
  Future<bool> isSharedWithMe(String patientId) async {
    try {
      final me = _supabase.auth.currentUser?.id;
      if (me == null) return true;
      final rows = await _supabase
          .from('care_team')
          .select('id')
          .eq('patient_id', patientId)
          .eq('doctor_id', me)
          .limit(1);
      return rows.isNotEmpty;
    } catch (e) {
      debugPrint('❌ Erreur vérification du partage: $e');
      return true;
    }
  }

  /// Synthèse complète d'une patiente. Les trois lectures sont indépendantes :
  /// elles sont lancées ensemble.
  Future<PatientFollowUp> loadPatient(String patientId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final (entries, adherence, next) = await (
      _loadEntries(patientId, today),
      _loadAdherence(patientId, today),
      _loadNextAppointment(patientId, today),
    ).wait;

    return PatientFollowUp(
      entries: entries,
      activeTreatments: adherence.active,
      expectedDoses: adherence.expected,
      takenDoses: adherence.taken,
      nextAppointment: next,
    );
  }

  Future<List<DailyEntry>> _loadEntries(String patientId, DateTime today) async {
    // Suivis des 30 derniers jours
    var entries = <DailyEntry>[];
    try {
      final since = CareReminderService.dateString(
        DateTime(today.year, today.month, today.day - 29),
      );
      final rows = await _supabase
          .from('symptoms')
          .select()
          .eq('patient_id', patientId)
          .gte('date', since)
          .order('date', ascending: false);
      entries = [
        for (final row in rows)
          if (_parse(row) != null) _parse(row)!,
      ];
    } catch (e) {
      debugPrint('❌ Erreur chargement du suivi: $e');
    }

    return entries;
  }

  Future<({List<Treatment> active, int expected, int taken})> _loadAdherence(
    String patientId,
    DateTime today,
  ) async {
    // Traitements actifs et observance (7 derniers jours complets)
    var active = <Treatment>[];
    var expected = 0;
    var taken = 0;
    try {
      final treatments = await _care.loadTreatments(patientId);
      active = treatments.where((t) => t.isActiveOn(today)).toList();

      if (treatments.isNotEmpty) {
        final start = DateTime(today.year, today.month, today.day - 7);
        final end = DateTime(today.year, today.month, today.day - 1);

        final rows = await _supabase
            .from('medication_intakes')
            .select('medication_id, slot, intake_date')
            .eq('patient_id', patientId)
            .gte('intake_date', CareReminderService.dateString(start))
            .lte('intake_date', CareReminderService.dateString(end));

        final takenKeys = <String>{
          for (final r in rows)
            '${r['intake_date']}|${r['medication_id']}|${r['slot']}',
        };

        for (var i = 1; i <= 7; i++) {
          final day = DateTime(today.year, today.month, today.day - i);
          final dayStr = CareReminderService.dateString(day);
          for (final t in treatments.where((t) => t.isActiveOn(day))) {
            for (final slot in t.slots) {
              expected++;
              if (takenKeys.contains('$dayStr|${t.medicationId}|$slot')) taken++;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Erreur calcul de l\'observance: $e');
    }

    return (active: active, expected: expected, taken: taken);
  }

  Future<Map<String, dynamic>?> _loadNextAppointment(
    String patientId,
    DateTime today,
  ) async {
    // Prochain rendez-vous avec ce médecin
    Map<String, dynamic>? next;
    try {
      final me = _supabase.auth.currentUser?.id;
      if (me != null) {
        final rows = await _supabase
            .from('appointments')
            .select('date, time, reason, status')
            .eq('patient_id', patientId)
            .eq('doctor_id', me)
            .gte('date', CareReminderService.dateString(today))
            .neq('status', 'cancelled')
            .neq('status', 'completed')
            .order('date', ascending: true)
            .order('time', ascending: true)
            .limit(1);
        if (rows.isNotEmpty) next = Map<String, dynamic>.from(rows.first);
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement du prochain rendez-vous: $e');
    }

    return next;
  }
}

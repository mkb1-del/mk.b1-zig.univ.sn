import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'doctor_directory_service.dart';
import 'notification_service.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// Réglages de rappel d'une patiente : 4 horaires de prise
/// (matin, midi, soir, coucher) et l'activation de chaque type de rappel.
class ReminderPreferences {
  static const List<String> defaultTimes = ['08:00', '12:00', '19:00', '22:00'];

  final List<String> times;
  final bool medicationReminders;
  final bool appointmentReminders;

  const ReminderPreferences({
    this.times = defaultTimes,
    this.medicationReminders = true,
    this.appointmentReminders = true,
  });

  factory ReminderPreferences.fromMap(Map<String, dynamic> map) {
    String time(String key, String fallback) {
      final value = map[key]?.toString() ?? '';
      if (value.isEmpty) return fallback;
      return value.length >= 5 ? value.substring(0, 5) : value;
    }

    return ReminderPreferences(
      times: [
        time('morning_time', '08:00'),
        time('noon_time', '12:00'),
        time('evening_time', '19:00'),
        time('night_time', '22:00'),
      ],
      medicationReminders: map['medication_reminders'] as bool? ?? true,
      appointmentReminders: map['appointment_reminders'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap(String patientId) {
    return {
      'patient_id': patientId,
      'morning_time': times[0],
      'noon_time': times[1],
      'evening_time': times[2],
      'night_time': times[3],
      'medication_reminders': medicationReminders,
      'appointment_reminders': appointmentReminders,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  ReminderPreferences copyWith({
    List<String>? times,
    bool? medicationReminders,
    bool? appointmentReminders,
  }) {
    return ReminderPreferences(
      times: times ?? this.times,
      medicationReminders: medicationReminders ?? this.medicationReminders,
      appointmentReminders: appointmentReminders ?? this.appointmentReminders,
    );
  }
}

/// Un médicament d'une ordonnance, avec sa période de traitement.
class Treatment {
  final String medicationId;
  final String prescriptionId;
  final String name;
  final String dosage;
  final String? instructions;
  final int timesPerDay;
  final int durationDays;

  /// Jour de la prescription (minuit, heure locale).
  final DateTime startDate;

  const Treatment({
    required this.medicationId,
    required this.prescriptionId,
    required this.name,
    required this.dosage,
    required this.instructions,
    required this.timesPerDay,
    required this.durationDays,
    required this.startDate,
  });

  DateTime get endDate => DateTime(
        startDate.year,
        startDate.month,
        startDate.day + durationDays - 1,
      );

  bool isActiveOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(startDate) && !d.isAfter(endDate);
  }

  /// Nombre de jours restants, jour donné inclus.
  int daysLeftFrom(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return endDate.difference(d).inDays + 1;
  }

  List<int> get slots => CareReminderService.slotsFor(timesPerDay);
}

/// Une prise précise à un horaire donné (ex : Paracétamol, ce soir à 19:00).
class DoseEntry {
  final Treatment treatment;
  final int slot;
  final DateTime time;
  final bool taken;

  const DoseEntry({
    required this.treatment,
    required this.slot,
    required this.time,
    required this.taken,
  });

  String get key => '${treatment.medicationId}|$slot';

  bool isOverdue(DateTime now) => !taken && time.isBefore(now);

  DoseEntry copyWith({bool? taken}) {
    return DoseEntry(
      treatment: treatment,
      slot: slot,
      time: time,
      taken: taken ?? this.taken,
    );
  }
}

class CareReminderService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const List<String> slotLabels = ['Matin', 'Midi', 'Soir', 'Coucher'];

  /// Créneaux utilisés selon le nombre de prises par jour.
  static List<int> slotsFor(int timesPerDay) {
    switch (timesPerDay) {
      case 1:
        return [0];
      case 2:
        return [0, 2];
      case 3:
        return [0, 1, 2];
      default:
        return [0, 1, 2, 3];
    }
  }

  static String dateString(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)}';

  static String timeString(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  /// Transforme "08:30" en date/heure pour le jour donné.
  static DateTime timeOn(DateTime day, String hhmm) {
    final parts = hhmm.split(':');
    final hour = int.tryParse(parts[0]) ?? 8;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  // ------------------------------------------------------------ Préférences

  Future<ReminderPreferences> getPreferences(String patientId) async {
    try {
      final res = await _supabase
          .from('reminder_preferences')
          .select()
          .eq('patient_id', patientId)
          .limit(1);
      if (res.isEmpty) return const ReminderPreferences();
      return ReminderPreferences.fromMap(res.first);
    } catch (e) {
      debugPrint('❌ Erreur lecture préférences rappels: $e');
      return const ReminderPreferences();
    }
  }

  Future<bool> savePreferences(
      String patientId, ReminderPreferences prefs) async {
    try {
      await _supabase
          .from('reminder_preferences')
          .upsert(prefs.toMap(patientId), onConflict: 'patient_id');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur enregistrement préférences rappels: $e');
      return false;
    }
  }

  // ------------------------------------------------------------ Traitements

  static int _parseTimesPerDay(String? text) {
    final match = RegExp(r'(\d+)').firstMatch(text ?? '');
    if (match == null) return 1;
    return int.tryParse(match.group(1)!) ?? 1;
  }

  static int _parseDurationDays(String? text) {
    final lower = (text ?? '').toLowerCase();
    final match = RegExp(r'(\d+)').firstMatch(lower);
    if (match == null) return 7;
    final n = int.tryParse(match.group(1)!) ?? 7;
    if (lower.contains('semaine')) return n * 7;
    if (lower.contains('mois')) return n * 30;
    return n;
  }

  /// Tous les médicaments des ordonnances de la patiente (actifs ou non).
  /// Les anciennes ordonnances sans champs structurés sont interprétées à
  /// partir du texte libre ("3x/jour", "7 jours").
  Future<List<Treatment>> loadTreatments(String patientId) async {
    try {
      final prescriptions = await _supabase
          .from('prescriptions')
          .select('id, created_at')
          .eq('patient_id', patientId);
      if (prescriptions.isEmpty) return [];

      final startById = <String, DateTime>{};
      for (final p in prescriptions) {
        final created =
            DateTime.tryParse(p['created_at']?.toString() ?? '')?.toLocal() ??
                DateTime.now();
        startById[p['id'].toString()] =
            DateTime(created.year, created.month, created.day);
      }

      final meds = await _supabase
          .from('medications')
          .select()
          .inFilter('prescription_id', startById.keys.toList());

      final result = <Treatment>[];
      for (final m in meds) {
        final prescriptionId = m['prescription_id']?.toString() ?? '';
        final start = startById[prescriptionId];
        if (start == null) continue;

        final times = ((m['times_per_day'] as num?)?.toInt() ??
                _parseTimesPerDay(m['frequency']?.toString()))
            .clamp(1, 4)
            .toInt();
        final days = ((m['duration_days'] as num?)?.toInt() ??
                _parseDurationDays(m['duration']?.toString()))
            .clamp(1, 365)
            .toInt();

        final instructions = m['instructions']?.toString().trim();

        result.add(
          Treatment(
            medicationId: m['id'].toString(),
            prescriptionId: prescriptionId,
            name: m['name']?.toString() ?? 'Médicament',
            dosage: m['dosage']?.toString() ?? '',
            instructions:
                (instructions == null || instructions.isEmpty) ? null : instructions,
            timesPerDay: times,
            durationDays: days,
            startDate: start,
          ),
        );
      }
      return result;
    } catch (e) {
      debugPrint('❌ Erreur chargement traitements: $e');
      return [];
    }
  }

  // ----------------------------------------------------------------- Prises

  Future<Set<String>> loadTakenKeys(String patientId, DateTime day) async {
    try {
      final res = await _supabase
          .from('medication_intakes')
          .select('medication_id, slot')
          .eq('patient_id', patientId)
          .eq('intake_date', dateString(day));
      return {
        for (final r in res) '${r['medication_id']}|${(r['slot'] as num).toInt()}'
      };
    } catch (e) {
      debugPrint('❌ Erreur chargement prises: $e');
      return <String>{};
    }
  }

  /// Prises cochées entre deux jours (inclus), en UNE seule requête.
  /// Résultat : date (aaaa-mm-jj) -> ensemble de clés « médicament|créneau ».
  Future<Map<String, Set<String>>> loadTakenKeysByDay(
    String patientId,
    DateTime from,
    DateTime to,
  ) async {
    try {
      final res = await _supabase
          .from('medication_intakes')
          .select('medication_id, slot, intake_date')
          .eq('patient_id', patientId)
          .gte('intake_date', dateString(from))
          .lte('intake_date', dateString(to));

      final byDay = <String, Set<String>>{};
      for (final r in res) {
        final day = r['intake_date'].toString();
        byDay
            .putIfAbsent(day, () => <String>{})
            .add('${r['medication_id']}|${(r['slot'] as num).toInt()}');
      }
      return byDay;
    } catch (e) {
      debugPrint('❌ Erreur chargement des prises (période): $e');
      return <String, Set<String>>{};
    }
  }

  /// Construit la liste des prises d'un jour donné, triée par heure.
  List<DoseEntry> buildDoses({
    required DateTime day,
    required List<Treatment> treatments,
    required ReminderPreferences prefs,
    Set<String> taken = const <String>{},
  }) {
    final doses = <DoseEntry>[];
    for (final t in treatments.where((t) => t.isActiveOn(day))) {
      for (final slot in t.slots) {
        doses.add(
          DoseEntry(
            treatment: t,
            slot: slot,
            time: timeOn(day, prefs.times[slot]),
            taken: taken.contains('${t.medicationId}|$slot'),
          ),
        );
      }
    }
    doses.sort((a, b) => a.time.compareTo(b.time));
    return doses;
  }

  Future<List<DoseEntry>> loadTodayDoses(String patientId) async {
    final today = DateTime.now();
    final treatments = await loadTreatments(patientId);
    if (treatments.isEmpty) return [];
    final prefs = await getPreferences(patientId);
    final taken = await loadTakenKeys(patientId, today);
    return buildDoses(
      day: today,
      treatments: treatments,
      prefs: prefs,
      taken: taken,
    );
  }

  /// Coche ou décoche une prise.
  Future<bool> setTaken({
    required String patientId,
    required String medicationId,
    required DateTime day,
    required int slot,
    required bool taken,
  }) async {
    final date = dateString(day);
    try {
      if (taken) {
        await _supabase.from('medication_intakes').insert({
          'patient_id': patientId,
          'medication_id': medicationId,
          'intake_date': date,
          'slot': slot,
          'taken_at': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        await _supabase
            .from('medication_intakes')
            .delete()
            .eq('patient_id', patientId)
            .eq('medication_id', medicationId)
            .eq('intake_date', date)
            .eq('slot', slot);
      }
      return true;
    } on PostgrestException catch (e) {
      // 23505 : prise déjà enregistrée, ce n'est pas une erreur.
      if (e.code == '23505') return true;
      debugPrint('❌ Erreur enregistrement prise: $e');
      return false;
    } catch (e) {
      debugPrint('❌ Erreur enregistrement prise: $e');
      return false;
    }
  }

  // ------------------------------------------- Notifications du téléphone

  /// Reprogramme toutes les notifications du téléphone :
  /// - prises de médicaments des 3 prochains jours ;
  /// - rendez-vous : la veille et 2 heures avant.
  /// Sans effet dans le navigateur.
  Future<void> syncDeviceNotifications(String patientId) async {
    final notifications = NotificationService.instance;
    if (!notifications.isSupported) return;

    try {
      await notifications.init();
      final prefs = await getPreferences(patientId);
      await notifications.cancelAll();

      var id = 1;
      final now = DateTime.now();

      if (prefs.medicationReminders) {
        final treatments = await loadTreatments(patientId);
        final takenToday = await loadTakenKeys(patientId, now);

        for (var offset = 0; offset < 3; offset++) {
          final day = DateTime(now.year, now.month, now.day + offset);
          final doses = buildDoses(
            day: day,
            treatments: treatments,
            prefs: prefs,
            taken: offset == 0 ? takenToday : const <String>{},
          );

          for (final dose in doses) {
            if (dose.taken || !dose.time.isAfter(now)) continue;
            await notifications.scheduleAt(
              id: id++,
              title: 'C\'est l\'heure de votre traitement',
              body: dose.treatment.dosage.isEmpty
                  ? dose.treatment.name
                  : '${dose.treatment.name} · ${dose.treatment.dosage}',
              when: dose.time,
            );
          }
        }
      }

      if (prefs.appointmentReminders) {
        final appointments = await _supabase
            .from('appointments')
            .select('id, doctor_id, date, time, status')
            .eq('patient_id', patientId)
            .inFilter('status', ['pending', 'confirmed'])
            .gte('date', dateString(now));

        final doctorIds = appointments
            .map((a) => a['doctor_id']?.toString())
            .whereType<String>()
            .toSet()
            .toList();

        final names = <String, String>{};
        if (doctorIds.isNotEmpty) {
          final docs = await _supabase
              .from('profiles')
              .select('id, name')
              .inFilter('id', doctorIds);
          for (final d in docs) {
            names[d['id'].toString()] = d['name']?.toString() ?? '';
          }
        }

        // Hôpital de chaque médecin : le lieu est indiqué dans le rappel.
        final hospitals = await DoctorDirectoryService().loadHospitals();

        for (final a in appointments) {
          final date = a['date']?.toString() ?? '';
          final time = a['time']?.toString() ?? '';
          final when = DateTime.tryParse(time.isEmpty ? date : '$date $time');
          if (when == null) continue;

          final doctor = names[a['doctor_id']?.toString() ?? ''] ?? '';
          final who = doctor.isEmpty ? 'votre médecin' : 'Dr $doctor';
          final hhmm = timeString(when);
          final hospital = hospitals[a['doctor_id']?.toString() ?? ''] ?? '';
          final place = hospital.isEmpty ? '' : ' · $hospital';

          await notifications.scheduleAt(
            id: id++,
            title: 'Rendez-vous demain',
            body: '$who à $hhmm$place',
            when: when.subtract(const Duration(hours: 24)),
          );
          await notifications.scheduleAt(
            id: id++,
            title: 'Rendez-vous dans 2 heures',
            body: '$who à $hhmm$place',
            when: when.subtract(const Duration(hours: 2)),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Erreur synchronisation des notifications: $e');
    }
  }
}

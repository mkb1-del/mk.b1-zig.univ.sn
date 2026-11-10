class Medication {
  final String id;
  final String prescriptionId;
  final String name;
  final String dosage;
  final String frequency;
  final String duration;
  final String? instructions;

  /// Nombre de prises par jour (1 à 4) : sert aux rappels.
  final int? timesPerDay;

  /// Durée du traitement en jours : sert aux rappels.
  final int? durationDays;

  Medication({
    required this.id,
    required this.prescriptionId,
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.duration,
    this.instructions,
    this.timesPerDay,
    this.durationDays,
  });

  factory Medication.fromMap(Map<String, dynamic> map) {
    return Medication(
      id: map['id']?.toString() ?? '',
      prescriptionId: map['prescription_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      dosage: map['dosage']?.toString() ?? '',
      frequency: map['frequency']?.toString() ?? '',
      duration: map['duration']?.toString() ?? '',
      instructions: map['instructions']?.toString(),
      timesPerDay: (map['times_per_day'] as num?)?.toInt(),
      durationDays: (map['duration_days'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      // L'id est généré par Supabase (uuid) : on ne l'envoie que s'il existe.
      if (id.isNotEmpty) 'id': id,
      'prescription_id': prescriptionId,
      'name': name,
      'dosage': dosage,
      'frequency': frequency,
      'duration': duration,
      'instructions': (instructions == null || instructions!.isEmpty)
          ? null
          : instructions,
      if (timesPerDay != null) 'times_per_day': timesPerDay,
      if (durationDays != null) 'duration_days': durationDays,
    };
  }

  Medication copyWith({
    String? id,
    String? prescriptionId,
    String? name,
    String? dosage,
    String? frequency,
    String? duration,
    String? instructions,
    int? timesPerDay,
    int? durationDays,
  }) {
    return Medication(
      id: id ?? this.id,
      prescriptionId: prescriptionId ?? this.prescriptionId,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      frequency: frequency ?? this.frequency,
      duration: duration ?? this.duration,
      instructions: instructions ?? this.instructions,
      timesPerDay: timesPerDay ?? this.timesPerDay,
      durationDays: durationDays ?? this.durationDays,
    );
  }

  String get fullDescription {
    return '$name - $dosage - $frequency pendant $duration';
  }
}
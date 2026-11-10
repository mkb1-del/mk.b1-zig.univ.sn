class PrescriptionMedication {
  final String id;
  final String prescriptionId;
  final String medicationName;
  final String dosage;
  final String frequency;
  final String duration;
  final String? instructions;
  final String? notes;

  PrescriptionMedication({
    required this.id,
    required this.prescriptionId,
    required this.medicationName,
    required this.dosage,
    required this.frequency,
    required this.duration,
    this.instructions,
    this.notes,
  });

  factory PrescriptionMedication.fromMap(Map<String, dynamic> map) {
    return PrescriptionMedication(
      id: map['id']?.toString() ?? '',
      prescriptionId: map['prescription_id']?.toString() ?? '',
      medicationName: map['medication_name']?.toString() ?? '',
      dosage: map['dosage']?.toString() ?? '',
      frequency: map['frequency']?.toString() ?? '',
      duration: map['duration']?.toString() ?? '',
      instructions: map['instructions']?.toString(),
      notes: map['notes']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'prescription_id': prescriptionId,
      'medication_name': medicationName,
      'dosage': dosage,
      'frequency': frequency,
      'duration': duration,
      'instructions': instructions,
      'notes': notes,
    };
  }

  PrescriptionMedication copyWith({
    String? id,
    String? prescriptionId,
    String? medicationName,
    String? dosage,
    String? frequency,
    String? duration,
    String? instructions,
    String? notes,
  }) {
    return PrescriptionMedication(
      id: id ?? this.id,
      prescriptionId: prescriptionId ?? this.prescriptionId,
      medicationName: medicationName ?? this.medicationName,
      dosage: dosage ?? this.dosage,
      frequency: frequency ?? this.frequency,
      duration: duration ?? this.duration,
      instructions: instructions ?? this.instructions,
      notes: notes ?? this.notes,
    );
  }

  String get fullDescription {
    return '$medicationName - $dosage - $frequency pendant $duration';
  }
}
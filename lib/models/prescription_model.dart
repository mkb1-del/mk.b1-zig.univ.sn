class Prescription {
  final String id;
  final String patientId;
  final String doctorId;
  final String patientName;
  final String doctorName;
  final String diagnosis;
  final String treatment;
  final String? notes;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Prescription({
    required this.id,
    required this.patientId,
    required this.doctorId,
    this.patientName = '',
    this.doctorName = '',
    this.diagnosis = '',
    this.treatment = '',
    this.notes,
    this.isRead = false,
    required this.createdAt,
    this.updatedAt,
  });

  factory Prescription.fromMap(Map<String, dynamic> map) {
    return Prescription(
      id: map['id']?.toString() ?? '',
      patientId: map['patient_id']?.toString() ?? '',
      doctorId: map['doctor_id']?.toString() ?? '',
      patientName: map['patient_name']?.toString() ?? '',
      doctorName: map['doctor_name']?.toString() ?? '',
      diagnosis: map['diagnosis']?.toString() ?? '',
      treatment: map['treatment']?.toString() ?? '',
      notes: map['notes']?.toString(),
      isRead: map['is_read'] as bool? ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'].toString())
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      // L'id est généré par Supabase (uuid) : on ne l'envoie que s'il existe.
      if (id.isNotEmpty) 'id': id,
      'patient_id': patientId,
      'doctor_id': doctorId,
      'patient_name': patientName,
      'doctor_name': doctorName,
      'diagnosis': diagnosis,
      'treatment': treatment,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  Prescription copyWith({
    String? id,
    String? patientId,
    String? doctorId,
    String? patientName,
    String? doctorName,
    String? diagnosis,
    String? treatment,
    String? notes,
    bool? isRead,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Prescription(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      doctorId: doctorId ?? this.doctorId,
      patientName: patientName ?? this.patientName,
      doctorName: doctorName ?? this.doctorName,
      diagnosis: diagnosis ?? this.diagnosis,
      treatment: treatment ?? this.treatment,
      notes: notes ?? this.notes,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get dateLabel {
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}
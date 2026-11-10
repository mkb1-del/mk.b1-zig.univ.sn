class Symptom {
  final String id;
  final String userId;
  final String name;
  final String description;
  final String severity; // 'mild', 'moderate', 'severe'
  final String? location;
  final DateTime date;
  final DateTime createdAt;

  Symptom({
    required this.id,
    required this.userId,
    required this.name,
    this.description = '',
    required this.severity,
    this.location,
    required this.date,
    required this.createdAt,
  });

  factory Symptom.fromMap(Map<String, dynamic> map) {
    return Symptom(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      severity: map['severity']?.toString() ?? 'moderate',
      location: map['location']?.toString(),
      date: map['date'] != null
          ? DateTime.parse(map['date'].toString())
          : DateTime.now(),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'description': description,
      'severity': severity,
      'location': location,
      'date': date.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  Symptom copyWith({
    String? id,
    String? userId,
    String? name,
    String? description,
    String? severity,
    String? location,
    DateTime? date,
    DateTime? createdAt,
  }) {
    return Symptom(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      description: description ?? this.description,
      severity: severity ?? this.severity,
      location: location ?? this.location,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get severityLabel {
    switch (severity) {
      case 'mild':
        return 'Léger';
      case 'moderate':
        return 'Modéré';
      case 'severe':
        return 'Sévère';
      default:
        return severity;
    }
  }

  String get dateLabel {
    return '${date.day}/${date.month}/${date.year}';
  }
}
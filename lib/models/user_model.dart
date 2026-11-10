class UserModel {
  final String id;
  final String email;
  final String name;
  final String? phone;
  final String userType;
  final String? specialty;
  final String? bio;
  final String? avatarUrl;
  final String? treatingDoctorId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  UserModel({
    required this.id,
    required this.email,
    required this.name,
    this.phone,
    required this.userType,
    this.specialty,
    this.bio,
    this.avatarUrl,
    this.treatingDoctorId,
    required this.createdAt,
    this.updatedAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString(),
      userType: map['user_type']?.toString() ?? 'patient',
      specialty: map['specialty']?.toString(),
      bio: map['bio']?.toString(),
      avatarUrl: map['avatar_url']?.toString(),
      treatingDoctorId: map['treating_doctor_id']?.toString(),
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
      'id': id,
      'email': email,
      'name': name,
      'phone': phone,
      'user_type': userType,
      'specialty': specialty,
      'bio': bio,
      'avatar_url': avatarUrl,
      'treating_doctor_id': treatingDoctorId,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    String? phone,
    String? userType,
    String? specialty,
    String? bio,
    String? avatarUrl,
    String? treatingDoctorId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      userType: userType ?? this.userType,
      specialty: specialty ?? this.specialty,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      treatingDoctorId: treatingDoctorId ?? this.treatingDoctorId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isDoctor => userType == 'doctor';
  bool get isPatient => userType == 'patient';
  String get displayName => isDoctor ? 'Dr. $name' : name;

  // ✅ AJOUT : Getter pour la date formatée
  String get dateLabel {
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}
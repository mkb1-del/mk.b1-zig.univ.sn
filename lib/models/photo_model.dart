class Photo {
  final String id;
  final String userId;
  final String url;
  final String type; // 'selfie', 'medical', 'document'
  final String? description;
  final DateTime createdAt;

  Photo({
    required this.id,
    required this.userId,
    required this.url,
    required this.type,
    this.description,
    required this.createdAt,
  });

  factory Photo.fromMap(Map<String, dynamic> map) {
    return Photo(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
      type: map['type']?.toString() ?? 'selfie',
      description: map['description']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'url': url,
      'type': type,
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Photo copyWith({
    String? id,
    String? userId,
    String? url,
    String? type,
    String? description,
    DateTime? createdAt,
  }) {
    return Photo(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      url: url ?? this.url,
      type: type ?? this.type,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get typeLabel {
    switch (type) {
      case 'selfie':
        return 'Photo personnelle';
      case 'medical':
        return 'Photo médicale';
      case 'document':
        return 'Document';
      default:
        return type;
    }
  }

  String get dateLabel {
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}
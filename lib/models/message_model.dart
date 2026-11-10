enum MessageType {
  text,
  voice,
  photo,
}

enum MessageStatus {
  pending,
  sent,
  delivered,
  read,
}

class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String? conversationId;
  final String content;
  final MessageType type;
  final String? mediaUrl;
  final int? duration;
  final bool isRead;
  final MessageStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.conversationId,
    required this.content,
    required this.type,
    this.mediaUrl,
    this.duration,
    this.isRead = false,
    this.status = MessageStatus.pending,
    required this.createdAt,
    this.updatedAt,
  });

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id']?.toString() ?? '',
      senderId: map['sender_id']?.toString() ?? '',
      receiverId: map['receiver_id']?.toString() ?? '',
      conversationId: map['conversation_id']?.toString(),
      content: map['content']?.toString() ?? '',
      type: _getMessageType(map['type']?.toString()),
      mediaUrl: map['media_url']?.toString(),
      duration: map['duration'] as int?,
      isRead: map['is_read'] as bool? ?? false,
      status: _getStatus(map['status']?.toString()),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'].toString())
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'].toString())
          : null,
    );
  }

  static MessageType _getMessageType(String? type) {
    switch (type?.toLowerCase()) {
      case 'voice':
        return MessageType.voice;
      case 'photo':
        return MessageType.photo;
      default:
        return MessageType.text;
    }
  }

  static MessageStatus _getStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      default:
        return MessageStatus.pending;
    }
  }

  Map<String, dynamic> toMap({bool includeId = false}) {
    return {
      if (includeId && id.isNotEmpty) 'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'conversation_id': conversationId,
      'content': content,
      'type': _typeToString(type),
      'media_url': mediaUrl,
      'duration': duration,
      'is_read': isRead,
      'status': _statusToString(status),
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  String _typeToString(MessageType type) {
    switch (type) {
      case MessageType.text:
        return 'text';
      case MessageType.voice:
        return 'voice';
      case MessageType.photo:
        return 'photo';
    }
  }

  String _statusToString(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
        return 'pending';
      case MessageStatus.sent:
        return 'sent';
      case MessageStatus.delivered:
        return 'delivered';
      case MessageStatus.read:
        return 'read';
    }
  }

  Message copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? conversationId,
    String? content,
    MessageType? type,
    String? mediaUrl,
    int? duration,
    bool? isRead,
    MessageStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      conversationId: conversationId ?? this.conversationId,
      content: content ?? this.content,
      type: type ?? this.type,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      duration: duration ?? this.duration,
      isRead: isRead ?? this.isRead,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isText => type == MessageType.text;
  bool get isVoice => type == MessageType.voice;
  bool get isPhoto => type == MessageType.photo;

  String get timeLabel {
    return '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
  }

  String get dateLabel {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays == 0) {
      return "Aujourd'hui";
    } else if (difference.inDays == 1) {
      return 'Hier';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} jours';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }
}
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../models/message_model.dart';

/// Une page de messages d'une conversation, du plus ancien au plus récent.
class MessagePage {
  final List<Message> messages;

  /// Date du message le plus ancien et du plus récent de cette page (texte brut
  /// renvoyé par le serveur, réutilisé tel quel pour demander la suite).
  final String? oldestCreatedAt;
  final String? newestCreatedAt;

  /// Il existe des messages plus anciens que cette page.
  final bool hasMore;

  const MessagePage({
    required this.messages,
    required this.oldestCreatedAt,
    required this.newestCreatedAt,
    required this.hasMore,
  });

  /// [rows] : lignes du serveur, du plus récent au plus ancien.
  factory MessagePage.fromNewestFirst(List<Map<String, dynamic>> rows, {required bool hasMore}) {
    return MessagePage(
      messages: [for (final row in rows.reversed) Message.fromMap(row)],
      oldestCreatedAt: rows.isEmpty ? null : rows.last['created_at']?.toString(),
      newestCreatedAt: rows.isEmpty ? null : rows.first['created_at']?.toString(),
      hasMore: hasMore,
    );
  }
}

class MessageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AudioRecorder _audioRecorder = AudioRecorder();

  String? _lastRecordingPath;

  String getConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  /// Nombre de messages chargés à la fois.
  static const int pageSize = 40;

  /// Les [limit] messages les plus récents, ou les [limit] qui précèdent [before].
  /// Les erreurs sont relancées : c'est l'écran qui décide quoi afficher.
  Future<MessagePage> getConversationPage(
    String currentUserId,
    String otherUserId, {
    String? before,
    int limit = pageSize,
  }) async {
    try {
      final conversationId = getConversationId(currentUserId, otherUserId);

      var query = _supabase
          .from('messages')
          .select()
          .eq('conversation_id', conversationId);
      if (before != null) query = query.lt('created_at', before);

      final rows = await query.order('created_at', ascending: false).limit(limit);
      return MessagePage.fromNewestFirst(
        List<Map<String, dynamic>>.from(rows),
        hasMore: rows.length >= limit,
      );
    } catch (e) {
      debugPrint('❌ Erreur page de conversation: $e');
      rethrow;
    }
  }

  /// Seulement les messages plus récents que [after] (date du dernier message
  /// déjà affiché) : bien plus léger que de recharger toute la conversation.
  Future<MessagePage> getMessagesAfter(
    String currentUserId,
    String otherUserId,
    String after,
  ) async {
    try {
      final conversationId = getConversationId(currentUserId, otherUserId);

      final rows = await _supabase
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .gt('created_at', after)
          .order('created_at', ascending: true);

      final list = List<Map<String, dynamic>>.from(rows);
      return MessagePage(
        messages: [for (final row in list) Message.fromMap(row)],
        oldestCreatedAt: list.isEmpty ? null : list.first['created_at']?.toString(),
        newestCreatedAt: list.isEmpty ? null : list.last['created_at']?.toString(),
        hasMore: false,
      );
    } catch (e) {
      debugPrint('❌ Erreur nouveaux messages: $e');
      rethrow;
    }
  }

  /// Messages non lus de chaque interlocuteur, en UNE requête (identifiant de
  /// l'expéditeur -> nombre). Renvoie une table vide en cas d'erreur : ce
  /// compteur est secondaire et ne doit pas bloquer l'écran.
  Future<Map<String, int>> getUnreadCountsBySender(String currentUserId) async {
    try {
      final rows = await _supabase
          .from('messages')
          .select('sender_id')
          .eq('receiver_id', currentUserId)
          .eq('is_read', false);

      final counts = <String, int>{};
      for (final row in rows) {
        final id = row['sender_id']?.toString();
        if (id != null) counts[id] = (counts[id] ?? 0) + 1;
      }
      return counts;
    } catch (e) {
      debugPrint('❌ Erreur comptage des non lus: $e');
      return {};
    }
  }

  Future<List<Message>> getConversation(String currentUserId, String otherUserId) async {
    try {
      final conversationId = getConversationId(currentUserId, otherUserId);

      final response = await _supabase
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);

      return response.map((map) => Message.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur récupération conversation: $e');
      return [];
    }
  }

  Future<int> getUnreadMessagesCount(String currentUserId, String otherUserId) async {
    try {
      final conversationId = getConversationId(currentUserId, otherUserId);

      final response = await _supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .eq('receiver_id', currentUserId)
          .eq('is_read', false);

      return response.length;
    } catch (e) {
      debugPrint('❌ Erreur comptage messages non lus: $e');
      return 0;
    }
  }

  Future<bool> markAllMessagesAsRead(String currentUserId, String otherUserId) async {
    try {
      final conversationId = getConversationId(currentUserId, otherUserId);

      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('conversation_id', conversationId)
          .eq('receiver_id', currentUserId)
          .eq('is_read', false);

      debugPrint('✅ Tous les messages marqués comme lus');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur marquage tous messages lus: $e');
      return false;
    }
  }

  Future<Message?> sendTextMessage({
    required String senderId,
    required String receiverId,
    required String content,
  }) async {
    try {
      final conversationId = getConversationId(senderId, receiverId);

      final message = Message(
        id: '',
        senderId: senderId,
        receiverId: receiverId,
        conversationId: conversationId,
        content: content,
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
      );

      final response = await _supabase
          .from('messages')
          .insert(message.toMap(includeId: false))
          .select()
          .single();

      final sentMessage = Message.fromMap(response);
      debugPrint('✅ Message texte envoyé');
      return sentMessage;
    } catch (e) {
      debugPrint('❌ Erreur envoi message texte: $e');
      return null;
    }
  }

  Future<Message?> sendVoiceMessage({
    required String senderId,
    required String receiverId,
    required int duration,
  }) async {
    try {
      if (_lastRecordingPath == null) {
        throw Exception('Aucun enregistrement en cours');
      }

      final mediaUrl = await _uploadAudioFile(_lastRecordingPath!, senderId);
      if (mediaUrl == null) throw Exception('Échec upload audio');

      if (!kIsWeb) {
        try {
          final file = File(_lastRecordingPath!);
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
      _lastRecordingPath = null;

      final conversationId = getConversationId(senderId, receiverId);

      final message = Message(
        id: '',
        senderId: senderId,
        receiverId: receiverId,
        conversationId: conversationId,
        content: '🎙️ Message vocal',
        type: MessageType.voice,
        mediaUrl: mediaUrl,
        duration: duration,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
      );

      final response = await _supabase
          .from('messages')
          .insert(message.toMap(includeId: false))
          .select()
          .single();

      final sentMessage = Message.fromMap(response);
      debugPrint('✅ Message vocal envoyé');
      return sentMessage;
    } catch (e) {
      debugPrint('❌ Erreur envoi message vocal: $e');
      return null;
    }
  }

  Future<Message?> sendPhotoMessage({
    required String senderId,
    required String receiverId,
    required String filePath,
    String? caption,
    String? mimeType,
  }) async {
    try {
      final mediaUrl = await _uploadPhotoFile(filePath, senderId, mimeType);
      if (mediaUrl == null) throw Exception('Échec upload photo');

      final conversationId = getConversationId(senderId, receiverId);

      final message = Message(
        id: '',
        senderId: senderId,
        receiverId: receiverId,
        conversationId: conversationId,
        content: caption ?? 'Photo',
        type: MessageType.photo,
        mediaUrl: mediaUrl,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
      );

      final response = await _supabase
          .from('messages')
          .insert(message.toMap(includeId: false))
          .select()
          .single();

      final sentMessage = Message.fromMap(response);
      debugPrint('✅ Message photo envoyé');
      return sentMessage;
    } catch (e) {
      debugPrint('❌ Erreur envoi message photo: $e');
      return null;
    }
  }

  /// Récupère les octets d'un fichier, que ce soit un vrai chemin local
  /// (mobile/desktop) ou une URL blob: générée par le navigateur (web).
  Future<Uint8List> _readBytes(String filePath) async {
    if (kIsWeb) {
      final response = await http.get(Uri.parse(filePath));
      return response.bodyBytes;
    } else {
      final file = File(filePath);
      return await file.readAsBytes();
    }
  }

  /// Déduit une extension de fichier cohérente avec le type MIME réel,
  /// pour éviter d'envoyer par exemple un PNG étiqueté comme un JPEG.
  String _extensionForMimeType(String? mimeType) {
    switch (mimeType) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      case 'image/jpeg':
      case null:
      default:
        return 'jpg';
    }
  }

  Future<String?> _uploadAudioFile(String filePath, String userId) async {
    try {
      final fileName = '$userId/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final bytes = await _readBytes(filePath);

      await _supabase.storage.from('messages').uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: false,
              contentType: 'audio/m4a',
            ),
          );

      final publicUrl = _supabase.storage.from('messages').getPublicUrl(fileName);
      debugPrint('✅ Audio uploadé: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('❌ Erreur upload audio: $e');
      return null;
    }
  }

  Future<String?> _uploadPhotoFile(String filePath, String userId, String? mimeType) async {
    try {
      // Type MIME réel, déterminé par l'appelant (XFile.mimeType) quand
      // disponible ; on retombe sur jpeg si inconnu.
      final effectiveMimeType = mimeType ?? 'image/jpeg';
      final extension = _extensionForMimeType(effectiveMimeType);
      final fileName = '$userId/photo_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final bytes = await _readBytes(filePath);

      await _supabase.storage.from('messages').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: false,
              contentType: effectiveMimeType,
            ),
          );

      final publicUrl = _supabase.storage.from('messages').getPublicUrl(fileName);
      debugPrint('✅ Photo uploadée ($effectiveMimeType): $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('❌ Erreur upload photo: $e');
      return null;
    }
  }

  Future<bool> startRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        throw Exception('Permission microphone non accordée');
      }

      String path;
      if (kIsWeb) {
        path = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      } else {
        final directory = await getApplicationDocumentsDirectory();
        path = '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      _lastRecordingPath = path;

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      debugPrint('🎙️ Enregistrement vocal démarré');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur démarrage enregistrement: $e');
      return false;
    }
  }

  Future<int?> stopRecording() async {
    try {
      final resultPath = await _audioRecorder.stop();
      if (resultPath == null) return null;

      if (kIsWeb) {
        _lastRecordingPath = resultPath;
        return null;
      } else {
        final duration = await _getAudioDuration(_lastRecordingPath!);
        debugPrint('⏱️ Enregistrement terminé: ${duration}s');
        return duration;
      }
    } catch (e) {
      debugPrint('❌ Erreur arrêt enregistrement: $e');
      return null;
    }
  }

  Future<void> cancelRecording() async {
    try {
      await _audioRecorder.stop();
      if (!kIsWeb && _lastRecordingPath != null) {
        final file = File(_lastRecordingPath!);
        if (file.existsSync()) file.deleteSync();
      }
      debugPrint('🗑️ Enregistrement annulé');
    } catch (e) {
      debugPrint('❌ Erreur annulation enregistrement: $e');
    } finally {
      _lastRecordingPath = null;
    }
  }

  Future<bool> deleteMessage(String messageId) async {
    try {
      await _supabase
          .from('messages')
          .delete()
          .eq('id', messageId);

      debugPrint('✅ Message supprimé');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur suppression message: $e');
      return false;
    }
  }

  Future<int> _getAudioDuration(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final size = await file.length();
        return (size / 16000).round().clamp(1, 300);
      }
      return 0;
    } catch (e) {
      debugPrint('❌ Erreur calcul durée audio: $e');
      return 0;
    }
  }

  void dispose() {
    _audioRecorder.dispose();
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signUp(String email, String password, Map<String, dynamic> metadata) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: metadata,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<List<Map<String, dynamic>>> fetchPatients(String doctorId) async {
    final response = await _client
        .from('patients')
        .select()
        .eq('doctor_id', doctorId);
    
    return response;
  }

  Future<List<Map<String, dynamic>>> fetchAppointments(String doctorId) async {
    final response = await _client
        .from('appointments')
        .select()
        .eq('doctor_id', doctorId);
    
    return response;
  }

  Stream<List<Map<String, dynamic>>> getMessagesStream(String conversationId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map((data) => data);
  }

  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
    String? messageType = 'text',
  }) async {
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
      'message_type': messageType,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> sendAudioMessage({
    required String conversationId,
    required String senderId,
    required String audioUrl,
    required int duration,
  }) async {
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': audioUrl,
      'message_type': 'audio',
      'duration': duration,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<String> downloadAudioFile(String filePath) async {
    await _client.storage
        .from('audio_messages')
        .download(filePath);
    
    return filePath;
  }

  Future<String> uploadFile(String bucket, String filePath, dynamic file) async {
    await _client.storage
        .from(bucket)
        .upload(filePath, file);
    
    return _client.storage
        .from(bucket)
        .getPublicUrl(filePath);
  }

  Future<Map<String, dynamic>> createConversation({
    required String participant1Id,
    required String participant2Id,
    required String participant1Type,
    required String participant2Type,
  }) async {
    final response = await _client.from('conversations').insert({
      'participant1_id': participant1Id,
      'participant2_id': participant2Id,
      'participant1_type': participant1Type,
      'participant2_type': participant2Type,
      'created_at': DateTime.now().toIso8601String(),
    }).select().single();

    return response;
  }

  Future<List<Map<String, dynamic>>> getConversations(String userId) async {
    final response = await _client
        .from('conversations')
        .select()
        .or('participant1_id.eq.$userId,participant2_id.eq.$userId');
    
    return response;
  }
}
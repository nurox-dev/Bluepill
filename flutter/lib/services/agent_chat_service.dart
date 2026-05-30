import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class AgentChatService {
  AgentChatService({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> getConversations(
    String userId, {
    int limit = 40,
  }) async {
    final data = await _client
        .from('agent_conversations')
        .select()
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .limit(limit);
    return _rows(data);
  }

  Future<Map<String, dynamic>> createConversation({
    required String userId,
    required String title,
  }) async {
    final data = await _client
        .from('agent_conversations')
        .insert({
          'user_id': userId,
          'title': title,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> updateConversation({
    required Object conversationId,
    required String title,
  }) async {
    await _client.from('agent_conversations').update({
      'title': title,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', conversationId);
  }

  Future<void> deleteConversation(Object conversationId) async {
    await _client.from('agent_conversations').delete().eq('id', conversationId);
  }

  Future<List<Map<String, dynamic>>> getMessages({
    required String userId,
    required Object conversationId,
  }) async {
    final data = await _client
        .from('agent_messages')
        .select()
        .eq('user_id', userId)
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
    return _rows(data);
  }

  Future<void> saveMessage({
    required String userId,
    required Object conversationId,
    required String role,
    required String text,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    await _client.from('agent_messages').insert({
      'user_id': userId,
      'conversation_id': conversationId,
      'role': role,
      'text': text,
      'attachments': attachments,
    });
    await _client.from('agent_conversations').update({
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', conversationId);
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data == null) return [];
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }
}

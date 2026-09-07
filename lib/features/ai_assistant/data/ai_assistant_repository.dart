import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/result.dart';
import '../domain/chat_message.dart';

/// Sends a user message + the deterministic context packet (built by
/// [AiContextBuilder]) to the `ai-assistant` Supabase Edge Function, and
/// persists both sides of the exchange to `ai_conversations`/
/// `ai_messages` (schema.sql).
///
/// Per plan section 17, no LLM provider API key is ever embedded in the
/// Flutter app. The actual model call happens server-side in the edge
/// function (`supabase/functions/ai-assistant/index.ts`), which holds
/// the real secret via `supabase secrets set`. This repository only
/// ever talks to Supabase, with the anon key — the same key already
/// used for auth and reads elsewhere in the app.
class AiAssistantRepository {
  final sb.SupabaseClient _client;

  AiAssistantRepository(this._client);

  Future<Result<String>> ensureConversation(String appUserId) async {
    try {
      final row = await _client
          .from('ai_conversations')
          .insert({'user_id': appUserId})
          .select('id')
          .single();
      return Result.ok(row['id'] as String);
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  Future<Result<List<ChatMessage>>> loadMessages(String conversationId) async {
    try {
      final rows = await _client
          .from('ai_messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at');
      return Result.ok(
        (rows as List).cast<Map<String, dynamic>>().map(ChatMessage.fromSupabaseRow).toList(),
      );
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  /// Sends [userMessage] plus [context] (from [AiContextBuilder]) to the
  /// edge function, persists both the user's message and the model's
  /// reply, and returns the reply text.
  Future<Result<String>> sendMessage({
    required String conversationId,
    required String userMessage,
    required Map<String, dynamic> context,
  }) async {
    try {
      await _client.from('ai_messages').insert({
        'conversation_id': conversationId,
        'role': 'user',
        'content': userMessage,
      });

      final response = await _client.functions.invoke(
        'ai-assistant',
        body: {
          'message': userMessage,
          'context': context,
        },
      );

      if (response.status != 200) {
        return Result.err(AppFailure(
          AppFailureType.network,
          'AI assistant returned status ${response.status}',
        ));
      }

      final replyText = (response.data as Map)['reply'] as String? ??
          "I couldn't generate a response just now.";

      await _client.from('ai_messages').insert({
        'conversation_id': conversationId,
        'role': 'assistant',
        'content': replyText,
        'tool_calls_json': {'context_sent': context},
      });

      return Result.ok(replyText);
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }
}

enum ChatRole { user, assistant }

/// Maps to a row in `ai_messages` (schema.sql). Kept minimal — the
/// context packet sent alongside a user message is never itself stored
/// as a message (it's rebuilt fresh from current data each time, per
/// [AiContextBuilder]'s doc comment on staying a single source of
/// truth), only the human-readable conversation is persisted.
class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromSupabaseRow(Map<String, dynamic> row) {
    return ChatMessage(
      id: row['id'] as String,
      role: (row['role'] as String) == 'user' ? ChatRole.user : ChatRole.assistant,
      content: row['content'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

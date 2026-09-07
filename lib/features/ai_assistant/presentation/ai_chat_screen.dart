import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_providers.dart';
import '../data/ai_assistant_providers.dart';
import '../domain/chat_message.dart';

/// Chat UI for the AI Assistant (plan section 11's user-facing surface).
/// Every message is answered using the context packet from
/// [aiContextProvider] — built fresh each send, never held stale across
/// the conversation.
class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  String? _conversationId;
  bool _isSending = false;
  String? _error;

  Future<String?> _ensureConversation() async {
    if (_conversationId != null) return _conversationId;
    final appUser = await ref.read(currentAppUserProvider.future);
    if (appUser == null) return null;

    final repo = ref.read(aiAssistantRepositoryProvider);
    final result = await repo.ensureConversation(appUser.id);
    return result.when(
      ok: (id) {
        _conversationId = id;
        return id;
      },
      err: (failure) {
        setState(() => _error = failure.message);
        return null;
      },
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
      _error = null;
      _messages.add(ChatMessage(
        id: 'local-${_messages.length}',
        role: ChatRole.user,
        content: text,
        createdAt: DateTime.now(),
      ));
    });
    _controller.clear();
    _scrollToBottom();

    final conversationId = await _ensureConversation();
    final context = await ref.read(aiContextProvider.future);

    if (conversationId == null) {
      setState(() {
        _isSending = false;
        _error = 'Could not start a conversation.';
      });
      return;
    }

    final repo = ref.read(aiAssistantRepositoryProvider);
    final result = await repo.sendMessage(
      conversationId: conversationId,
      userMessage: text,
      context: context ?? {},
    );

    if (!mounted) return;
    setState(() {
      _isSending = false;
      result.when(
        ok: (reply) => _messages.add(ChatMessage(
          id: 'local-${_messages.length}',
          role: ChatRole.assistant,
          content: reply,
          createdAt: DateTime.now(),
        )),
        err: (failure) => _error = failure.message,
      );
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ask SquadIQ')),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        _MessageBubble(message: _messages[index]),
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Ask about your squad, captain, transfers…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : _send,
                    icon: _isSending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Text(
          'Ask about your squad, captaincy, or any issues the '
          'Emergency Coach found — answers are grounded in the numbers '
          "already computed for your team, nothing invented.",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(message.content),
      ),
    );
  }
}

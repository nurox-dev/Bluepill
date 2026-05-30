import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;

import '../models/model_helpers.dart';
import '../services/agent_chat_service.dart';
import '../services/agent_gateway_service.dart';
import '../services/ai_service.dart';
import '../services/google_calendar_service.dart';
import '../services/mcp_context_service.dart';
import '../services/supabase_service.dart';
import '../ui/expressive_loading_indicator.dart';
import 'checkin_page.dart';

const _maxAttachments = 4;
const _maxAttachmentBytes = 8 * 1024 * 1024;
const _agentRunPollInterval = Duration(milliseconds: 1500);
const _agentRunTimeout = Duration(seconds: 75);
const _agentWelcomeText =
    'I am Agent. Attach anything useful, ask what you need next, and I will connect it to your stored context.';

const _suggestedPrompts = [
  'What should I focus on today?',
  'How am I doing this week?',
  'What is my next best action?',
  'Make a plan for tomorrow',
  'Prioritize my tasks',
  'What pattern do my check-ins show?',
];

class AgentPage extends StatefulWidget {
  const AgentPage({super.key});

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _mcp = McpContextService();
  final _chatStore = AgentChatService();
  final _gateway = AgentGatewayService();
  final _calendar = GoogleCalendarService();
  final _messages = <_ChatMessage>[];
  final _conversations = <Map<String, dynamic>>[];
  final _attachments = <_AgentInputAttachment>[];
  Object? _activeConversationId;
  String _activeTitle = 'New chat';
  bool _sending = false;
  bool _loadingHistory = true;
  bool _loadingConversation = false;
  bool _calendarInitialized = false;

  @override
  void initState() {
    super.initState();
    _messages.add(_welcomeMessage());
    _loadConversations();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _calendar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSend =
        !_sending &&
        (_controller.text.trim().isNotEmpty || _attachments.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: Text(_activeConversationId == null ? 'Agent' : _activeTitle),
        actions: [
          IconButton(
            tooltip: 'New chat',
            onPressed: _sending ? null : _startNewChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: 'Start check-in',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CheckinPage()),
            ),
            icon: const Icon(Icons.question_answer_outlined),
          ),
          Builder(
            builder: (context) {
              return IconButton(
                tooltip: 'Chat history',
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                icon: const Icon(Icons.history),
              );
            },
          ),
        ],
      ),
      endDrawer: _HistoryDrawer(
        conversations: _conversations,
        activeConversationId: _activeConversationId,
        loading: _loadingHistory,
        onNewChat: _startNewChat,
        onOpenConversation: _openConversation,
        onDeleteConversation: _deleteConversation,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const _AgentStatusBar(),
              SizedBox(
                height: 58,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final prompt in _suggestedPrompts)
                      _PromptChip(text: prompt, onTap: _ask),
                  ],
                ),
              ),
              Expanded(
                child: _messages.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemBuilder: (context, index) {
                          return _ChatBubble(message: _messages[index]);
                        },
                        itemCount: _messages.length,
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_attachments.isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final attachment in _attachments)
                                _AttachmentChip(
                                  attachment: attachment,
                                  onDeleted: () => setState(
                                    () => _attachments.remove(attachment),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _ComposerIconButton(
                            tooltip: 'Attach image',
                            icon: Icons.image_outlined,
                            onPressed: _sending
                                ? null
                                : () => _pickAttachment(_AttachmentKind.image),
                          ),
                          const SizedBox(width: 6),
                          _ComposerIconButton(
                            tooltip: 'Attach voice',
                            icon: Icons.mic_none_outlined,
                            onPressed: _sending
                                ? null
                                : () => _pickAttachment(_AttachmentKind.voice),
                          ),
                          const SizedBox(width: 6),
                          _ComposerIconButton(
                            tooltip: 'Attach file',
                            icon: Icons.attach_file,
                            onPressed: _sending
                                ? null
                                : () => _pickAttachment(_AttachmentKind.file),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              minLines: 1,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                hintText: 'Message Agent...',
                                prefixIcon: Icon(Icons.chat_bubble_outline),
                              ),
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: canSend ? _send : null,
                            child: _sending
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: ExpressiveLoadingIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_loadingConversation)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.62),
                child: const Center(child: ExpressiveLoadingIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  void _ask(String text) {
    _controller.text = text;
    _send();
  }

  _ChatMessage _welcomeMessage() {
    return const _ChatMessage(role: 'assistant', text: _agentWelcomeText);
  }

  Future<void> _loadConversations() async {
    setState(() => _loadingHistory = true);
    try {
      final userId = SupabaseService.currentUserId;
      final conversations = await _chatStore.getConversations(userId);
      if (!mounted) return;
      setState(() {
        _conversations
          ..clear()
          ..addAll(conversations);
        _loadingHistory = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
      _showSnack('Could not load chat history: $error');
    }
  }

  void _startNewChat() {
    setState(() {
      _activeConversationId = null;
      _activeTitle = 'New chat';
      _attachments.clear();
      _messages
        ..clear()
        ..add(_welcomeMessage());
    });
    _scrollToEnd();
  }

  Future<void> _openConversation(Map<String, dynamic> conversation) async {
    final conversationId = conversation['id'];
    if (conversationId == null) return;
    Navigator.of(context).maybePop();
    setState(() => _loadingConversation = true);
    try {
      final userId = SupabaseService.currentUserId;
      final rows = await _chatStore.getMessages(
        userId: userId,
        conversationId: conversationId,
      );
      if (!mounted) return;
      setState(() {
        _activeConversationId = conversationId;
        _activeTitle = conversation['title']?.toString() ?? 'Agent chat';
        _attachments.clear();
        _messages
          ..clear()
          ..addAll(rows.map(_messageFromRow));
        if (_messages.isEmpty) _messages.add(_welcomeMessage());
      });
      _scrollToEnd();
    } catch (error) {
      _showSnack('Could not open chat: $error');
    } finally {
      if (mounted) setState(() => _loadingConversation = false);
    }
  }

  Future<void> _deleteConversation(Map<String, dynamic> conversation) async {
    final conversationId = conversation['id'];
    if (conversationId == null) return;
    try {
      await _chatStore.deleteConversation(conversationId);
      if (_activeConversationId == conversationId) _startNewChat();
      await _loadConversations();
    } catch (error) {
      _showSnack('Could not delete chat: $error');
    }
  }

  Future<void> _pickAttachment(_AttachmentKind kind) async {
    if (_attachments.length >= _maxAttachments) {
      _showSnack('Remove an attachment before adding another.');
      return;
    }

    final remaining = _maxAttachments - _attachments.length;
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: remaining > 1,
        withData: true,
        type: _pickerType(kind),
        allowedExtensions: _allowedExtensions(kind),
      );
      if (result == null || result.files.isEmpty) return;

      final next = <_AgentInputAttachment>[];
      for (final file in result.files.take(remaining)) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          _showSnack('Could not read ${file.name}.');
          continue;
        }
        if (bytes.length > _maxAttachmentBytes) {
          _showSnack('${file.name} is larger than 8 MB.');
          continue;
        }
        final mimeType = _mimeTypeFor(file, kind);
        next.add(
          _AgentInputAttachment(
            name: file.name,
            mimeType: mimeType,
            bytes: bytes,
            textExcerpt: _textExcerpt(file.name, mimeType, bytes),
          ),
        );
      }

      if (next.isEmpty || !mounted) return;
      setState(() => _attachments.addAll(next));
    } catch (error) {
      _showSnack('Could not attach file: $error');
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (_sending || (text.isEmpty && _attachments.isEmpty)) return;

    final promptText = text.isEmpty
        ? 'Review my attachments and connect them to my current goals.'
        : text;
    final visibleText = text.isEmpty ? 'Review these attachments.' : text;
    final messageAttachments = List<_AgentInputAttachment>.from(_attachments);
    final userId = SupabaseService.currentUserId;

    setState(() {
      _sending = true;
      _messages.add(
        _ChatMessage(
          role: 'user',
          text: visibleText,
          createdAt: DateTime.now(),
          attachments: messageAttachments,
        ),
      );
      _controller.clear();
      _attachments.clear();
    });
    _scrollToEnd();

    try {
      if (isCalendarContextRequest(promptText)) {
        await _refreshCalendarContextForChat(userId);
      }

      final response = await _gateway.createAgentRun(
        message: promptText,
        conversationId: _activeConversationId,
        attachments: [
          for (final attachment in messageAttachments) attachment.toMetadata(),
        ],
      );
      final conversationId = response['conversation_id'];
      final runId = response['agent_run_id'];
      if (conversationId == null || runId == null) {
        throw StateError('Agent gateway did not return a run id.');
      }

      if (!mounted) return;
      setState(() {
        _activeConversationId = conversationId;
        if (_activeTitle == 'New chat') {
          _activeTitle = _titleFromMessage(visibleText);
        }
      });
      await _loadConversations();

      final responseStatus = response['status']?.toString();
      final run = _isFinishedRunStatus(responseStatus)
          ? response
          : await _waitForAgentRun(runId);
      if (!mounted) return;
      final status = run['status']?.toString();

      if (status == 'completed') {
        await _syncConversationMessages(
          userId: userId,
          conversationId: conversationId,
          fallbackReply: _replyTextFromRun(run),
        );
        await _loadConversations();
      } else if (status == 'failed' || status == 'cancelled') {
        throw StateError(_agentRunFailureMessage(run));
      } else {
        setState(
          () => _messages.add(
            const _ChatMessage(
              role: 'assistant',
              text:
                  'Agent is still working on this. Reopen this chat from history in a moment to pick up the reply.',
            ),
          ),
        );
        _scrollToEnd();
      }
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _messages.add(
          _ChatMessage(
            role: 'assistant',
            text: 'Agent could not reply: ${_friendlyError(error)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _refreshCalendarContextForChat(String userId) async {
    try {
      if (!_calendarInitialized) {
        await _calendar.initialize(onAuthChanged: (_, __) {}, onError: (_) {});
        _calendarInitialized = true;
      }
      final email = _calendar.accountEmail?.trim();
      if (email == null || email.isEmpty || !_calendar.isAuthorized) return;

      final events = await _calendar.listUpcomingEvents();
      await _mcp.saveGoogleCalendarConnection(
        userId: userId,
        email: email,
        scopes: GoogleCalendarService.calendarScopes,
        upcomingEvents: events
            .map(_calendarEventSummary)
            .take(50)
            .toList(growable: false),
      );
    } catch (_) {
      // Chat can still proceed with the most recent stored calendar snapshot.
    }
  }

  Future<Map<String, dynamic>> _waitForAgentRun(Object runId) async {
    final timeoutAt = DateTime.now().add(_agentRunTimeout);
    var run = await _gateway.getAgentRun(runId);

    while (mounted && DateTime.now().isBefore(timeoutAt)) {
      final status = run['status']?.toString();
      if (_isFinishedRunStatus(status)) {
        return run;
      }

      await Future<void>.delayed(_agentRunPollInterval);
      run = await _gateway.getAgentRun(runId);
    }

    return run;
  }

  bool _isFinishedRunStatus(String? status) {
    return status == 'completed' || status == 'failed' || status == 'cancelled';
  }

  Future<void> _syncConversationMessages({
    required String userId,
    required Object conversationId,
    String? fallbackReply,
  }) async {
    final rows = await _chatStore.getMessages(
      userId: userId,
      conversationId: conversationId,
    );
    if (!mounted) return;

    final messages = rows.map(_messageFromRow).toList();
    final cleanFallback = fallbackReply?.trim();
    final shouldAppendFallback =
        cleanFallback != null &&
        cleanFallback.isNotEmpty &&
        !messages.any(
          (message) =>
              message.role == 'assistant' &&
              message.text.trim() == cleanFallback,
        );

    setState(() {
      _messages
        ..clear()
        ..addAll(messages);
      if (_messages.isEmpty) _messages.add(_welcomeMessage());
      if (shouldAppendFallback) {
        _messages.add(
          _ChatMessage(
            role: 'assistant',
            text: cleanFallback,
            createdAt: DateTime.now(),
          ),
        );
      }
    });
    _scrollToEnd();
  }

  String? _replyTextFromRun(Map<String, dynamic> run) {
    final result = run['result'];
    if (result is Map && result['text'] != null) {
      final text = result['text'].toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  String _agentRunFailureMessage(Map<String, dynamic> run) {
    final status = run['status']?.toString() ?? 'failed';
    final error = run['error']?.toString().trim();
    if (error != null && error.isNotEmpty) {
      return 'Agent run $status: $error';
    }
    return 'Agent run $status before it could reply.';
  }

  String _friendlyError(Object error) {
    Object? details;
    try {
      details = (error as dynamic).details;
    } catch (_) {
      details = null;
    }

    if (details is Map) {
      final message = details['error'] ?? details['message'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
    if (details is String && details.trim().isNotEmpty) return details;

    return error.toString();
  }

  Map<String, dynamic> _calendarEventSummary(calendar.Event event) {
    final start = _calendarEventStart(event);
    final end = _calendarEventEnd(event);
    return {
      'id': event.id,
      'title': event.summary ?? 'Untitled event',
      'start': start?.toIso8601String(),
      'end': end?.toIso8601String(),
      if ((event.location ?? '').trim().isNotEmpty) 'location': event.location,
      if ((event.description ?? '').trim().isNotEmpty)
        'description': event.description,
      if ((event.attendees ?? []).isNotEmpty)
        'attendees': event.attendees
            ?.map((attendee) => attendee.email)
            .whereType<String>()
            .toList(growable: false),
    };
  }

  DateTime? _calendarEventStart(calendar.Event event) {
    return event.start?.dateTime ?? event.start?.date;
  }

  DateTime? _calendarEventEnd(calendar.Event event) {
    return event.end?.dateTime ?? event.end?.date;
  }

  String _titleFromMessage(String text) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return 'Attachment review';
    return collapsed.length <= 42
        ? collapsed
        : '${collapsed.substring(0, 42)}...';
  }

  _ChatMessage _messageFromRow(Map<String, dynamic> row) {
    final attachments = _attachmentsFromStored(row['attachments']);
    return _ChatMessage(
      role: row['role']?.toString() ?? 'assistant',
      text: row['text']?.toString() ?? '',
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      attachments: attachments,
    );
  }

  List<_AgentInputAttachment> _attachmentsFromStored(Object? value) {
    Object? decoded = value;
    if (value is String && value.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(value);
      } catch (_) {
        decoded = null;
      }
    }
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map)
          _AgentInputAttachment.fromMetadata(Map<String, dynamic>.from(item)),
    ];
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AgentStatusBar extends StatelessWidget {
  const _AgentStatusBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          avatar: const Icon(Icons.storage_outlined, size: 18),
          label: const Text('Stored data connected'),
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.text, required this.onTap});

  final String text;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
      child: ActionChip(
        avatar: const Icon(Icons.auto_awesome, size: 18),
        label: Text(text),
        onPressed: () => onTap(text),
      ),
    );
  }
}

class _HistoryDrawer extends StatelessWidget {
  const _HistoryDrawer({
    required this.conversations,
    required this.activeConversationId,
    required this.loading,
    required this.onNewChat,
    required this.onOpenConversation,
    required this.onDeleteConversation,
  });

  final List<Map<String, dynamic>> conversations;
  final Object? activeConversationId;
  final bool loading;
  final VoidCallback onNewChat;
  final ValueChanged<Map<String, dynamic>> onOpenConversation;
  final ValueChanged<Map<String, dynamic>> onDeleteConversation;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.history,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Chat History',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'New chat',
                    onPressed: () {
                      Navigator.of(context).maybePop();
                      onNewChat();
                    },
                    icon: const Icon(Icons.add_comment_outlined),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: loading
                  ? const Center(child: ExpressiveLoadingIndicator())
                  : conversations.isEmpty
                  ? const _EmptyHistory()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: conversations.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];
                        final id = conversation['id'];
                        final title = conversation['title']?.toString();
                        final updatedAt = compactDate(
                          conversation['updated_at'],
                        );
                        return ListTile(
                          selected: id == activeConversationId,
                          leading: const CircleAvatar(
                            child: Icon(Icons.support_agent_outlined),
                          ),
                          title: Text(
                            title == null || title.trim().isEmpty
                                ? 'Agent chat'
                                : title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            updatedAt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: 'Delete chat',
                            onPressed: () => onDeleteConversation(conversation),
                            icon: const Icon(Icons.delete_outline),
                          ),
                          onTap: () => onOpenConversation(conversation),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No chats yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Saved Agent conversations will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = isUser
        ? colorScheme.primaryContainer
        : colorScheme.surface;
    final textColor = isUser
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            color: bubbleColor,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isUser
                        ? Icons.person_outline
                        : Icons.support_agent_outlined,
                    size: 20,
                    color: textColor,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: DefaultTextStyle(
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.copyWith(color: textColor),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(message.text),
                          if (message.createdAt != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              TimeOfDay.fromDateTime(
                                message.createdAt!.toLocal(),
                              ).format(context),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: textColor.withValues(alpha: 0.72),
                                  ),
                            ),
                          ],
                          if (message.attachments.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final attachment in message.attachments)
                                  _AttachmentChip(
                                    attachment: attachment,
                                    dense: true,
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    this.onDeleted,
    this.dense = false,
  });

  final _AgentInputAttachment attachment;
  final VoidCallback? onDeleted;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final label = '${attachment.name} (${_formatBytes(attachment.sizeBytes)})';
    return InputChip(
      avatar: Icon(_iconForMime(attachment.mimeType), size: 18),
      label: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dense ? 180 : 260),
        child: Text(label, overflow: TextOverflow.ellipsis),
      ),
      visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
      onDeleted: onDeleted,
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(onPressed: onPressed, icon: Icon(icon)),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.text,
    this.createdAt,
    this.attachments = const [],
  });

  final String role;
  final String text;
  final DateTime? createdAt;
  final List<_AgentInputAttachment> attachments;
}

class _AgentInputAttachment {
  const _AgentInputAttachment({
    required this.name,
    required this.mimeType,
    required this.bytes,
    this.textExcerpt,
    this.storedSizeBytes,
  });

  factory _AgentInputAttachment.fromMetadata(Map<String, dynamic> metadata) {
    return _AgentInputAttachment(
      name: metadata['name']?.toString() ?? 'Attachment',
      mimeType: metadata['mime_type']?.toString() ?? 'application/octet-stream',
      bytes: Uint8List(0),
      storedSizeBytes: intValue(metadata['size_bytes']),
    );
  }

  final String name;
  final String mimeType;
  final Uint8List bytes;
  final String? textExcerpt;
  final int? storedSizeBytes;

  int get sizeBytes => storedSizeBytes ?? bytes.length;

  Map<String, dynamic> toMetadata() {
    return {'name': name, 'mime_type': mimeType, 'size_bytes': sizeBytes};
  }
}

enum _AttachmentKind { image, voice, file }

FileType _pickerType(_AttachmentKind kind) {
  if (kind == _AttachmentKind.file) return FileType.any;
  return FileType.custom;
}

List<String>? _allowedExtensions(_AttachmentKind kind) {
  return switch (kind) {
    _AttachmentKind.image => ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'],
    _AttachmentKind.voice => [
      'mp3',
      'm4a',
      'wav',
      'aac',
      'ogg',
      'flac',
      'webm',
    ],
    _AttachmentKind.file => null,
  };
}

String _mimeTypeFor(PlatformFile file, _AttachmentKind kind) {
  final extension = (file.extension ?? file.name.split('.').last).toLowerCase();
  const mimeByExtension = {
    'aac': 'audio/aac',
    'csv': 'text/csv',
    'css': 'text/css',
    'dart': 'text/plain',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'flac': 'audio/flac',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'html': 'text/html',
    'jpeg': 'image/jpeg',
    'jpg': 'image/jpeg',
    'js': 'text/javascript',
    'json': 'application/json',
    'log': 'text/plain',
    'm4a': 'audio/mp4',
    'md': 'text/markdown',
    'mp3': 'audio/mpeg',
    'ogg': 'audio/ogg',
    'pdf': 'application/pdf',
    'png': 'image/png',
    'txt': 'text/plain',
    'ts': 'text/plain',
    'wav': 'audio/wav',
    'webm': 'audio/webm',
    'webp': 'image/webp',
    'xml': 'application/xml',
    'yaml': 'text/yaml',
    'yml': 'text/yaml',
  };

  final mapped = mimeByExtension[extension];
  if (mapped != null) return mapped;
  if (kind == _AttachmentKind.image) return 'image/jpeg';
  if (kind == _AttachmentKind.voice) return 'audio/mpeg';
  return 'application/octet-stream';
}

String? _textExcerpt(String name, String mimeType, Uint8List bytes) {
  final lowerName = name.toLowerCase();
  final looksText =
      mimeType.startsWith('text/') ||
      mimeType == 'application/json' ||
      mimeType == 'application/xml' ||
      lowerName.endsWith('.md') ||
      lowerName.endsWith('.log');
  if (!looksText) return null;

  final text = utf8.decode(bytes, allowMalformed: true).trim();
  if (text.isEmpty) return null;
  return text.length <= 5000 ? text : '${text.substring(0, 5000)}\n...';
}

IconData _iconForMime(String mimeType) {
  if (mimeType.startsWith('image/')) return Icons.image_outlined;
  if (mimeType.startsWith('audio/')) return Icons.graphic_eq_outlined;
  if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mimeType.startsWith('text/') || mimeType == 'application/json') {
    return Icons.description_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

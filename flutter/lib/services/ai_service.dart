const progressExtractionSystemPrompt = '''
You are a progress extraction assistant. Your job is to convert the user's natural language check-in answer into structured JSON. Do not give advice. Do not include extra text. Only return valid JSON.

Return this format:
{
  "completed_tasks": [],
  "missed_tasks": [],
  "partial_tasks": [],
  "habits_completed": [],
  "habits_missed": [],
  "study_minutes": null,
  "work_minutes": null,
  "exercise_minutes": null,
  "mood": null,
  "focus_score": null,
  "blockers": [],
  "lesson": null,
  "tomorrow_adjustment": null
}
''';

const agentSystemPrompt = '''
You are a helpful AI Agent inside Project BluePill. Answer the latest user message directly and naturally.

Use the user's stored Project BluePill context only when it is clearly relevant: goals, mission, tasks, habits, calendar, check-ins, progress, planning, motivation, personal patterns, or an explicit request to personalize. For simple factual questions, math, definitions, coding help, general knowledge, or casual chat, answer normally without mentioning the user's mission, profile, progress, weaknesses, or next action.

Do not force personalization. When stored context is relevant, be practical, honest, motivational, and specific. When it is not relevant, be concise and neutral.

Use conversation history for continuity, but answer the latest user message directly. Do not repeat your previous answer unless the user explicitly asks you to repeat it. If the latest message is similar to an earlier one, add a new angle, a sharper next action, or ask one concrete clarifying question.

When the user provides images, audio, or files, use the supplied attachment content and metadata alongside the stored user context. If a file type cannot be inspected by the active model, say what you can and cannot infer instead of pretending to have read it.
''';

const mentorSystemPrompt = '''
You are a personal AI mentor for Project BluePill. For explicit coaching, planning, progress, habit, mission, task, or dashboard requests, use the user's stored data before giving advice. Be practical, honest, motivational, and personalized. Mention the user's mission, recent progress, weakness, and next best action when they are relevant. Keep responses clear, human, and supportive.
''';

bool shouldUsePersonalContextForAgentMessage(
  String message, {
  bool hasAttachments = false,
}) {
  if (isCalendarContextRequest(message)) return true;

  final normalized = message.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.trim().isEmpty) return hasAttachments;

  final personalPatterns = [
    RegExp(r'\bmy\b'),
    RegExp(r'\bme\b'),
    RegExp(r'\bi\b'),
    RegExp(r'\btoday\b'),
    RegExp(r'\btomorrow\b'),
    RegExp(r'\bthis week\b'),
  ];
  final contextPatterns = [
    RegExp(r'\bmission\b'),
    RegExp(r'\b(main|dream) goal\b'),
    RegExp(r'\bgoal(s)?\b'),
    RegExp(r'\btask(s)?\b'),
    RegExp(r'\bto-?do\b'),
    RegExp(r'\bhabit(s)?\b'),
    RegExp(r'\bstreak(s)?\b'),
    RegExp(r'\bcalendar\b'),
    RegExp(r'\bschedule\b'),
    RegExp(r'\bevent(s)?\b'),
    RegExp(r'\bmeeting(s)?\b'),
    RegExp(r'\bappointment(s)?\b'),
    RegExp(r'\bavailability\b'),
    RegExp(r'\bfree\b'),
    RegExp(r'\bbusy\b'),
    RegExp(r'\bcheck-?in(s)?\b'),
    RegExp(r'\bprogress\b'),
    RegExp(r'\blife score\b'),
    RegExp(r'\bfocus\b'),
    RegExp(r'\bblocker(s)?\b'),
    RegExp(r'\bmood\b'),
    RegExp(r'\bweakness\b'),
    RegExp(r'\bmotivat(e|ion|ional)\b'),
    RegExp(r'\bdiscipline\b'),
    RegExp(r'\broutine\b'),
    RegExp(r'\bplan\b'),
    RegExp(r'\bprioriti[sz]e\b'),
    RegExp(r'\bnext action\b'),
    RegExp(r'\bhow am i doing\b'),
    RegExp(r'\bwhat should i\b'),
    RegExp(r'\bbluepill\b'),
  ];

  return contextPatterns.any((pattern) => pattern.hasMatch(normalized)) ||
      (hasAttachments &&
          personalPatterns.any((pattern) => pattern.hasMatch(normalized)));
}

bool isCalendarContextRequest(String message) {
  final normalized = message.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.trim().isEmpty) return false;

  final calendarPatterns = [
    RegExp(r'\bcalendar\b'),
    RegExp(r'\bschedule\b'),
    RegExp(r'\bevent(s)?\b'),
    RegExp(r'\bmeeting(s)?\b'),
    RegExp(r'\bappointment(s)?\b'),
    RegExp(r'\bavailability\b'),
    RegExp(r'\bfree\b'),
    RegExp(r'\bbusy\b'),
    RegExp(r'\bwhat do i have\b'),
    RegExp(r'\bdo i have\b'),
    RegExp(r'\banything (today|tomorrow|this week)\b'),
    RegExp(r'\bwhat.?s on (today|tomorrow|my schedule)\b'),
  ];

  return calendarPatterns.any((pattern) => pattern.hasMatch(normalized));
}

class AiAttachment {
  const AiAttachment({
    required this.name,
    required this.mimeType,
    required this.bytes,
    this.textExcerpt,
  });

  final String name;
  final String mimeType;
  final List<int> bytes;
  final String? textExcerpt;

  bool get isImage => mimeType.startsWith('image/');
  bool get isAudio => mimeType.startsWith('audio/');

  bool get canSendToGeminiInline {
    return isImage || isAudio || mimeType == 'application/pdf';
  }

  Map<String, dynamic> toPromptContext() {
    return {
      'name': name,
      'mime_type': mimeType,
      'size_bytes': bytes.length,
      if (textExcerpt != null && textExcerpt!.trim().isNotEmpty)
        'text_excerpt': textExcerpt,
    };
  }
}

class AiService {
  Future<String> generateDailySuggestion(Map<String, dynamic> userContext) {
    return _mentorText(
      userContext,
      'Give one specific daily suggestion for today.',
      fallback:
          'Complete your top 2 tasks before adding new work. Keep the day narrow and finishable.',
    );
  }

  Future<String> generateMotivation(Map<String, dynamic> userContext) {
    return _mentorText(
      userContext,
      'Give one short motivation message in the user preferred motivation style.',
      fallback:
          'You do not need a perfect day. You need one disciplined action today.',
    );
  }

  Future<String> generateWeaknessAlert(Map<String, dynamic> userContext) {
    return _mentorText(
      userContext,
      'Identify the user most important weakness or risk this week in one sentence.',
      fallback: 'Your sleep and focus scores are low this week.',
    );
  }

  Future<Map<String, dynamic>> extractProgressFromCheckin(
    String userAnswer,
    Map<String, dynamic> userContext,
  ) async {
    final fallback = _emptyExtraction();
    return {...fallback, ..._localExtract(userAnswer)};
  }

  Future<String> generateWeeklyReview(Map<String, dynamic> userContext) {
    return _mentorText(
      userContext,
      'Write a concise weekly review: what worked, what failed, what changes next week.',
      fallback:
          'This week, consistency matters more than intensity. Keep one focus block, one health habit, and one night reflection non-negotiable.',
    );
  }

  Future<List<Map<String, dynamic>>> generateTaskPriorityOrder(
    List<Map<String, dynamic>> tasks,
    Map<String, dynamic> userContext,
  ) async {
    final pending = tasks.where((task) => task['status'] != 'completed');
    return _localTaskOrder(pending.toList());
  }

  Future<String> generateMissionAdvice(Map<String, dynamic> userContext) {
    return _mentorText(
      userContext,
      'Give practical advice on connecting dream mission, goals, and today tasks.',
      fallback:
          'Make the mission visible in today task list: one yearly goal should produce one weekly goal and one concrete task today.',
    );
  }

  Future<List<String>> generateMissionCheckpoints(
    Map<String, dynamic> mission,
    Map<String, dynamic> userContext,
  ) async {
    final title = mission['title']?.toString().trim() ?? '';
    final description = mission['description']?.toString().trim() ?? '';
    final source = title.isEmpty ? description : title;
    final cleanTitle = source.isEmpty ? 'this mission' : source;
    final verbs = _checkpointVerbs(cleanTitle);

    return [
      '${verbs[0]} the clear outcome for $cleanTitle',
      '${verbs[1]} the first repeatable system',
      '${verbs[2]} one visible proof of progress',
      '${verbs[3]} feedback and remove the biggest blocker',
      '${verbs[4]} the next milestone from real results',
    ];
  }

  Future<String> sendMentorMessage(
    String message,
    Map<String, dynamic> userContext,
  ) {
    return sendAgentMessage(message: message, userContext: userContext);
  }

  Future<String> sendAgentMessage({
    required String message,
    required Map<String, dynamic> userContext,
    List<AiAttachment> attachments = const [],
    List<Map<String, String>> chatHistory = const [],
  }) {
    return _agentChat(
      system: agentSystemPrompt,
      message: message,
      userContext: userContext,
      chatHistory: chatHistory,
      attachments: attachments,
      fallback: _agentFallback(
        message: message,
        attachments: attachments,
        usePersonalContext: shouldUsePersonalContextForAgentMessage(
          message,
          hasAttachments: attachments.isNotEmpty,
        ),
      ),
    );
  }

  Future<String> _agentChat({
    required String system,
    required String message,
    required Map<String, dynamic> userContext,
    required List<Map<String, String>> chatHistory,
    required List<AiAttachment> attachments,
    required String fallback,
  }) async {
    final usePersonalContext = shouldUsePersonalContextForAgentMessage(
      message,
      hasAttachments: attachments.isNotEmpty,
    );
    if (usePersonalContext) return fallback;
    return _agentFallback(
      message: message,
      attachments: attachments,
      usePersonalContext: usePersonalContext,
    );
  }

  Future<String> _mentorText(
    Map<String, dynamic> userContext,
    String request, {
    required String fallback,
  }) {
    return Future.value(fallback);
  }

  List<Map<String, dynamic>> _localTaskOrder(List<Map<String, dynamic>> tasks) {
    final ordered = [...tasks];
    const priorityWeight = {'high': 0, 'medium': 1, 'low': 2};
    ordered.sort((a, b) {
      final priority = (priorityWeight[a['priority']] ?? 1).compareTo(
        priorityWeight[b['priority']] ?? 1,
      );
      if (priority != 0) return priority;
      final aDate = DateTime.tryParse(a['due_date']?.toString() ?? '');
      final bDate = DateTime.tryParse(b['due_date']?.toString() ?? '');
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    return ordered;
  }

  Map<String, dynamic> _emptyExtraction() {
    return {
      'completed_tasks': [],
      'missed_tasks': [],
      'partial_tasks': [],
      'habits_completed': [],
      'habits_missed': [],
      'study_minutes': null,
      'work_minutes': null,
      'exercise_minutes': null,
      'mood': null,
      'focus_score': null,
      'blockers': [],
      'lesson': null,
      'tomorrow_adjustment': null,
    };
  }

  Map<String, dynamic> _localExtract(String answer) {
    final lower = answer.toLowerCase();
    final minutesMatch = RegExp(
      r'(\d+)\s*(minute|min|minutes|mins)',
    ).firstMatch(lower);
    final focusMatch = RegExp(r'focus(?:ed)?\D*(10|[1-9])').firstMatch(lower);
    final blockers = <String>[
      if (lower.contains('tired')) 'tired',
      if (lower.contains('stress')) 'stress',
      if (lower.contains('busy')) 'busy',
      if (lower.contains('sleep')) 'sleep',
    ];

    return {
      'study_minutes': lower.contains('stud')
          ? int.tryParse(minutesMatch?.group(1) ?? '')
          : null,
      'work_minutes': lower.contains('work')
          ? int.tryParse(minutesMatch?.group(1) ?? '')
          : null,
      'exercise_minutes':
          lower.contains('gym') ||
              lower.contains('workout') ||
              lower.contains('exercise')
          ? int.tryParse(minutesMatch?.group(1) ?? '')
          : null,
      'mood': lower.contains('tired') || lower.contains('low')
          ? 'low energy'
          : null,
      'focus_score': int.tryParse(focusMatch?.group(1) ?? ''),
      'blockers': blockers,
    };
  }

  String _agentFallback({
    required String message,
    required List<AiAttachment> attachments,
    required bool usePersonalContext,
  }) {
    final collapsed = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    final localAnswer = _localGeneralAnswer(collapsed);
    if (!usePersonalContext && localAnswer != null) return localAnswer;

    final prompt = collapsed.length <= 90
        ? collapsed
        : '${collapsed.substring(0, 90)}...';
    final attachmentNote = attachments.isEmpty
        ? ''
        : ' I can see you attached ${attachments.length} item${attachments.length == 1 ? '' : 's'}, but the AI backend could not inspect attachments right now.';
    if (!usePersonalContext) {
      return 'I could not reach the AI backend for "$prompt".$attachmentNote';
    }
    return 'I could not reach the AI backend for "$prompt". As a local Agent fallback, pick one mission-linked task, shrink it to a 15-minute action, then complete a short check-in so your next answer can use fresher context.$attachmentNote';
  }

  List<String> _checkpointVerbs(String missionTitle) {
    final lower = missionTitle.toLowerCase();
    if (lower.contains('fitness') ||
        lower.contains('health') ||
        lower.contains('body')) {
      return ['Define', 'Build', 'Complete', 'Review', 'Raise'];
    }
    if (lower.contains('business') ||
        lower.contains('startup') ||
        lower.contains('company')) {
      return ['Define', 'Validate', 'Ship', 'Collect', 'Scale'];
    }
    if (lower.contains('learn') ||
        lower.contains('study') ||
        lower.contains('skill')) {
      return ['Define', 'Practice', 'Publish', 'Review', 'Advance'];
    }
    return ['Define', 'Build', 'Finish', 'Review', 'Set'];
  }

  String? _localGeneralAnswer(String message) {
    final addition = RegExp(
      r'^\s*(?:what\s+is\s+)?(-?\d+)\s*\+\s*(-?\d+)\??\s*$',
    ).firstMatch(message.toLowerCase());
    if (addition != null) {
      final left = int.tryParse(addition.group(1)!);
      final right = int.tryParse(addition.group(2)!);
      if (left != null && right != null) return '${left + right}';
    }
    return null;
  }
}

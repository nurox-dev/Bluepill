import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/model_helpers.dart';
import 'google_api_auth_service.dart';
import 'progress_engine.dart';
import 'supabase_service.dart';

class McpContextService {
  McpContextService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> getUserContext(String userId) async {
    final profile = await _client
        .from('users_profile')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    final data = <String, dynamic>{
      'profile': maybeRow(profile),
      'today_tasks': await getTodayTasks(userId),
      'goals': await getUserGoals(userId),
      'habits': await getUserHabits(userId),
      'recent_progress': await getRecentProgress(userId),
      'recent_checkins': await getRecentCheckins(userId),
      'ai_checkin_streak': await getAiCheckinStreak(userId),
      'recent_feedback': await getRecentFeedback(userId),
      'connected_accounts': await getConnectedAccounts(userId),
      'google_calendar': await getGoogleCalendarContext(userId),
    };

    return data;
  }

  Future<List<Map<String, dynamic>>> getTodayTasks(String userId) async {
    final today = dateKey(DateTime.now());
    final data = await _client
        .from('tasks')
        .select()
        .eq('user_id', userId)
        .or('due_date.eq.$today,due_date.is.null')
        .order('due_date', ascending: true)
        .order('priority', ascending: true)
        .order('created_at', ascending: true);
    return rows(data);
  }

  Future<List<Map<String, dynamic>>> getAllTasks(String userId) async {
    final data = await _client
        .from('tasks')
        .select()
        .eq('user_id', userId)
        .order('due_date', ascending: true)
        .order('created_at', ascending: false);
    return rows(data);
  }

  Future<List<Map<String, dynamic>>> getUserGoals(String userId) async {
    final data = await _client
        .from('goals')
        .select()
        .eq('user_id', userId)
        .order('goal_type', ascending: true)
        .order('created_at', ascending: true);
    return rows(data);
  }

  Future<List<Map<String, dynamic>>> getUserHabits(String userId) async {
    final data = await _client
        .from('habits')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: true);
    return rows(data);
  }

  Future<List<Map<String, dynamic>>> getTodayHabitLogs(String userId) async {
    final data = await _client
        .from('habit_logs')
        .select()
        .eq('user_id', userId)
        .eq('date', dateKey(DateTime.now()));
    return rows(data);
  }

  Future<List<Map<String, dynamic>>> getRecentProgress(
    String userId, {
    int limit = 14,
  }) async {
    final data = await _client
        .from('progress_logs')
        .select()
        .eq('user_id', userId)
        .order('date', ascending: false)
        .limit(limit);
    final list = rows(data);
    return list.reversed.toList();
  }

  Future<List<Map<String, dynamic>>> getRecentCheckins(
    String userId, {
    int limit = 12,
  }) async {
    final data = await _client
        .from('checkins')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows(data);
  }

  Future<Map<String, dynamic>?> getAiCheckinStreak(String userId) async {
    final data = await _client
        .from('ai_checkin_streaks')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return maybeRow(data);
  }

  Future<Map<String, dynamic>> recordAiCheckinStreak(
    String userId, {
    DateTime? checkinDate,
  }) async {
    final previous = await getAiCheckinStreak(userId);
    final streak = ProgressEngine.buildAiCheckinStreakUpdate(
      previous: previous,
      checkinDate: checkinDate ?? DateTime.now(),
    );

    await _client.from('ai_checkin_streaks').upsert({
      ...streak,
      'user_id': userId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');

    return {...?previous, ...streak, 'user_id': userId};
  }

  Future<List<Map<String, dynamic>>> getRecentFeedback(
    String userId, {
    int limit = 8,
  }) async {
    final data = await _client
        .from('ai_feedback')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit * 4);
    return rows(data)
        .where(
          (item) =>
              item['related_data'] is! Map ||
              (item['related_data'] as Map)['source'] != 'agent_chat',
        )
        .take(limit)
        .toList();
  }

  Future<List<Map<String, dynamic>>> getConnectedAccounts(String userId) async {
    final data = await _client
        .from('connected_accounts')
        .select(
          'provider, account_label, account_email, scopes, status, '
          'expires_at, metadata, updated_at',
        )
        .eq('user_id', userId)
        .order('updated_at', ascending: false);
    return rows(data);
  }

  Future<Map<String, dynamic>> getGoogleCalendarContext(String userId) async {
    final account = maybeRow(
      await _client
          .from('connected_accounts')
          .select('account_email, scopes, status, metadata, updated_at')
          .eq('user_id', userId)
          .eq('provider', 'google')
          .eq('status', 'connected')
          .contains('scopes', [
            'https://www.googleapis.com/auth/calendar.events',
          ])
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle(),
    );

    if (account == null) {
      return {'connected': false, 'events': <Map<String, dynamic>>[]};
    }

    final metadata = account['metadata'];
    final events = metadata is Map ? metadata['upcoming_events'] : null;
    return {
      'connected': true,
      'account_email': account['account_email'],
      'scopes': account['scopes'],
      'synced_at': metadata is Map ? metadata['synced_at'] : null,
      'events': events is List ? events : <Map<String, dynamic>>[],
    };
  }

  Future<void> saveGoogleCalendarConnection({
    required String userId,
    required String email,
    required List<String> scopes,
    required List<Map<String, dynamic>> upcomingEvents,
  }) async {
    await _client.from('connected_accounts').upsert({
      'user_id': userId,
      'provider': 'google',
      'account_label': 'Google Calendar',
      'account_email': email,
      'scopes': {...scopes, ...GoogleApiAuthService.googleApiScopes}.toList(),
      'status': 'connected',
      'metadata': {
        'source': 'flutter_google_sign_in',
        'calendar_authorized': true,
        'tasks_authorized': true,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
        'upcoming_events': upcomingEvents.take(20).toList(growable: false),
        'note':
            'OAuth tokens stay in the browser; this is a safe event summary for Agent context.',
      },
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,provider,account_email');
  }

  Future<void> markGoogleCalendarDisconnected({
    required String userId,
    String? email,
  }) async {
    var query = _client
        .from('connected_accounts')
        .update({
          'status': 'revoked',
          'metadata': {
            'calendar_authorized': false,
            'revoked_at': DateTime.now().toUtc().toIso8601String(),
          },
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', userId)
        .eq('provider', 'google');

    if (email != null && email.trim().isNotEmpty) {
      query = query.eq('account_email', email);
    }

    await query;
  }

  Future<void> saveProgressLog(String userId, Map<String, dynamic> data) async {
    await _client.from('progress_logs').upsert({
      ...data,
      'user_id': userId,
      'date': data['date'] ?? dateKey(DateTime.now()),
    }, onConflict: 'user_id,date');
  }

  Future<void> saveAIFeedback(
    String userId,
    Map<String, dynamic> feedback,
  ) async {
    await _client.from('ai_feedback').insert({...feedback, 'user_id': userId});
  }

  Future<Map<String, dynamic>> updateDashboardData(String userId) async {
    final context = await getUserContext(userId);
    final todayTasks = context['today_tasks'] as List<Map<String, dynamic>>;
    final habits = context['habits'] as List<Map<String, dynamic>>;
    final progress = context['recent_progress'] as List<Map<String, dynamic>>;
    final checkins = context['recent_checkins'] as List<Map<String, dynamic>>;
    final aiCheckinStreak =
        context['ai_checkin_streak'] as Map<String, dynamic>?;
    final todayLogs = await getTodayHabitLogs(userId);

    final dailyLog = ProgressEngine.buildDailyProgressLog(
      userId: userId,
      todayTasks: todayTasks,
      todayHabitLogs: todayLogs,
      todayCheckins: checkins.where((item) {
        final created = DateTime.tryParse(item['created_at'].toString());
        return created != null && dateKey(created) == dateKey(DateTime.now());
      }).toList(),
    );

    final existingToday = maybeRow(
      await _client
          .from('progress_logs')
          .select()
          .eq('user_id', userId)
          .eq('date', dateKey(DateTime.now()))
          .maybeSingle(),
    );
    if (existingToday != null) {
      dailyLog['focus_score'] ??= existingToday['focus_score'];
      dailyLog['mood'] ??= existingToday['mood'];
      dailyLog['blocker'] ??= existingToday['blocker'];
      dailyLog['ai_summary'] ??= existingToday['ai_summary'];
      dailyLog['life_score'] = ProgressEngine.calculateLifeScore(
        tasksCompleted: intValue(dailyLog['tasks_completed']),
        tasksMissed: intValue(dailyLog['tasks_missed']),
        habitsCompleted: intValue(dailyLog['habits_completed']),
        habitsMissed: intValue(dailyLog['habits_missed']),
        focusScore: dailyLog['focus_score'] == null
            ? null
            : intValue(dailyLog['focus_score']),
        reflectionCompleted:
            dailyLog['ai_summary'] != null ||
            checkins.any((item) {
              final created = DateTime.tryParse(item['created_at'].toString());
              return created != null &&
                  dateKey(created) == dateKey(DateTime.now());
            }),
      );
    }

    await saveProgressLog(userId, dailyLog);
    context['recent_progress'] = await getRecentProgress(userId);

    return {
      ...context,
      'today_habit_logs': todayLogs,
      'computed_progress': dailyLog,
      'ai_checkin_streak': aiCheckinStreak,
      'life_score': dailyLog['life_score'],
      'today_focus': _todayFocus(todayTasks, context),
      'ai_suggestion': _localSuggestion(todayTasks, habits, progress),
      'weakness_alert': _weaknessAlert(progress, todayLogs),
      'motivation': _motivation(context),
    };
  }

  String _todayFocus(
    List<Map<String, dynamic>> tasks,
    Map<String, dynamic> context,
  ) {
    final profile = context['profile'] as Map<String, dynamic>?;
    final pending = tasks.where((task) => task['status'] == 'pending').toList();
    if (pending.isEmpty) {
      return 'Protect your mission today with one recovery action and one reflection.';
    }
    final top = pending.take(2).map((task) => task['title']).join(' and ');
    final mission = profile?['dream_goal'];
    if (mission == null || mission.toString().trim().isEmpty) {
      return 'Complete your top 2 tasks before adding new work: $top.';
    }
    return 'Complete $top before adding new work. This keeps momentum tied to "$mission".';
  }

  String _localSuggestion(
    List<Map<String, dynamic>> tasks,
    List<Map<String, dynamic>> habits,
    List<Map<String, dynamic>> progress,
  ) {
    final missedTasks = tasks.where((task) => task['status'] == 'missed');
    final weakHabits = habits.where(
      (habit) => doubleValue(habit['completion_rate']) < 60,
    );
    if (missedTasks.isNotEmpty) {
      return 'Move one missed task into a smaller version today instead of trying to recover everything.';
    }
    if (weakHabits.isNotEmpty) {
      return 'Your weakest habit is "${weakHabits.first['title']}". Do a short version today to rebuild consistency.';
    }
    if (progress.isEmpty) {
      return 'Start with one check-in today. BluePill gets sharper once it has your real patterns.';
    }
    return 'Complete your top 2 tasks before adding new work.';
  }

  String _weaknessAlert(
    List<Map<String, dynamic>> progress,
    List<Map<String, dynamic>> todayLogs,
  ) {
    final recent = progress.take(7).toList();
    final lowFocus = recent.where((log) => intValue(log['focus_score']) < 6);
    final missedHabits = todayLogs
        .where((log) => log['status'] == 'missed')
        .length;
    if (lowFocus.length >= 3) {
      return 'Your focus scores are low this week. Reduce today to the highest-impact task.';
    }
    if (missedHabits > 0) {
      return 'You have missed habits today. Restart with the shortest possible completion.';
    }
    return 'No major weakness detected yet. Keep feeding the dashboard honest check-ins.';
  }

  String _motivation(Map<String, dynamic> context) {
    final profile = context['profile'] as Map<String, dynamic>?;
    final style = profile?['motivation_style'] ?? 'friendly';
    if (style == 'strict' || style == 'military discipline') {
      return 'You do not need a perfect day. You need one disciplined action today.';
    }
    if (style == 'soft') {
      return 'A small honest step counts. Keep the promise light enough to complete.';
    }
    if (style == 'business mentor') {
      return 'Treat today like a portfolio: invest energy where the return compounds.';
    }
    return 'You do not need a perfect day. You need one action that proves you are still in the game.';
  }
}

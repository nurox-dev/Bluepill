import '../models/model_helpers.dart';

class ProgressEngine {
  static Map<String, dynamic> buildAiCheckinStreakUpdate({
    required Map<String, dynamic>? previous,
    required DateTime checkinDate,
  }) {
    final checkinDay = DateTime(
      checkinDate.year,
      checkinDate.month,
      checkinDate.day,
    );
    final checkinKey = dateKey(checkinDay);
    final lastCheckinDay = _parseDateOnly(previous?['last_checkin_date']);
    final current = intValue(previous?['current_streak']);
    final best = intValue(previous?['best_streak']);

    late final int nextCurrent;
    if (lastCheckinDay == null) {
      nextCurrent = 1;
    } else if (dateKey(lastCheckinDay) == checkinKey) {
      nextCurrent = current <= 0 ? 1 : current;
    } else if (checkinDay.difference(lastCheckinDay).inDays == 1) {
      nextCurrent = current + 1;
    } else {
      nextCurrent = 1;
    }

    final nextBest = best > nextCurrent ? best : nextCurrent;
    return {
      'current_streak': nextCurrent,
      'best_streak': nextBest,
      'last_checkin_date': checkinKey,
    };
  }

  static int calculateLifeScore({
    required int tasksCompleted,
    required int tasksMissed,
    required int habitsCompleted,
    required int habitsMissed,
    required int? focusScore,
    required bool reflectionCompleted,
  }) {
    final totalTasks = tasksCompleted + tasksMissed;
    final totalHabits = habitsCompleted + habitsMissed;

    final taskPoints =
        totalTasks == 0 ? 0 : (tasksCompleted / totalTasks * 40).round();
    final habitPoints =
        totalHabits == 0 ? 0 : (habitsCompleted / totalHabits * 30).round();
    final normalizedFocus = focusScore?.clamp(0, 10).toInt();
    final focusPoints =
        normalizedFocus == null ? 0 : ((normalizedFocus / 10) * 20).round();
    final reflectionPoints = reflectionCompleted ? 10 : 0;

    return (taskPoints + habitPoints + focusPoints + reflectionPoints)
        .clamp(0, 100)
        .toInt();
  }

  static Map<String, dynamic> buildDailyProgressLog({
    required String userId,
    required List<Map<String, dynamic>> todayTasks,
    required List<Map<String, dynamic>> todayHabitLogs,
    required List<Map<String, dynamic>> todayCheckins,
    Map<String, dynamic>? extracted,
  }) {
    final completedTasks =
        todayTasks.where((task) => task['status'] == 'completed').length;
    final missedTasks =
        todayTasks.where((task) => task['status'] == 'missed').length;
    final completedHabits =
        todayHabitLogs.where((log) => log['status'] == 'completed').length;
    final missedHabits =
        todayHabitLogs.where((log) => log['status'] == 'missed').length;

    final extractedCompletedTasks =
        (extracted?['completed_tasks'] as List?)?.length ?? 0;
    final extractedMissedTasks =
        (extracted?['missed_tasks'] as List?)?.length ?? 0;
    final extractedCompletedHabits =
        (extracted?['habits_completed'] as List?)?.length ?? 0;
    final extractedMissedHabits =
        (extracted?['habits_missed'] as List?)?.length ?? 0;

    final focusScore = intValue(extracted?['focus_score'], -1);
    final normalizedFocus =
        focusScore < 0 ? null : focusScore.clamp(0, 10).toInt();
    final reflectionCompleted = todayCheckins.isNotEmpty || extracted != null;
    final blockerList = extracted?['blockers'];

    final data = <String, dynamic>{
      'user_id': userId,
      'date': dateKey(DateTime.now()),
      'tasks_completed': completedTasks + extractedCompletedTasks,
      'tasks_missed': missedTasks + extractedMissedTasks,
      'habits_completed': completedHabits + extractedCompletedHabits,
      'habits_missed': missedHabits + extractedMissedHabits,
      'focus_score': normalizedFocus,
      'mood': extracted?['mood'],
      'blocker': blockerList is List ? blockerList.join(', ') : null,
      'ai_summary': _summaryFromExtracted(extracted),
    };

    data['life_score'] = calculateLifeScore(
      tasksCompleted: data['tasks_completed'] as int,
      tasksMissed: data['tasks_missed'] as int,
      habitsCompleted: data['habits_completed'] as int,
      habitsMissed: data['habits_missed'] as int,
      focusScore: normalizedFocus,
      reflectionCompleted: reflectionCompleted,
    );

    return data;
  }

  static DateTime? _parseDateOnly(Object? value) {
    final text = value?.toString();
    if (text == null || text.trim().isEmpty) return null;
    final parts = text.split('-');
    if (parts.length >= 3) {
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2].split('T').first);
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String? _summaryFromExtracted(Map<String, dynamic>? extracted) {
    if (extracted == null) return null;
    final mood = extracted['mood'];
    final lesson = extracted['lesson'];
    final adjustment = extracted['tomorrow_adjustment'];
    final parts = [
      if (mood != null) 'Mood: $mood',
      if (lesson != null) 'Lesson: $lesson',
      if (adjustment != null) 'Tomorrow: $adjustment',
    ];
    return parts.isEmpty ? null : parts.join('. ');
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:project_bluepill/services/progress_engine.dart';

void main() {
  test('calculates life score from weighted components', () {
    final score = ProgressEngine.calculateLifeScore(
      tasksCompleted: 3,
      tasksMissed: 1,
      habitsCompleted: 3,
      habitsMissed: 2,
      focusScore: 7,
      reflectionCompleted: true,
    );

    expect(score, 72);
  });

  test('matches documented life score example', () {
    final score = ProgressEngine.calculateLifeScore(
      tasksCompleted: 75,
      tasksMissed: 25,
      habitsCompleted: 60,
      habitsMissed: 40,
      focusScore: 7,
      reflectionCompleted: true,
    );

    expect(score, 72);
  });

  test('starts daily AI check-in streak on first check-in', () {
    final streak = ProgressEngine.buildAiCheckinStreakUpdate(
      previous: null,
      checkinDate: DateTime(2026, 5, 12, 20),
    );

    expect(streak['current_streak'], 1);
    expect(streak['best_streak'], 1);
    expect(streak['last_checkin_date'], '2026-05-12');
  });

  test('increments daily AI check-in streak on consecutive day', () {
    final streak = ProgressEngine.buildAiCheckinStreakUpdate(
      previous: {
        'current_streak': 3,
        'best_streak': 5,
        'last_checkin_date': '2026-05-11',
      },
      checkinDate: DateTime(2026, 5, 12, 8),
    );

    expect(streak['current_streak'], 4);
    expect(streak['best_streak'], 5);
    expect(streak['last_checkin_date'], '2026-05-12');
  });

  test('does not double count multiple daily AI check-ins on same day', () {
    final streak = ProgressEngine.buildAiCheckinStreakUpdate(
      previous: {
        'current_streak': 4,
        'best_streak': 4,
        'last_checkin_date': '2026-05-12',
      },
      checkinDate: DateTime(2026, 5, 12, 22),
    );

    expect(streak['current_streak'], 4);
    expect(streak['best_streak'], 4);
    expect(streak['last_checkin_date'], '2026-05-12');
  });

  test('resets daily AI check-in streak after a missed day', () {
    final streak = ProgressEngine.buildAiCheckinStreakUpdate(
      previous: {
        'current_streak': 4,
        'best_streak': 7,
        'last_checkin_date': '2026-05-10',
      },
      checkinDate: DateTime(2026, 5, 12, 8),
    );

    expect(streak['current_streak'], 1);
    expect(streak['best_streak'], 7);
    expect(streak['last_checkin_date'], '2026-05-12');
  });
}

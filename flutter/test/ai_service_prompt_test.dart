import 'package:flutter_test/flutter_test.dart';
import 'package:project_bluepill/services/ai_service.dart';

void main() {
  test('general agent questions do not request personal context', () {
    expect(shouldUsePersonalContextForAgentMessage('2+2'), isFalse);
    expect(
      shouldUsePersonalContextForAgentMessage('What is the capital of France?'),
      isFalse,
    );
    expect(
      shouldUsePersonalContextForAgentMessage(
        'What is in this image?',
        hasAttachments: true,
      ),
      isFalse,
    );
  });

  test('personal planning questions request Project BluePill context', () {
    expect(
      shouldUsePersonalContextForAgentMessage(
        'What should I focus on today?',
      ),
      isTrue,
    );
    expect(
      shouldUsePersonalContextForAgentMessage('Prioritize my tasks'),
      isTrue,
    );
    expect(
      shouldUsePersonalContextForAgentMessage(
        'What do I have tomorrow?',
      ),
      isTrue,
    );
    expect(
      shouldUsePersonalContextForAgentMessage(
        'Review my attachments and connect them to my goals.',
        hasAttachments: true,
      ),
      isTrue,
    );
  });

  test('agent prompt does not force mission mentions', () {
    expect(agentSystemPrompt.toLowerCase(), isNot(contains('always mention')));
    expect(agentSystemPrompt, contains('Do not force personalization'));
  });

  test('calendar requests are detected beyond the word calendar', () {
    expect(isCalendarContextRequest('check my events'), isTrue);
    expect(isCalendarContextRequest('any meetings today?'), isTrue);
    expect(isCalendarContextRequest('am I free tomorrow afternoon?'), isTrue);
    expect(isCalendarContextRequest('2+2'), isFalse);
  });
}

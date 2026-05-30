import 'package:flutter/widgets.dart';

import 'google_calendar_sign_in_button_stub.dart'
    if (dart.library.js_interop) 'google_calendar_sign_in_button_web.dart';

Widget googleCalendarSignInButton({
  required VoidCallback onPressed,
  String label = 'Connect Google Calendar',
}) {
  return platformGoogleCalendarSignInButton(
    onPressed: onPressed,
    label: label,
  );
}

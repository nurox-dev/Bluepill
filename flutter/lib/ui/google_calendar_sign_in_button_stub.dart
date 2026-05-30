import 'package:flutter/material.dart';

Widget platformGoogleCalendarSignInButton({
  required VoidCallback onPressed,
  required String label,
}) {
  return FilledButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.event_available_outlined),
    label: Text(label),
  );
}

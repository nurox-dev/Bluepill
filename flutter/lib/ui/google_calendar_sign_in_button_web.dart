import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as google_web;

Widget platformGoogleCalendarSignInButton({
  required VoidCallback onPressed,
  required String label,
}) {
  return _GoogleSignInButtonWrapper(
    onPressed: onPressed,
    child: google_web.renderButton(
      configuration: google_web.GSIButtonConfiguration(
        size: google_web.GSIButtonSize.large,
        text: google_web.GSIButtonText.continueWith,
        theme: google_web.GSIButtonTheme.filledBlue,
        type: google_web.GSIButtonType.standard,
        minimumWidth: 260,
      ),
    ),
  );
}

class _GoogleSignInButtonWrapper extends StatefulWidget {
  const _GoogleSignInButtonWrapper({
    required this.onPressed,
    required this.child,
  });

  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_GoogleSignInButtonWrapper> createState() =>
      _GoogleSignInButtonWrapperState();
}

class _GoogleSignInButtonWrapperState extends State<_GoogleSignInButtonWrapper> {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

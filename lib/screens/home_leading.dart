import 'package:flutter/material.dart';

import 'home_shell.dart';

/// Back control for a tool opened from Home.
///
/// A route that can pop keeps the normal back button. Home itself shows
/// nothing here, because the list is already on screen.
Widget? homeBackLeading(BuildContext context) {
  if (ModalRoute.of(context)?.canPop ?? false) return null;
  final shell = homeShellKey.currentState;
  if (shell == null || !shell.toolIsOpen) return null;
  return IconButton(
    tooltip: 'Home',
    icon: const Icon(Icons.arrow_back),
    onPressed: shell.closeTool,
  );
}

import 'package:flutter/material.dart';

class AiUsageSecondaryScaffold extends StatelessWidget {
  const AiUsageSecondaryScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.onBack,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: onBack == null ? null : BackButton(onPressed: onBack),
      title: Text(title),
      actions: actions,
    ),
    body: SafeArea(child: child),
  );
}

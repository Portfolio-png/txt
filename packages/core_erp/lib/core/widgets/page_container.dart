import 'package:flutter/material.dart';

class PageContainer extends StatelessWidget {
  const PageContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(0, 10, 20, 16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      padding: padding,
      child: child,
    );
  }
}

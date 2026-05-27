import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/soft_erp_theme.dart';
import 'soft_primitives.dart';

Future<T?> showErpFormDialog<T>(
  BuildContext context, {
  required Widget child,
  double maxWidth = 840,
  double maxHeight = 760,
  double mobileBreakpoint = 900,
  EdgeInsets desktopInsetPadding = const EdgeInsets.all(24),
}) {
  final isNarrow = MediaQuery.of(context).size.width < mobileBreakpoint;
  if (isNarrow) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: child,
      ),
    );
  }

  return showDialog<T>(
    context: context,
    builder: (context) {
      final size = MediaQuery.of(context).size;
      return Dialog(
        insetPadding: desktopInsetPadding,
        backgroundColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        child: SizedBox(
          width: math.min(
            maxWidth,
            size.width - desktopInsetPadding.horizontal,
          ),
          height: math.min(
            maxHeight,
            size.height - desktopInsetPadding.vertical,
          ),
          child: child,
        ),
      );
    },
  );
}

class ErpFormScaffold extends StatelessWidget {
  const ErpFormScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.footer,
    this.onClose,
    this.errorBanner,
    this.eyebrow,
    this.leading,
    this.headerActions,
    this.bodyPadding = const EdgeInsets.fromLTRB(24, 22, 24, 22),
    this.bodyScrollable = true,
    this.borderRadius = 18,
  });

  final String title;
  final String subtitle;
  final Widget body;
  final Widget footer;
  final VoidCallback? onClose;
  final Widget? errorBanner;
  final Widget? eyebrow;
  final Widget? leading;
  final Widget? headerActions;
  final EdgeInsets bodyPadding;
  final bool bodyScrollable;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 20, 18, 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFBFBFB),
                border: const Border(
                  bottom: BorderSide(color: SoftErpTheme.border),
                ),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(borderRadius),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 14)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null) ...[
                          eyebrow!,
                          const SizedBox(height: 10),
                        ],
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: SoftErpTheme.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: SoftErpTheme.textSecondary,
                                height: 1.45,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (headerActions != null) ...[
                    const SizedBox(width: 12),
                    headerActions!,
                  ],
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Close',
                    onPressed:
                        onClose ?? () => Navigator.of(context).maybePop(),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF8FAFC),
                      foregroundColor: const Color(0xFF334155),
                      side: const BorderSide(color: Color(0xFFD9E2F2)),
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (errorBanner != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: errorBanner,
              ),
            Expanded(
              child: bodyScrollable
                  ? SingleChildScrollView(padding: bodyPadding, child: body)
                  : Padding(padding: bodyPadding, child: body),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
              decoration: const BoxDecoration(
                color: Color(0xFFFBFBFB),
                border: Border(top: BorderSide(color: SoftErpTheme.border)),
              ),
              child: footer,
            ),
          ],
        ),
      ),
    );
  }
}

class ErpDialogSectionCard extends StatelessWidget {
  const ErpDialogSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SoftSectionCard(
      title: title,
      subtitle: subtitle,
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

class ErpFormMessageBanner extends StatelessWidget {
  const ErpFormMessageBanner({
    super.key,
    required this.message,
    this.isError = true,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? const Color(0xFFB91C1C) : const Color(0xFF047857),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

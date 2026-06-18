import 'package:flutter/material.dart';
import 'package:core_erp/core/widgets/app_toast.dart';

// Backwards-compatible shim: the toast now lives in core_erp as showAppToast.
// Production code keeps using showFloorToast / FloorToastKind unchanged.
enum FloorToastKind { info, warning, error }

void showFloorToast(
  BuildContext context,
  String message, {
  FloorToastKind kind = FloorToastKind.warning,
  Duration duration = const Duration(seconds: 4),
}) {
  showAppToast(
    context,
    message,
    kind: switch (kind) {
      FloorToastKind.info => AppToastKind.info,
      FloorToastKind.warning => AppToastKind.warning,
      FloorToastKind.error => AppToastKind.error,
    },
    duration: duration,
  );
}

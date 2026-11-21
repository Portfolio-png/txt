import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Where photos come from: the live camera on a phone, a stand-in in tests.
///
/// A seam rather than the camera plugin used directly, because the plugin
/// needs a real device: without it the capture screen could only be checked
/// by hand.
abstract class CaptureSource {
  /// Readies the camera. Answers why not, or null when it is ready.
  Future<String?> open();

  /// The live view, filling what it is given.
  Widget preview(BuildContext context);

  /// One photo, or null when none was taken.
  Future<XFile?> take();

  /// How far the camera zooms, or null when it cannot. 1.0 is no zoom.
  Future<({double min, double max})?> zoomRange();

  /// Zooms to [level], inside [zoomRange].
  Future<void> setZoom(double level);

  Future<void> close();
}

/// The phone's back camera, through the `camera` plugin.
class CameraCaptureSource implements CaptureSource {
  CameraController? _controller;

  @override
  Future<String?> open() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return 'This phone has no camera the app can use.';
      final back = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        // A photo, not a video: no microphone permission to ask for.
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      _controller = controller;
      return null;
    } on CameraException catch (error) {
      return error.code == 'CameraAccessDenied'
          ? 'Camera access is off for this app. Turn it on in the phone\'s Settings.'
          : (error.description ?? 'The camera could not start.');
    }
  }

  @override
  Widget preview(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    // Cover the screen like the system camera does, cropping rather than
    // letterboxing.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.height ?? 1,
          height: controller.value.previewSize?.width ?? 1,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  @override
  Future<XFile?> take() async {
    final controller = _controller;
    if (controller == null || controller.value.isTakingPicture) return null;
    return controller.takePicture();
  }

  @override
  Future<({double min, double max})?> zoomRange() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    try {
      final min = await controller.getMinZoomLevel();
      final max = await controller.getMaxZoomLevel();
      return max > min ? (min: min, max: max) : null;
    } on CameraException {
      return null;
    }
  }

  @override
  Future<void> setZoom(double level) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setZoomLevel(level);
    } on CameraException {
      // A zoom the lens refused leaves it where it was.
    }
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

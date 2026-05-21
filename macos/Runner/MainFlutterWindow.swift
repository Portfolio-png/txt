import Cocoa
import FlutterMacOS
import PDFKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let windowControlChannel = FlutterMethodChannel(
      name: "paper/window_control",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowControlChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "WINDOW_UNAVAILABLE", message: "Window is unavailable.", details: nil))
        return
      }
      if call.method == "setFullscreen" {
        guard let args = call.arguments as? [String: Any],
              let enabled = args["enabled"] as? Bool else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "enabled is required.", details: nil))
          return
        }
        let isFullscreen = self.styleMask.contains(.fullScreen)
        if enabled != isFullscreen {
          self.toggleFullScreen(nil)
        }
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let nativePrintingChannel = FlutterMethodChannel(
      name: "paper/native_printing",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    nativePrintingChannel.setMethodCallHandler { [weak self] call, result in
      guard self != nil else {
        result(FlutterError(code: "WINDOW_UNAVAILABLE", message: "Print window is unavailable.", details: nil))
        return
      }
      guard call.method == "printPdfFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let filePath = args["filePath"] as? String,
        !filePath.isEmpty
      else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "filePath is required.", details: nil))
        return
      }

      let url = URL(fileURLWithPath: filePath)
      guard let document = PDFDocument(url: url) else {
        result(FlutterError(code: "PDF_OPEN_FAILED", message: "Could not open the generated PDF.", details: nil))
        return
      }

      guard let operation = document.printOperation(
        for: NSPrintInfo.shared,
        scalingMode: .pageScaleToFit,
        autoRotate: true
      ) else {
        result(FlutterError(code: "PRINT_OPERATION_FAILED", message: "Could not prepare the macOS print dialog.", details: nil))
        return
      }

      operation.showsPrintPanel = true
      operation.showsProgressPanel = true
      DispatchQueue.main.async {
        let accepted = operation.run()
        result(accepted)
      }
    }

    super.awakeFromNib()
  }
}

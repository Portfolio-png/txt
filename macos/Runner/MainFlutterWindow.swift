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
    let nativePrintingChannel = FlutterMethodChannel(
      name: "paper/native_printing",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    nativePrintingChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
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

      let pdfView = PDFView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
      pdfView.autoScales = true
      pdfView.document = document
      guard let operation = pdfView.printOperation(
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
        let accepted = operation.runModal(for: self, delegate: nil, didRun: nil, contextInfo: nil)
        result(accepted)
      }
    }

    super.awakeFromNib()
  }
}

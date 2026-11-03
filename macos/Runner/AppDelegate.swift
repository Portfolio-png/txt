import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// The app's answer to "may it quit?" (paper/quit), set by the window.
  var quitChannel: FlutterMethodChannel?
  private var askingToQuit = false
  private var quitApproved = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Every quit — Cmd+Q, the menu, the red close button — asks the app
  /// first, and a screen with unsaved work asks the user. Asked once: another
  /// quit while the question is open is ignored. Flutter's own handler marked
  /// the app as quitting the moment it asked, so a second Cmd+Q or close
  /// during "Leave with unsaved work?" quit without saving.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if quitApproved { return .terminateNow }
    guard let channel = quitChannel else { return .terminateNow }
    if askingToQuit { return .terminateCancel }
    askingToQuit = true
    channel.invokeMethod("requestQuit", arguments: nil) { [weak self] reply in
      guard let self = self else { return }
      self.askingToQuit = false
      // Anything but "cancel" — no handler yet, an error — quits, as before.
      if (reply as? String) != "cancel" {
        self.quitApproved = true
        NSApp.terminate(nil)
      }
    }
    return .terminateCancel
  }
}

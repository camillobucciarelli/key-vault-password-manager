import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func application(_ application: NSApplication, open urls: [URL]) {
    let otpAuthUrls = urls.filter { $0.scheme?.lowercased() == "otpauth" }
    let otherUrls = urls.filter { $0.scheme?.lowercased() != "otpauth" }
    otpAuthUrls.forEach { OtpAuthDeepLinkForwarder.shared.receive($0) }
    if !otherUrls.isEmpty {
      super.application(application, open: otherUrls)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

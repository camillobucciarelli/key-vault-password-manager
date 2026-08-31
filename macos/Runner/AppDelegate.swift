import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    excludeManagedStorageFromBackup()
    super.applicationDidFinishLaunching(notification)
  }

  /// spec 014 FR-7 (T013): the managed root (Application Support) is marked
  /// do-not-back-up so Time Machine and iCloud never carry the vaults, key
  /// files or their encrypted metadata.
  private func excludeManagedStorageFromBackup() {
    guard let support = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first else { return }
    // path_provider appends the bundle id only outside the sandbox (inside a
    // container the path is already app-scoped). Mark whichever shape this
    // process resolves to.
    let sandboxed = support.path.contains("/Containers/")
    var url = support
    if !sandboxed, let bundleId = Bundle.main.bundleIdentifier {
      url = support.appendingPathComponent(bundleId, isDirectory: true)
    }
    try? FileManager.default.createDirectory(
      at: url, withIntermediateDirectories: true
    )
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
  }

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

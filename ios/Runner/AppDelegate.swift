import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Channel name must match DeviceBackupExclusion in the Dart side.
  private static let backupChannelName = "com.turkisecurity.floos/device_backup"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerBackupExclusionChannel(engineBridge.pluginRegistry)
  }

  /// Everything under Documents/ is swept into iCloud and Finder backups by
  /// default, and that is where the finance database and its exported backups
  /// live. Android blocks this in the manifest; iOS has no equivalent, so it
  /// has to be set per file, as a resource value on the file URL.
  private func registerBackupExclusionChannel(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "FloosDeviceBackup") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: AppDelegate.backupChannelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "exclude" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(false)
        return
      }
      result(AppDelegate.setExcludedFromBackup(path))
    }
  }

  /// Sets the exclusion flag, then reads it back and reports what the OS
  /// actually holds. The Dart side treats a false as a failure worth showing
  /// the user: a privacy control nobody verifies is how this was missed in the
  /// first place.
  private static func setExcludedFromBackup(_ path: String) -> Bool {
    guard FileManager.default.fileExists(atPath: path) else { return false }
    var url = URL(fileURLWithPath: path)
    do {
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try url.setResourceValues(values)
    } catch {
      return false
    }
    let readBack = try? URL(fileURLWithPath: path)
      .resourceValues(forKeys: [.isExcludedFromBackupKey])
    return readBack?.isExcludedFromBackup ?? false
  }
}

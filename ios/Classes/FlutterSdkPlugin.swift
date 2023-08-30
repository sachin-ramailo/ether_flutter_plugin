import Flutter
import UIKit
import Foundation


public class FlutterSdkPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_sdk", binaryMessenger: registrar.messenger())
    let instance = FlutterSdkPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "generateNewMnemonic":
      result(RlyNetworkMobileSdk().generateMnemonic())
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

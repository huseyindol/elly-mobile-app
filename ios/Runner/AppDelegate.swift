import AVFoundation
import CallKit
import Flutter
import PushKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate, CXProviderDelegate {

  private var callkitChannel: FlutterMethodChannel?
  private var voipRegistry: PKPushRegistry?
  private var callProvider: CXProvider?
  private let callController = CXCallController()
  private var activeCallUUID: UUID?
  private var cachedVoipToken: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureCallKit()
    configurePushKit()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "EllyCallKitBridge") {
      let channel = FlutterMethodChannel(name: "elly/callkit", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleFlutterMethod(call, result: result)
      }
      self.callkitChannel = channel
      if let token = cachedVoipToken {
        channel.invokeMethod("onVoipToken", arguments: ["voipToken": token])
      }
    }
  }

  // MARK: - CallKit & PushKit Setup

  private func configureCallKit() {
    let config = CXProviderConfiguration(localizedName: "Elly Studio")
    config.supportsVideo = true
    config.maximumCallsPerCallGroup = 1
    config.maximumCallGroups = 1
    config.supportedHandleTypes = [.generic]

    let provider = CXProvider(configuration: config)
    provider.setDelegate(self, queue: nil)
    self.callProvider = provider
  }

  private func configurePushKit() {
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    self.voipRegistry = registry
  }

  // MARK: - Flutter MethodChannel Handler

  private func handleFlutterMethod(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getVoipToken":
      result(cachedVoipToken)

    case "showIncomingCall":
      let args = call.arguments as? [String: Any] ?? [:]
      let rawCallId = args["callId"] as? String
      let callerName = (args["callerName"] as? String) ?? "Gelen Çağrı"
      reportIncomingCall(rawCallId: rawCallId, callerName: callerName, completion: nil)
      result(true)

    case "endCall":
      endActiveCall()
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func reportIncomingCall(rawCallId: String?, callerName: String, completion: (() -> Void)?) {
    guard let provider = callProvider else {
      completion?()
      return
    }
    let uuid = (rawCallId != nil ? UUID(uuidString: rawCallId!) : nil) ?? UUID()
    if activeCallUUID == uuid {
      completion?()
      return
    }
    activeCallUUID = uuid

    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: callerName)
    update.localizedCallerName = callerName
    update.hasVideo = true

    provider.reportNewIncomingCall(with: uuid, update: update) { _ in
      completion?()
    }
  }

  private func endActiveCall() {
    guard let uuid = activeCallUUID else { return }
    activeCallUUID = nil
    let action = CXEndCallAction(call: uuid)
    let transaction = CXTransaction(action: action)
    callController.request(transaction) { _ in }
  }

  // MARK: - PKPushRegistryDelegate (Apple VoIP Push)

  func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    cachedVoipToken = token
    callkitChannel?.invokeMethod("onVoipToken", arguments: ["voipToken": token])
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    cachedVoipToken = nil
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    let dict = payload.dictionaryPayload
    let rawCallId = dict["callId"] as? String
    let callerName = (dict["callerDisplayName"] as? String) ?? "Elly Gelen Arama"
    let callerUserId = dict["callerUserId"] as? Int
    let ringAll = (dict["ringAll"] as? Bool) ?? false
    callkitChannel?.invokeMethod(
      "onIncomingPush",
      arguments: [
        "callId": rawCallId ?? "",
        "callerDisplayName": callerName,
        "callerUserId": callerUserId as Any,
        "ringAll": ringAll,
      ]
    )
    reportIncomingCall(rawCallId: rawCallId, callerName: callerName, completion: completion)
  }

  // MARK: - CXProviderDelegate

  func providerDidReset(_ provider: CXProvider) {
    activeCallUUID = nil
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    callkitChannel?.invokeMethod("onAcceptCall", arguments: ["video": false])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    activeCallUUID = nil
    callkitChannel?.invokeMethod("onRejectCall", arguments: nil)
    action.fulfill()
  }
}

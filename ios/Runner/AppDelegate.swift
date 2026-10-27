import AVFoundation
import CallKit
import Flutter
import PushKit
import UIKit
import WebRTC

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate, CXProviderDelegate {

  private var callkitChannel: FlutterMethodChannel?
  private var voipRegistry: PKPushRegistry?
  private var callProvider: CXProvider?
  private let callController = CXCallController()
  private var activeCallUUID: UUID?
  private var activeCallReportedToCallKit = false
  private var activeCallAnswered = false
  private var cachedVoipToken: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureWebRTCAudioDefaults()
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

  // MARK: - CallKit, PushKit & WebRTC Audio Setup

  private func configureWebRTCAudioDefaults() {
    let config = RTCAudioSessionConfiguration.webRTC()
    config.category = AVAudioSession.Category.playAndRecord.rawValue
    config.mode = AVAudioSession.Mode.voiceChat.rawValue
    config.categoryOptions = [
      .allowBluetooth,
      .allowBluetoothA2DP,
      .allowAirPlay,
      .defaultToSpeaker,
    ]
    RTCAudioSessionConfiguration.setWebRTC(config)
  }

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
      // Uygulama ön plandayken Flutter kendi tam ekran CallScreen'ini zaten gösteriyor;
      // üstüne ikinci bir CallKit başlığı düşürmemek için yalnız arka planda/kilit ekranında bildir.
      if UIApplication.shared.applicationState != .active {
        reportIncomingCall(rawCallId: rawCallId, callerName: callerName, completion: nil)
      } else if let rawCallId = rawCallId, let uuid = UUID(uuidString: rawCallId), activeCallUUID == nil {
        activeCallUUID = uuid
        activeCallReportedToCallKit = false
        activeCallAnswered = false
      }
      result(true)

    case "acceptCall":
      acceptActiveCallFromFlutter()
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
    if activeCallUUID == uuid && activeCallReportedToCallKit {
      completion?()
      return
    }
    let wasAlreadyAnswered = (activeCallUUID == uuid && activeCallAnswered)
    activeCallUUID = uuid
    activeCallReportedToCallKit = true
    if !wasAlreadyAnswered {
      activeCallAnswered = false
      let rtcAudio = RTCAudioSession.sharedInstance()
      rtcAudio.useManualAudio = true
      rtcAudio.isAudioEnabled = false
    }

    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: callerName)
    update.localizedCallerName = callerName
    update.hasVideo = true

    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      completion?()
      guard error == nil, let self = self else { return }
      if wasAlreadyAnswered || (self.activeCallUUID == uuid && self.activeCallAnswered) {
        let action = CXAnswerCallAction(call: uuid)
        self.callController.request(CXTransaction(action: action)) { _ in }
      }
    }
  }

  private func configureAudioSession() {
    let rtcAudio = RTCAudioSession.sharedInstance()
    rtcAudio.lockForConfiguration()
    defer { rtcAudio.unlockForConfiguration() }
    let config = RTCAudioSessionConfiguration.webRTC()
    try? rtcAudio.setConfiguration(config)
  }

  private func activateWebRTCAudioDirectly() {
    let rtcAudio = RTCAudioSession.sharedInstance()
    rtcAudio.lockForConfiguration()
    let config = RTCAudioSessionConfiguration.webRTC()
    try? rtcAudio.setConfiguration(config, active: true)
    rtcAudio.unlockForConfiguration()
    rtcAudio.useManualAudio = false
    rtcAudio.isAudioEnabled = true
  }

  private func acceptActiveCallFromFlutter() {
    activeCallAnswered = true
    if activeCallReportedToCallKit, let uuid = activeCallUUID {
      configureAudioSession()
      let action = CXAnswerCallAction(call: uuid)
      let transaction = CXTransaction(action: action)
      callController.request(transaction) { [weak self] error in
        if error != nil {
          self?.activateWebRTCAudioDirectly()
        }
      }
    } else {
      activateWebRTCAudioDirectly()
    }
  }

  private func endActiveCall() {
    let uuid = activeCallUUID
    let wasReported = activeCallReportedToCallKit
    activeCallUUID = nil
    activeCallReportedToCallKit = false
    activeCallAnswered = false
    if wasReported, let uuid = uuid {
      let action = CXEndCallAction(call: uuid)
      let transaction = CXTransaction(action: action)
      callController.request(transaction) { _ in }
    } else {
      let rtcAudio = RTCAudioSession.sharedInstance()
      rtcAudio.useManualAudio = false
    }
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
    let callerUserId = (dict["callerUserId"] as? NSNumber)?.intValue ?? (dict["callerUserId"] as? Int)
    let ringAll = (dict["ringAll"] as? NSNumber)?.boolValue ?? (dict["ringAll"] as? Bool) ?? false
    reportIncomingCall(rawCallId: rawCallId, callerName: callerName, completion: completion)
    callkitChannel?.invokeMethod(
      "onIncomingPush",
      arguments: [
        "callId": rawCallId ?? "",
        "callerDisplayName": callerName,
        "callerUserId": callerUserId as Any,
        "ringAll": ringAll,
      ]
    )
  }

  // MARK: - CXProviderDelegate

  func providerDidReset(_ provider: CXProvider) {
    activeCallUUID = nil
    activeCallReportedToCallKit = false
    activeCallAnswered = false
    let rtcAudio = RTCAudioSession.sharedInstance()
    rtcAudio.isAudioEnabled = false
    rtcAudio.useManualAudio = false
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    configureAudioSession()
    let rtcAudio = RTCAudioSession.sharedInstance()
    rtcAudio.audioSessionDidActivate(audioSession)
    rtcAudio.isAudioEnabled = true
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    let rtcAudio = RTCAudioSession.sharedInstance()
    rtcAudio.audioSessionDidDeactivate(audioSession)
    rtcAudio.isAudioEnabled = false
    rtcAudio.useManualAudio = false
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    configureAudioSession()
    let alreadyAnsweredInFlutter = activeCallAnswered
    activeCallAnswered = true
    action.fulfill()
    if !alreadyAnsweredInFlutter {
      callkitChannel?.invokeMethod("onAcceptCall", arguments: ["video": true])
    }
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    let wasActiveInNative = (activeCallUUID != nil)
    activeCallUUID = nil
    activeCallReportedToCallKit = false
    activeCallAnswered = false
    action.fulfill()
    if wasActiveInNative {
      callkitChannel?.invokeMethod("onRejectCall", arguments: nil)
    }
  }
}

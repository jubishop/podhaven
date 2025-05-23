// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Logging
import Sentry
import SwiftUI

@main
struct PodHavenApp: App {
  @InjectedObservable(\.alert) private var alert

  init() {
    Task {
      await Self.configureLogging()
      Self.configureAudioSession()
      await Container.shared.playState().start()
      await Container.shared.playManager().start()
      await Container.shared.refreshManager().start()
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .customAlert($alert.config)
    }
  }

  private static func configureLogging() async {
    let environment = await Container.shared.appInfo().environment
    switch environment {
    case .appStore, .onIPhone:
      SentrySDK.start { options in
        options.dsn =
          "https://df2c739d3207c6cbc8d0e6f965238234@o4508469263663104.ingest.us.sentry.io/4508469264711681"

        // Environment Info
        options.environment = environment.rawValue
        let version =
          Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        options.releaseName = "podhaven@\(version)"
        options.dist = buildNumber

        // Error reporting configuration
        options.enabled = true
        options.enableCrashHandler = true
        options.sampleRate = 1
        options.enableAutoSessionTracking = true
        options.attachStacktrace = true
        options.sendDefaultPii = true
        options.enableAppHangTrackingV2 = true
        options.enableReportNonFullyBlockingAppHangs = true
        options.enableAutoBreadcrumbTracking = true
        options.swiftAsyncStacktraces = true
        options.maxBreadcrumbs = 150

        // Excessive Error noise
        options.enableSigtermReporting = false
        options.enableCaptureFailedRequests = false
        options.enableNetworkBreadcrumbs = false
        options.enableNetworkTracking = false
        options.enableSpotlight = false

        // Visual context
        options.attachScreenshot = true
        options.attachViewHierarchy = true

        // Performance features disabled
        options.enableSwizzling = false
        options.tracesSampleRate = 0
        options.enableAutoPerformanceTracing = false
        options.enablePerformanceV2 = false
        options.enableUIViewControllerTracing = false
        options.enableFileIOTracing = false
        options.enableCoreDataTracing = false
      }

      LoggingSystem.bootstrap { label in
        MultiplexLogHandler([
          OSLogHandler(label: label),
          CrashReportHandler(),
        ])
      }
    case .preview:
      LoggingSystem.bootstrap(PrintLogHandler.init)
    case .simulator, .onMac:
      LoggingSystem.bootstrap(OSLogHandler.init)
    }
  }

  private static func configureAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
      try audioSession.setMode(.spokenAudio)
      try audioSession.setActive(true)
    } catch {
      Assert.fatal("Failed to initialize the audio session")
    }
  }
}

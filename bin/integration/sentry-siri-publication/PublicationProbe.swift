// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging
import Sentry
import SwiftUI
import Tagged
import UIKit

private final class ProbeFileManager: FileManager, @unchecked Sendable {
  override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL?
  {
    URL.documentsDirectory.appendingPathComponent("widget", isDirectory: true)
  }
}

private final class ProbeDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    let path = AppInfo.documentsDirectory.appendingPathComponent("db.sqlite").path
    guard let feed = URL(string: "https://private-sentinel.invalid/feed") else {
      fatalError("Invalid controlled feed URL")
    }
    do {
      for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: path + suffix)
      {
        try FileManager.default.removeItem(atPath: path + suffix)
      }
      let queue = try DatabaseQueue(path: path)
      Schema.migrate(queue)
      try queue.write { db in
        let podcast =
          try Create.unsavedPodcast(
            feedURL: FeedURL(feed),
            title: "Private Sentinel Title"
          )
          .insertAndFetch(db, as: Podcast.self)
        _ =
          try Create.unsavedEpisode(
            podcastId: podcast.id,
            guid: GUID("private-sentinel-guid"),
            title: "Private Sentinel Episode"
          )
          .insertAndFetch(db, as: Episode.self)
      }
      try queue.close()
    } catch {
      fatalError("Could not prepare controlled library: \(error)")
    }
    Container.shared.initializeAppDB()
    return true
  }
}

@main
struct PublicationProbe: App {
  @UIApplicationDelegateAdaptor(ProbeDelegate.self) private var delegate

  init() {
    let run = ProcessInfo.processInfo.environment["PODHAVEN_PUBLICATION_RUN"] ?? UUID().uuidString
    Container.shared.fileManager.register { ProbeFileManager() }
    Container.shared.siriCatalogFile.register {
      SiriCatalogFile(
        url: URL.documentsDirectory.appendingPathComponent("siri-media.json"),
        replaceContents: { data, url in
          if !data.isEmpty { Thread.sleep(forTimeInterval: 1.25) }
          try data.write(to: url, options: .atomic)
        }
      )
    }
    AppInfo.initializeEnvironment()
    do {
      try FileManager.default.createDirectory(
        at: WidgetInfo.recentLogFileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
    } catch {
      fatalError("Unable to prepare controlled widget directory: \(error)")
    }
    let options = Sentry.Options()
    AppLauncher.configureSentryOptions(options)
    options.environment = "diagnostics-issue-737"
    options.sendDefaultPii = false
    options.enableAutoSessionTracking = false
    options.enableMetricKit = false
    options.enableAppHangTracking = false
    let beforeSendLog = options.beforeSendLog
    options.beforeSendLog = { log in
      guard let log = beforeSendLog?(log) else { return nil }
      log.setAttribute(
        SentryLog.Attribute(string: "diagnostics-issue-737"),
        forKey: "sentry.environment"
      )
      log.setAttribute(SentryLog.Attribute(string: run), forKey: "diagnostic-run")
      return log
    }
    let initialScope = options.initialScope
    options.initialScope = { scope in
      let scope = initialScope(scope)
      scope.setTag(value: run, key: "diagnostic-run")
      scope.setUser(nil)
      return scope
    }
    SentrySDK.start(options: options)
    LoggingSystem.bootstrap { label in
      MultiplexLogHandler(
        AppLauncher.fileLogHandlers(label: label) + [SentryLogHandler(label: label)]
      )
    }
    Log.as("ControlledPublicationProbe").debug("controlled session ready run=\(run)")
  }

  var body: some Scene {
    WindowGroup {
      Text("Controlled Siri catalog publication diagnostics")
    }
  }
}

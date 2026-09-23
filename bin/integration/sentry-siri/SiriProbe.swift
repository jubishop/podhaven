// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Intents
import Logging
import Sentry
import SwiftUI

private final class ProbeFileManager: FileManager, @unchecked Sendable {
  override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL?
  {
    URL.documentsDirectory.appendingPathComponent("widget", isDirectory: true)
  }
}

private struct SlowReadHandle: SiriCatalogReadHandle {
  let handle: FileHandle
  func read(upToCount count: Int) throws -> Data? {
    Thread.sleep(forTimeInterval: 1.25)
    return try handle.read(upToCount: count)
  }
  func close() throws { try handle.close() }
}

@main
struct SiriProbe: App {
  nonisolated private static let log = Log.as("ControlledSiriProbe")
  private let run = ProcessInfo.processInfo.environment["PODHAVEN_SIRI_RUN"] ?? UUID().uuidString

  init() {
    Container.shared.fileManager.register { ProbeFileManager() }
    Container.shared.siriCatalogFile.register {
      SiriCatalogFile(url: URL.documentsDirectory.appendingPathComponent("siri-media.json"))
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
    LoggingSystem.bootstrap { label in
      FileLogHandler(
        label: label,
        fileURL: AppInfo.recentLogFileURL,
        maxFileSizeBytes: AppInfo.recentLogMaxFileSizeBytes,
        targetFileSizeBytes: AppInfo.recentLogTargetFileSizeBytes,
        historyPolicy: .preservePreviousSession,
        writeSynchronously: { _ in false }
      )
    }
    let widget = FileLogHandler(
      label: "PodHaven/ControlledWidgetProbe",
      fileURL: WidgetInfo.recentLogFileURL,
      maxFileSizeBytes: WidgetInfo.recentLogMaxFileSizeBytes,
      targetFileSizeBytes: WidgetInfo.recentLogTargetFileSizeBytes,
      historyPolicy: .preservePreviousSession,
      writeSynchronously: { _ in false }
    )
    widget.log(
      event: LogEvent(
        level: .debug,
        message: "controlled widget ready",
        metadata: nil,
        source: "ControlledSiriProbe",
        file: #fileID,
        function: #function,
        line: #line
      )
    )
    Self.log.debug("controlled session ready run=\(run)")
    let options = Sentry.Options()
    AppLauncher.configureSentryOptions(options)
    options.environment = "diagnostics-issue-715"
    options.sendDefaultPii = false
    options.enableAutoSessionTracking = false
    options.enableMetricKit = false
    let initialScope = options.initialScope
    let run = run
    options.initialScope = { scope in
      let scope = initialScope(scope)
      scope.setTag(value: run, key: "diagnostic-run")
      scope.setUser(nil)
      return scope
    }
    SentrySDK.start(options: options)
  }

  var body: some Scene {
    WindowGroup {
      Text("Controlled Siri catalog diagnostics")
        .onAppear {
          DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            let file = Container.shared.siriCatalogFile()
            do {
              try file.write(
                SiriCatalog(entries: [
                  .init(
                    identity: .init(
                      kind: .podcast,
                      id: 913759,
                      feed: "https://private-sentinel.invalid"
                    ),
                    title: "Private Sentinel Title",
                    podcastTitle: nil
                  )
                ])
              )
            } catch { fatalError("Could not prepare controlled catalog: \(error)") }
            let slow = SiriCatalogFile(
              url: file.url,
              openForReading: { url in
                SlowReadHandle(handle: try FileHandle(forReadingFrom: url))
              }
            )
            let handler = SiriMediaIntentHandler(
              catalog: slow.read,
              authorized: { true },
              diagnostic: { Container.shared.siriResolutionDiagnostics().record($0) }
            )
            let intent = INPlayMediaIntent(
              mediaItems: nil,
              mediaContainer: nil,
              playShuffled: nil,
              playbackRepeatMode: .unknown,
              resumePlayback: nil,
              playbackQueueLocation: .unknown,
              playbackSpeed: nil,
              mediaSearch: INMediaSearch(
                mediaType: .podcastShow,
                sortOrder: .unknown,
                mediaName: "Private Sentinel Title",
                artistName: nil,
                albumName: nil,
                genreNames: nil,
                moodNames: nil,
                releaseDate: nil,
                reference: .unknown,
                mediaIdentifier: nil
              )
            )
            handler.resolveMediaItems(for: intent) { _ in
              DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                Thread.sleep(forTimeInterval: 4)
                Self.log.debug("controlled hang recovered after Siri resolution")
              }
            }
          }
        }
    }
  }
}

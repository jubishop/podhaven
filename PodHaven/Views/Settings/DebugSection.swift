// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import Logging
import SwiftUI

struct DebugSection: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.bgTaskScheduler) private var bgTaskScheduler
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding
  @DynamicInjected(\.userSettings) private var userSettings

  @State private var pendingEmbeddings: Int? = nil

  private static let log = Log.as(LogSubsystem.SettingsView.main)

  private var pendingEmbeddingsLabel: String {
    if let pendingEmbeddings {
      return "Embeddings remaining: \(pendingEmbeddings.formatted())"
    }
    return "Embeddings remaining: …"
  }

  private func debounceLabel(_ label: String, _ debounce: AdaptiveDebounce) -> String {
    func seconds(_ d: Duration) -> String {
      let value = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
      return "\(value.formatted(decimalPlaces: 2))s"
    }
    let window = debounce.passDurations.map(seconds).joined(separator: ", ")
    return "\(label): next \(seconds(debounce.nextDebounceDuration)) (window [\(window)])"
  }

  var body: some View {
    Section("Debugging") {
      Text("Environment: \(AppInfo.environment.rawValue)")

      Text(pendingEmbeddingsLabel)
        .task {
          do {
            let ids = try await recommendationRepo.episodesNeedingEmbeddings(
              revision: contextualEmbedding.revision
            )
            pendingEmbeddings = ids.count
          } catch {
            Self.log.caughtError("Failed to count pending embeddings", error)
          }
        }

      Button("Copy Device ID") {
        UIPasteboard.general.string = AppInfo.deviceIdentifier
      }

      Text(debounceLabel("Cache rebuild", recommendationEngine.cacheRebuildDebounce))
      Text(
        debounceLabel("Recs rebuild", recommendationEngine.recommendationsRebuildDebounce)
      )

      SettingsRow(
        infoText: """
          Installs a database write probe that logs commit rate, affected \
          tables, and sampled backtraces for every committed transaction — \
          used to trace runaway DB-write loops.
          """
      ) {
        Toggle("DB Write Probe", isOn: userSettings.$enableWriteProbe.binding)
      }

      #if DEBUG
      Text("in DEBUG")
      #else
      Text("Version \(AppInfo.version) (\(AppInfo.buildNumber))")
      Text("Built \(Date.usShortDateFormatWithTime.string(from: AppInfo.buildDate))")
      #endif

      Text("Git: \(AppInfo.gitCommitHash)")

      Button("Show Pending Background Tasks") {
        bgTaskScheduler.getPendingTaskRequests { requests in
          let formatted = BackgroundTaskScheduler.formatPendingTasks(requests)
          Task { @MainActor in
            alert(
              title: "Pending Tasks",
              """
              Pending Background Tasks:
                \(formatted)
              """
            )
          }
        }
      }

      ShareLink(
        item: AppInfo.logFileURL,
        preview: SharePreview(
          "PodHaven Logs",
          image: AppIcon.shareLogs.rawImage
        ),
        label: { AppIcon.shareLogs.label }
      )

      ShareLink(
        item: WidgetInfo.logFileURL,
        preview: SharePreview(
          "Widget Logs",
          image: AppIcon.shareLogs.rawImage
        ),
        label: { AppIcon.shareLogs.label("Share Widget Logs") }
      )

      ShareLink(
        item: AppInfo.documentsDirectory.appendingPathComponent("db.sqlite"),
        preview: SharePreview(
          "PodHaven Database",
          image: AppIcon.shareDatabase.rawImage
        ),
        label: { AppIcon.shareDatabase.label }
      )
    }
  }
}

#if DEBUG
#Preview {
  DebugSection().preview()
}
#endif

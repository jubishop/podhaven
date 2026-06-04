// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import Logging
import SwiftUI
import UniformTypeIdentifiers

struct DebugSection: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.bgTaskScheduler) private var bgTaskScheduler
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding
  @DynamicInjected(\.userSettings) private var userSettings

  @State private var pendingEmbeddings: Int? = nil

  private static var log: Logger { Log.as(LogSubsystem.SettingsView.main) }

  private var pendingEmbeddingsLabel: String {
    if let pendingEmbeddings {
      return "Embeddings remaining: \(pendingEmbeddings.formatted())"
    }
    return "Embeddings remaining: …"
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

      LogFileExportButton(
        sourceURL: AppInfo.logFileURL,
        previewTitle: "PodHaven Logs",
        exportFilename: "log.ndjson",
        flushBeforeExport: true,
        label: { AppIcon.shareLogs.label }
      )

      LogFileExportButton(
        sourceURL: WidgetInfo.logFileURL,
        previewTitle: "Widget Logs",
        exportFilename: "widget-log.ndjson",
        flushBeforeExport: false,
        label: { AppIcon.shareLogs.label("Share Widget Logs") }
      )

      ShareLink(
        item: DatabaseExportItem(),
        preview: SharePreview(
          "PodHaven Database",
          image: AppIcon.shareDatabase.rawImage
        ),
        label: { AppIcon.shareDatabase.label }
      )
    }
  }
}

private struct LogFileExportButton<Label: View>: View {
  let sourceURL: URL
  let previewTitle: String
  let exportFilename: String
  let flushBeforeExport: Bool
  let label: () -> Label

  @DynamicInjected(\.alert) private var alert
  @State private var exportDocument: LogFileDocument?
  @State private var isExporting = false

  private static var log: Logger { Log.as(LogSubsystem.SettingsView.main) }

  init(
    sourceURL: URL,
    previewTitle: String,
    exportFilename: String,
    flushBeforeExport: Bool,
    @ViewBuilder label: @escaping () -> Label
  ) {
    self.sourceURL = sourceURL
    self.previewTitle = previewTitle
    self.exportFilename = exportFilename
    self.flushBeforeExport = flushBeforeExport
    self.label = label
  }

  var body: some View {
    if AppInfo.environment == .macDev {
      Button(action: startExport, label: label)
        .fileExporter(
          isPresented: $isExporting,
          document: exportDocument,
          contentType: LogFilePayload.contentType,
          defaultFilename: exportFilename,
          onCompletion: completeExport
        )
    } else {
      ShareLink(
        item: LogFileShareItem(
          sourceURL: sourceURL,
          exportFilename: exportFilename,
          flushBeforeExport: flushBeforeExport
        ),
        preview: SharePreview(previewTitle),
        label: label
      )
    }
  }

  private func startExport() {
    do {
      exportDocument = LogFileDocument(
        payload: try LogFilePayload.load(
          sourceURL: sourceURL,
          exportFilename: exportFilename,
          flushBeforeExport: flushBeforeExport
        )
      )
      isExporting = true
    } catch {
      Self.log.caughtError("Log export: failed to prepare \(exportFilename)", error)
      alert(title: "Failed to Export Logs", "Could not prepare \(exportFilename).")
    }
  }

  private func completeExport(_ result: Result<URL, any Error>) {
    defer { exportDocument = nil }
    guard case .failure(let error) = result else { return }
    guard !Self.isUserCancelled(error) else { return }

    Self.log.caughtError("Log export: failed to write \(exportFilename)", error)
    alert(title: "Failed to Export Logs", "Could not export \(exportFilename).")
  }

  private static func isUserCancelled(_ error: any Error) -> Bool {
    let nsError = error as NSError
    return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
  }
}

private struct LogFilePayload: Sendable {
  let data: Data

  static let contentType = UTType(filenameExtension: "ndjson") ?? .json
  private static let log = Log.as(LogSubsystem.SettingsView.main)

  static func load(
    sourceURL: URL,
    exportFilename: String,
    flushBeforeExport: Bool
  ) throws -> Self {
    if flushBeforeExport {
      FileLogHandler.flush(fileURL: sourceURL)
    }

    if FileManager.default.fileExists(atPath: sourceURL.path) {
      return Self(data: try Data(contentsOf: sourceURL))
    }

    log.info("Log export: no file at \(sourceURL.path); exporting empty \(exportFilename)")
    return Self(data: Data())
  }
}

private struct LogFileDocument: FileDocument {
  static var readableContentTypes: [UTType] { [LogFilePayload.contentType] }
  static var writableContentTypes: [UTType] { [LogFilePayload.contentType] }

  let data: Data

  init(payload: LogFilePayload) {
    self.data = payload.data
  }

  init(configuration: ReadConfiguration) throws {
    self.data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

private struct LogFileShareItem: Transferable {
  let sourceURL: URL
  let exportFilename: String
  let flushBeforeExport: Bool

  private static let log = Log.as(LogSubsystem.SettingsView.main)

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: LogFilePayload.contentType) { item in
      do {
        let payload = try LogFilePayload.load(
          sourceURL: item.sourceURL,
          exportFilename: item.exportFilename,
          flushBeforeExport: item.flushBeforeExport
        )
        return payload.data
      } catch {
        log.caughtError("Log export: failed to prepare \(item.exportFilename)", error)
        throw error
      }
    }
    .suggestedFileName { item in item.exportFilename }
  }
}

private struct DatabaseExportItem: Transferable {
  private static let log = Log.as(LogSubsystem.Database.appDB)
  private static let sqliteExportContentType =
    UTType(filenameExtension: "sqlite") ?? .data

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: sqliteExportContentType) { _ in
      do {
        let exportDirectory = FileManager.default.temporaryDirectory
          .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
          at: exportDirectory,
          withIntermediateDirectories: true
        )
        let exportURL = exportDirectory.appendingPathComponent("db.sqlite")
        try Container.shared.appDB().exportSnapshot(to: exportURL)
        return SentTransferredFile(exportURL, allowAccessingOriginalFile: true)
      } catch {
        Self.log.caughtError("Failed to export database snapshot", error)
        throw error
      }
    }
  }
}

#if DEBUG
#Preview {
  DebugSection().preview()
}
#endif

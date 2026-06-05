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
  @DynamicInjected(\.appDB) private var appDB

  @State private var pendingEmbeddings: Int? = nil
  @State private var dbStats: AppDB.FileStats? = nil

  private static var log: Logger { Log.as(LogSubsystem.SettingsView.main) }

  private var pendingEmbeddingsLabel: String {
    if let pendingEmbeddings {
      return "Embeddings remaining: \(pendingEmbeddings.formatted())"
    }
    return "Embeddings remaining: …"
  }

  private var dbStatsLabel: String {
    guard let dbStats else { return "Database: …" }
    let size = ByteCountFormatter.string(
      fromByteCount: Int64(dbStats.byteCount),
      countStyle: .file
    )
    return "Database: \(size) (\(Int((dbStats.freeFraction * 100).rounded()))% free)"
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

      Text(dbStatsLabel)
        .task {
          do {
            dbStats = try await appDB.fileStats()
          } catch {
            Self.log.caughtError("Failed to read database file stats", error)
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

      DatabaseExportButton(label: { AppIcon.shareDatabase.label })
    }
  }
}

// In the Simulator the iOS share sheet can't reach the Mac, so exports write
// straight to the host Desktop via the path the Simulator injects.
private func simulatorDesktopURL(for filename: String) -> URL? {
  guard let hostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else {
    return nil
  }
  return URL(filePath: hostHome).appending(path: "Desktop").appending(path: filename)
}

private func isExportCancelled(_ error: any Error) -> Bool {
  let nsError = error as NSError
  return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
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
    switch AppInfo.environment {
    case .macDev:
      Button(action: startExport, label: label)
        .fileExporter(
          isPresented: $isExporting,
          document: exportDocument,
          contentType: LogFilePayload.contentType,
          defaultFilename: exportFilename,
          onCompletion: completeExport
        )
    case .simulator:
      Button(action: copyToHostDesktop, label: label)
    default:
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

  private func copyToHostDesktop() {
    guard let destination = simulatorDesktopURL(for: exportFilename) else {
      Self.log.error("Log export: SIMULATOR_HOST_HOME unset; cannot copy \(exportFilename)")
      alert(title: "Failed to Export Logs", "Simulator host path unavailable.")
      return
    }
    do {
      let payload = try LogFilePayload.load(
        sourceURL: sourceURL,
        exportFilename: exportFilename,
        flushBeforeExport: flushBeforeExport
      )
      try payload.data.write(to: destination, options: .atomic)
      alert(title: "Logs Saved", "Saved to \(destination.path)")
    } catch {
      Self.log.caughtError("Log export: failed to copy \(exportFilename) to host Desktop", error)
      alert(title: "Failed to Export Logs", "Could not copy \(exportFilename) to the Mac.")
    }
  }

  private func completeExport(_ result: Result<URL, any Error>) {
    defer { exportDocument = nil }
    guard case .failure(let error) = result else { return }
    guard !isExportCancelled(error) else { return }

    Self.log.caughtError("Log export: failed to write \(exportFilename)", error)
    alert(title: "Failed to Export Logs", "Could not export \(exportFilename).")
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

private struct DatabaseExportButton<Label: View>: View {
  let label: () -> Label

  @DynamicInjected(\.alert) private var alert
  @State private var exportDocument: DatabaseDocument?
  @State private var isExporting = false

  private static var log: Logger { Log.as(LogSubsystem.Database.appDB) }

  init(@ViewBuilder label: @escaping () -> Label) {
    self.label = label
  }

  var body: some View {
    switch AppInfo.environment {
    case .macDev:
      Button(action: startExport, label: label)
        .fileExporter(
          isPresented: $isExporting,
          document: exportDocument,
          contentType: DatabaseExportItem.contentType,
          defaultFilename: DatabaseExportItem.exportFilename,
          onCompletion: completeExport
        )
    case .simulator:
      Button(action: copyToHostDesktop, label: label)
    default:
      ShareLink(
        item: DatabaseExportItem(),
        preview: SharePreview(
          "PodHaven Database",
          image: AppIcon.shareDatabase.rawImage
        ),
        label: label
      )
    }
  }

  private func startExport() {
    do {
      exportDocument = DatabaseDocument(data: try DatabaseExportItem.snapshotData())
      isExporting = true
    } catch {
      Self.log.caughtError("Database export: failed to prepare snapshot", error)
      alert(title: "Failed to Export Database", "Could not prepare the database snapshot.")
    }
  }

  private func copyToHostDesktop() {
    guard let destination = simulatorDesktopURL(for: DatabaseExportItem.exportFilename) else {
      Self.log.error("Database export: SIMULATOR_HOST_HOME unset; cannot copy snapshot")
      alert(title: "Failed to Export Database", "Simulator host path unavailable.")
      return
    }
    do {
      try Container.shared.appDB().exportSnapshot(to: destination)
      alert(title: "Database Saved", "Saved to \(destination.path)")
    } catch {
      Self.log.caughtError("Database export: failed to copy snapshot to host Desktop", error)
      alert(title: "Failed to Export Database", "Could not copy the database to the Mac.")
    }
  }

  private func completeExport(_ result: Result<URL, any Error>) {
    defer { exportDocument = nil }
    guard case .failure(let error) = result else { return }
    guard !isExportCancelled(error) else { return }

    Self.log.caughtError("Database export: failed to write snapshot", error)
    alert(title: "Failed to Export Database", "Could not export the database.")
  }
}

private struct DatabaseDocument: FileDocument {
  static var readableContentTypes: [UTType] { [DatabaseExportItem.contentType] }
  static var writableContentTypes: [UTType] { [DatabaseExportItem.contentType] }

  let data: Data

  init(data: Data) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    self.data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

private struct DatabaseExportItem: Transferable {
  static let exportFilename = "db.sqlite"
  static let contentType = UTType(filenameExtension: "sqlite") ?? .data

  private static let log = Log.as(LogSubsystem.Database.appDB)

  static func exportSnapshotFile() throws -> URL {
    let exportDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: exportDirectory,
      withIntermediateDirectories: true
    )
    let exportURL = exportDirectory.appendingPathComponent(exportFilename)
    try Container.shared.appDB().exportSnapshot(to: exportURL)
    return exportURL
  }

  static func snapshotData() throws -> Data {
    try Data(contentsOf: exportSnapshotFile())
  }

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: contentType) { _ in
      do {
        return SentTransferredFile(
          try exportSnapshotFile(),
          allowAccessingOriginalFile: true
        )
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

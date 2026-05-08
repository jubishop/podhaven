// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import os

extension Container {
  fileprivate var fileLogWriter: ParameterFactory<(URL, Int, Int), FileLogHandler.Writer> {
    ParameterFactory(self) {
      FileLogHandler.Writer(fileURL: $0.0, maxFileSizeBytes: $0.1, targetFileSizeBytes: $0.2)
    }
    .scope(.cached)
  }
}

struct FileLogHandler: LogHandler {
  // MARK: - Writer

  fileprivate final class Writer: Sendable {
    private static let log = Log.as("FileLogWriter")
    private static let fallbackLog = os.Logger(subsystem: "PodHaven", category: "FileLogWriter")

    let fileURL: URL
    let maxFileSizeBytes: Int
    let targetFileSizeBytes: Int
    private let queue: DispatchQueue

    init(fileURL: URL, maxFileSizeBytes: Int, targetFileSizeBytes: Int) {
      self.fileURL = fileURL
      self.maxFileSizeBytes = maxFileSizeBytes
      self.targetFileSizeBytes = targetFileSizeBytes
      let fileName = fileURL.deletingPathExtension().lastPathComponent
      self.queue = DispatchQueue(
        label: "\(AppInfo.bundleIdentifier).FileLogHandler.Writer.\(fileName)",
        qos: .background
      )
    }

    func write(_ entry: Entry, synchronously: Bool) {
      if synchronously {
        let result = queue.sync { writeEntry(entry) }
        report(result)
      } else {
        queue.async {
          let result = self.writeEntry(entry)
          Task { [weak self] in
            guard let self else { return }
            report(result)
          }
        }
      }
    }

    func flush() {
      queue.sync {}
    }

    private enum WriteResult {
      case ok
      case message(String)
      case failed(any Error)
    }

    // Must be called on `queue`.
    private func writeEntry(_ entry: Entry) -> WriteResult {
      do {
        let currentSize = try appendEntry(entry)
        if currentSize > UInt64(maxFileSizeBytes) {
          if let truncation = try truncateIfNeeded() {
            return .message(
              "Log truncated from \(truncation.originalSize) to \(truncation.newSize) bytes"
            )
          }
        }
        return .ok
      } catch {
        return .failed(error)
      }
    }

    // Must be called outside `queue` (or asynchronously) to avoid deadlock.
    private func report(_ result: WriteResult) {
      switch result {
      case .ok:
        break
      case .message(let message):
        Self.log.info("\(message)")
      case .failed(let error):
        Self.fallbackLog.error(
          "Failed to write log entry: \(error.localizedDescription, privacy: .public)"
        )
      }
    }

    private func appendEntry(_ entry: Entry) throws -> UInt64 {
      var data = try JSONEncoder().encode(entry)
      data.append(0x0A)

      do {
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        handle.write(data)
        return handle.offsetInFile
      } catch CocoaError.fileNoSuchFile {
        try data.write(to: fileURL)
        return UInt64(data.count)
      }
    }

    private func truncateIfNeeded() throws -> (originalSize: Int, newSize: Int)? {
      let data = try Data(contentsOf: fileURL)
      guard data.count > maxFileSizeBytes else { return nil }

      let bytesToRemove = data.count - targetFileSizeBytes
      guard bytesToRemove > 0 else { return nil }

      let searchRange = bytesToRemove..<data.count
      guard let newlineIndex = data[searchRange].firstIndex(of: 0x0A) else { return nil }

      let truncated = data[(newlineIndex + 1)...]
      try truncated.write(to: fileURL, options: .atomic)

      return (originalSize: data.count, newSize: truncated.count)
    }
  }

  // MARK: - Entry

  fileprivate struct Entry: Codable {
    let level: Int
    let levelName: String
    let timestamp: Int64
    let subsystem: String
    let category: String
    let message: String
    let metadata: [String: String]?
    let source: String
    let file: String
    let function: String
    let line: UInt
  }

  // MARK: - LogHandler

  public var metadata: Logging.Logger.Metadata = [:]
  public var metadataProvider: Logging.Logger.MetadataProvider?
  public subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
    get { self.metadata[metadataKey] }
    set(newValue) { self.metadata[metadataKey] = newValue }
  }
  public var logLevel: Logging.Logger.Level = .trace

  // MARK: - State

  private static let writer = ThreadSafe<Writer?>(nil)
  private let subsystem: String
  private let category: String
  private let writer: Writer
  private let writeSynchronously: @Sendable (Logging.Logger.Level) -> Bool

  // MARK: - Initialization

  init(
    label: String,
    fileURL: URL,
    maxFileSizeBytes: Int,
    targetFileSizeBytes: Int,
    writeSynchronously: @escaping @Sendable (Logging.Logger.Level) -> Bool
  ) {
    let (subsystem, category) = LogKit.destructureLabel(from: label)
    self.subsystem = subsystem
    self.category = category
    self.writeSynchronously = writeSynchronously

    let writer = Container.shared.fileLogWriter((fileURL, maxFileSizeBytes, targetFileSizeBytes))
    Self.writer(writer)
    self.writer = writer
  }

  // MARK: - Logging

  public func log(event: LogEvent) {
    let mergedMetadata = LogKit.merge(
      handler: self.metadata,
      provider: self.metadataProvider,
      oneOff: event.metadata
    )

    let entry = Entry(
      level: event.level.intValue,
      levelName: event.level.rawValue,
      timestamp: Int64(Date().timeIntervalSince1970 * 1000),
      subsystem: subsystem,
      category: category,
      message: event.message.description,
      metadata: mergedMetadata.isEmpty
        ? nil
        : Dictionary(uniqueKeysWithValues: mergedMetadata.map { ($0.key, $0.value.description) }),
      source: event.source,
      file: event.file,
      function: event.function,
      line: event.line
    )

    writer.write(entry, synchronously: writeSynchronously(event.level))
  }

  // MARK: - Flush

  static func flush() {
    writer()?.flush()
  }
}

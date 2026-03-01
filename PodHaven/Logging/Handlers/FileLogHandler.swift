// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

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
        label: "com.artisanalsoftware.PodHaven.FileLogHandler.Writer.\(fileName)",
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
      case truncated(originalSize: Int, newSize: Int)
      case failed(any Error)
    }

    // Must be called on `queue`.
    private func writeEntry(_ entry: Entry) -> WriteResult {
      do {
        let currentSize = try appendEntry(entry)
        if currentSize > UInt64(maxFileSizeBytes) {
          if let truncation = try truncateIfNeeded() {
            return .truncated(
              originalSize: truncation.originalSize,
              newSize: truncation.newSize
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
      case .truncated(let originalSize, let newSize):
        Self.log.info("Log truncated from \(originalSize) to \(newSize) bytes")
      case .failed(let error):
        Self.log.error(error)
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

  public var metadata: Logger.Metadata = [:]
  public var metadataProvider: Logger.MetadataProvider?
  public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
    get { self.metadata[metadataKey] }
    set(newValue) { self.metadata[metadataKey] = newValue }
  }
  public var logLevel: Logger.Level = .trace

  // MARK: - State

  private static let writer = ThreadSafe<Writer?>(nil)
  private let subsystem: String
  private let category: String
  private let writer: Writer
  private let writeSynchronously: @Sendable (Logger.Level) -> Bool

  // MARK: - Initialization

  init(
    label: String,
    fileURL: URL,
    maxFileSizeBytes: Int,
    targetFileSizeBytes: Int,
    writeSynchronously: @escaping @Sendable (Logger.Level) -> Bool
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

  public func log(
    level: Logger.Level,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    let mergedMetadata = LogKit.merge(
      handler: self.metadata,
      provider: self.metadataProvider,
      oneOff: metadata
    )

    let entry = Entry(
      level: level.intValue,
      levelName: level.rawValue,
      timestamp: Int64(Date().timeIntervalSince1970 * 1000),
      subsystem: subsystem,
      category: category,
      message: message.description,
      metadata: mergedMetadata.isEmpty
        ? nil
        : Dictionary(uniqueKeysWithValues: mergedMetadata.map { ($0.key, $0.value.description) }),
      source: source,
      file: file,
      function: function,
      line: line
    )

    writer.write(entry, synchronously: writeSynchronously(level))
  }

  // MARK: - Flush

  static func flush() {
    writer()?.flush()
  }
}

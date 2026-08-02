// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

extension Container {
  var publisherTranscriptSession: Factory<any DataFetchable> {
    Factory(self) {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.allowsCellularAccess = true
      configuration.waitsForConnectivity = false
      configuration.timeoutIntervalForRequest = Double(10)
      configuration.timeoutIntervalForResource = Double(30)
      return URLSession(configuration: configuration)
    }
    .scope(.cached)
  }

  var publisherTranscriptImporter: Factory<PublisherTranscriptImporter> {
    Factory(self) { PublisherTranscriptImporter() }.scope(.cached)
  }
}

struct PublisherTranscriptReference: Codable, Hashable, Sendable {
  private static let log = Log.as(LogSubsystem.Feed.podcast)

  enum Format: Int, Sendable {
    case json
    case webVTT
    case subRip
  }

  let url: URL
  let mimeType: String
  let language: String?

  enum CodingKeys: String, CodingKey {
    case url
    case mimeType = "type"
    case language
  }

  var format: Format? {
    switch mimeType
      .split(separator: ";", maxSplits: 1)
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    {
    case "application/json":
      return .json
    case "text/vtt":
      return .webVTT
    case "application/srt", "application/x-subrip":
      return .subRip
    default:
      return nil
    }
  }

  func normalized(defaultLanguage: String?) throws -> Self {
    let normalizedLanguage = language?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedDefaultLanguage = defaultLanguage?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let effectiveLanguage: String?
    if let normalizedLanguage, !normalizedLanguage.isEmpty {
      effectiveLanguage = normalizedLanguage
    } else if let normalizedDefaultLanguage, !normalizedDefaultLanguage.isEmpty {
      effectiveLanguage = normalizedDefaultLanguage
    } else {
      effectiveLanguage = nil
    }
    return Self(
      url: try url.convertToHTTPSURL(),
      mimeType: mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      language: effectiveLanguage
    )
  }

  static func canonicalized(
    _ references: [Self],
    defaultLanguage: String?
  ) -> [Self] {
    let preferredLanguage = defaultLanguage?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "_", with: "-")
      .lowercased()
    let preferredLanguageCode = preferredLanguage?
      .split(separator: "-", maxSplits: 1)
      .first
    let languageRank = { (language: String?) -> Int in
      guard let preferredLanguage, !preferredLanguage.isEmpty else { return 0 }
      let normalizedLanguage = language?
        .replacingOccurrences(of: "_", with: "-")
        .lowercased()
      if normalizedLanguage == preferredLanguage { return 0 }
      if normalizedLanguage?.split(separator: "-", maxSplits: 1).first
        == preferredLanguageCode
      {
        return 1
      }
      return 2
    }
    var seen = Set<Self>()
    return
      references
      .compactMap { reference in
        do {
          return try reference.normalized(defaultLanguage: defaultLanguage)
        } catch {
          Self.log.caughtError(
            "Ignoring invalid publisher transcript URL: \(reference.url)",
            error,
            level: .info
          )
          return nil
        }
      }
      .filter { seen.insert($0).inserted }
      .sorted { lhs, rhs in
        let lhsKey = (
          languageRank(lhs.language),
          lhs.format?.rawValue ?? Int.max,
          lhs.url.absoluteString,
          lhs.mimeType,
          lhs.language ?? ""
        )
        let rhsKey = (
          languageRank(rhs.language),
          rhs.format?.rawValue ?? Int.max,
          rhs.url.absoluteString,
          rhs.mimeType,
          rhs.language ?? ""
        )
        return lhsKey < rhsKey
      }
  }

  static func jsonString(for references: [Self]) throws -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(references), as: UTF8.self)
  }

  static func jsonString(for reference: Self?) throws -> String? {
    guard let reference else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(reference), as: UTF8.self)
  }

  static func decodeReferences(from json: String?) throws -> [Self] {
    guard let json else { return [] }
    return try JSONDecoder().decode([Self].self, from: Data(json.utf8))
  }

  static func decodeReference(from json: String?) throws -> Self? {
    guard let json else { return nil }
    return try JSONDecoder().decode(Self.self, from: Data(json.utf8))
  }
}

struct PublisherTranscriptImport: Sendable {
  let transcript: Transcript
  let source: PublisherTranscriptReference
}

enum PublisherTranscriptImportOutcome: Sendable {
  case imported(PublisherTranscriptImport)
  case retryableFailure
  case terminalFailure
}

struct PublisherTranscriptImporter: Sendable {
  @DynamicInjected(\.dateProvider) private var dateProvider
  @DynamicInjected(\.publisherTranscriptSession) private var session

  private static let log = Log.as(LogSubsystem.Transcription.processor)

  fileprivate init() {}

  func importTranscript(
    from references: [PublisherTranscriptReference]
  ) async throws -> PublisherTranscriptImport? {
    switch try await attemptImport(from: references) {
    case .imported(let imported):
      return imported
    case .retryableFailure, .terminalFailure:
      return nil
    }
  }

  func attemptImport(
    from references: [PublisherTranscriptReference]
  ) async throws -> PublisherTranscriptImportOutcome {
    let candidates = PublisherTranscriptReference.canonicalized(
      references,
      defaultLanguage: references.first?.language
    )
    var encounteredRetryableFailure = false
    for reference in candidates {
      guard let format = reference.format else { continue }

      do {
        let data = try await session.validatedData(from: reference.url)
        let segments = try PublisherTranscriptParser.parse(data, as: format)
        return .imported(
          PublisherTranscriptImport(
            transcript: Transcript(
              segments: segments,
              locale: reference.language ?? "und",
              createdAt: dateProvider.now
            ),
            source: reference
          )
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        try Task.checkCancellation()
        let retryable = Self.isRetryable(error)
        encounteredRetryableFailure = encounteredRetryableFailure || retryable
        Self.log.caughtError(
          """
          Publisher transcript candidate failed: \(reference.url) \
          retryable=\(retryable)
          """,
          error,
          level: .info
        )
      }
    }
    return encounteredRetryableFailure ? .retryableFailure : .terminalFailure
  }

  private static func isRetryable(_ error: any Error) -> Bool {
    if error is PublisherTranscriptParser.ParsingError || error is DecodingError {
      return false
    }
    if let statusError = error as? HTTPStatusError {
      return statusError.statusCode == 408
        || statusError.statusCode == 425
        || statusError.statusCode == 429
        || (500...599).contains(statusError.statusCode)
    }
    if let urlError = error as? URLError {
      switch urlError.code {
      case .badURL, .unsupportedURL, .fileDoesNotExist, .noPermissionsToReadFile,
        .resourceUnavailable, .redirectToNonExistentLocation,
        .userAuthenticationRequired, .userCancelledAuthentication,
        .appTransportSecurityRequiresSecureConnection:
        return false
      default:
        return true
      }
    }
    return true
  }
}

enum PublisherTranscriptParser {
  private struct JSONTranscript: Decodable {
    struct Segment: Decodable {
      let startTime: TimeInterval?
      let endTime: TimeInterval?
      let body: String?
    }

    let segments: [Segment]
  }

  enum ParsingError: Error, LocalizedError {
    case invalidTextEncoding
    case invalidWebVTTHeader
    case noUsableSegments

    var errorDescription: String? {
      switch self {
      case .invalidTextEncoding:
        "Transcript is not valid UTF-8"
      case .invalidWebVTTHeader:
        "Transcript does not have a valid WebVTT header"
      case .noUsableSegments:
        "Transcript has no usable timed segments"
      }
    }
  }

  static func parse(
    _ data: Data,
    as format: PublisherTranscriptReference.Format
  ) throws -> [TranscriptSegment] {
    let segments =
      switch format {
      case .json:
        try parseJSON(data)
      case .webVTT:
        try parseWebVTT(data)
      case .subRip:
        try parseSubRip(data)
      }
    guard !segments.isEmpty else { throw ParsingError.noUsableSegments }
    return segments
  }

  private static func parseJSON(_ data: Data) throws -> [TranscriptSegment] {
    let transcript = try JSONDecoder().decode(JSONTranscript.self, from: data)
    return transcript.segments.compactMap { segment in
      guard
        let start = segment.startTime,
        let end = segment.endTime,
        start.isFinite,
        end.isFinite,
        start >= 0,
        end > start,
        let body = segment.body?.trimmingCharacters(in: .whitespacesAndNewlines),
        !body.isEmpty
      else {
        return nil
      }
      return TranscriptSegment(start: start, end: end, text: body)
    }
  }

  private static func parseWebVTT(_ data: Data) throws -> [TranscriptSegment] {
    let blocks = try textBlocks(from: data)
    guard
      let header = blocks.first?.first,
      header.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\u{feff}", with: "")
        .hasPrefix("WEBVTT")
    else {
      throw ParsingError.invalidWebVTTHeader
    }
    return blocks.dropFirst().compactMap(parseCue)
  }

  private static func parseSubRip(_ data: Data) throws -> [TranscriptSegment] {
    try textBlocks(from: data).compactMap(parseCue)
  }

  private static func textBlocks(from data: Data) throws -> [[String]] {
    guard var text = String(data: data, encoding: .utf8) else {
      throw ParsingError.invalidTextEncoding
    }
    text = text.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")

    var blocks: [[String]] = []
    var block: [String] = []
    for line in text.components(separatedBy: "\n") {
      if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if !block.isEmpty {
          blocks.append(block)
          block = []
        }
      } else {
        block.append(line)
      }
    }
    if !block.isEmpty {
      blocks.append(block)
    }
    return blocks
  }

  private static func parseCue(_ lines: [String]) -> TranscriptSegment? {
    guard
      let timingIndex = lines.firstIndex(where: { $0.contains("-->") })
    else {
      return nil
    }
    let timingParts = lines[timingIndex].components(separatedBy: "-->")
    guard timingParts.count == 2 else { return nil }

    let startText = timingParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let endText = timingParts[1].split(whereSeparator: { $0.isWhitespace }).first,
      let start = timestamp(String(startText)),
      let end = timestamp(String(endText)),
      end > start
    else {
      return nil
    }

    let text = visibleText(in: Array(lines.dropFirst(timingIndex + 1)))
    guard !text.isEmpty else { return nil }
    return TranscriptSegment(start: start, end: end, text: text)
  }

  private static func timestamp(_ value: String) -> TimeInterval? {
    let normalized = value.replacingOccurrences(of: ",", with: ".")
    let components = normalized.split(separator: ":", omittingEmptySubsequences: false)
    guard components.count == 2 || components.count == 3 else { return nil }

    let hours: Double
    let minutes: Double
    let seconds: Double
    if components.count == 3 {
      guard
        let parsedHours = Double(components[0]),
        let parsedMinutes = Double(components[1]),
        let parsedSeconds = Double(components[2])
      else {
        return nil
      }
      hours = parsedHours
      minutes = parsedMinutes
      seconds = parsedSeconds
    } else {
      guard
        let parsedMinutes = Double(components[0]),
        let parsedSeconds = Double(components[1])
      else {
        return nil
      }
      hours = 0
      minutes = parsedMinutes
      seconds = parsedSeconds
    }
    guard
      hours.isFinite,
      minutes.isFinite,
      seconds.isFinite,
      hours >= 0,
      minutes >= 0,
      minutes < 60,
      seconds >= 0,
      seconds < 60
    else {
      return nil
    }
    return hours * 3_600 + minutes * 60 + seconds
  }

  private static func visibleText(in lines: [String]) -> String {
    lines
      .joined(separator: "\n")
      .replacingOccurrences(
        of: #"<br\s*/?>"#,
        with: "\n",
        options: [.regularExpression, .caseInsensitive]
      )
      .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&lrm;", with: "")
      .replacingOccurrences(of: "&rlm;", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

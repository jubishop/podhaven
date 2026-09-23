// Copyright Justin Bishop, 2026

import Foundation
import Intents
import Logging

struct SiriMediaIdentity: Codable, Equatable, Sendable {
  enum Kind: String, Codable, Sendable { case podcast, episode }
  let kind: Kind
  let id: Int64
  let feed: String
  let guid: String?

  var identifier: String {
    get throws { "podhaven-media:" + (try JSONEncoder().encode(self)).base64EncodedString() }
  }

  init(kind: Kind, id: Int64, feed: String, guid: String? = nil) {
    self.kind = kind
    self.id = id
    self.feed = feed
    self.guid = guid
  }

  init(identifier: String) throws {
    let prefix = "podhaven-media:"
    guard identifier.hasPrefix(prefix),
      let data = Data(base64Encoded: String(identifier.dropFirst(prefix.count)))
    else { throw SiriMediaFailure.noMatch }
    self = try JSONDecoder().decode(Self.self, from: data)
  }
}

enum SiriMediaFailure: Error {
  case unavailable, unsupported, noMatch, needsName, ambiguous, unauthorized
}

struct SiriMediaSelection: Sendable {
  let identity: SiriMediaIdentity
  let title: String
  let catalogGeneration: UUID
}

struct SiriCatalog: Codable, Sendable {
  struct Entry: Codable, Equatable, Sendable {
    let identity: SiriMediaIdentity
    let title: String
    let podcastTitle: String?

    var displayTitle: String {
      if let podcastTitle { return "\(title) — \(podcastTitle)" }
      return title
    }

    func mediaItem() throws -> INMediaItem {
      INMediaItem(
        identifier: try identity.identifier,
        title: displayTitle,
        type: identity.kind == .episode ? .podcastEpisode : .podcastShow,
        artwork: nil
      )
    }
  }

  let schemaVersion: Int
  let generation: UUID
  let entries: [Entry]

  init(entries: [Entry]) {
    schemaVersion = 1
    generation = UUID()
    self.entries = entries
  }

  static func normalize(_ name: String) -> String {
    if name.utf8.allSatisfy({ $0 < 128 }) {
      var bytes: [UInt8] = []
      bytes.reserveCapacity(name.utf8.count)
      var separator = false
      for byte in name.utf8 {
        let lowered = (65...90).contains(byte) ? byte + 32 : byte
        if (97...122).contains(lowered) || (48...57).contains(lowered) {
          if separator && !bytes.isEmpty { bytes.append(32) }
          bytes.append(lowered)
          separator = false
        } else {
          separator = true
        }
      }
      return String(decoding: bytes, as: UTF8.self)
    }
    let folded = name.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    var result = String.UnicodeScalarView()
    var separator = false
    for scalar in folded.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        if separator && !result.isEmpty { result.append(" ") }
        result.append(scalar)
        separator = false
      } else {
        separator = true
      }
    }
    return String(result)
  }

  func matches(_ intent: INPlayMediaIntent) throws -> [Entry] {
    try matches(SiriMediaRequest(intent))
  }

  func matches(_ request: SiriMediaRequest) throws -> [Entry] {
    guard schemaVersion == 1 else { throw SiriMediaFailure.unavailable }
    if let identifier = request.identifier {
      let identity = try SiriMediaIdentity(identifier: identifier)
      guard let entry = entries.first(where: { $0.identity == identity }) else {
        throw SiriMediaFailure.noMatch
      }
      if let title = request.selectedTitle, title != entry.displayTitle {
        throw SiriMediaFailure.noMatch
      }
      return [entry]
    }
    let query = Self.normalize(request.name)
    guard !query.isEmpty else { throw SiriMediaFailure.needsName }
    let mediaType = request.mediaType
    guard [.unknown, .podcastShow, .podcastEpisode].contains(mediaType) else {
      throw SiriMediaFailure.unsupported
    }
    let podcastName = Self.normalize(request.album)
    var albums: [String: String] = [:]
    let ranked = entries.compactMap { entry -> (Entry, Int)? in
      if mediaType == .podcastShow && entry.identity.kind != .podcast { return nil }
      if mediaType == .podcastEpisode && entry.identity.kind != .episode { return nil }
      if !podcastName.isEmpty {
        let title = entry.podcastTitle ?? ""
        let normalized: String
        if let cached = albums[title] {
          normalized = cached
        } else {
          normalized = Self.normalize(title)
          if albums.count < 1024 { albums[title] = normalized }
        }
        guard normalized == podcastName else { return nil }
      }
      let name = Self.normalize(entry.title)
      if name == query { return (entry, 0) }
      if name.hasPrefix(query + " ") { return (entry, 1) }
      if (" " + name + " ").contains(" " + query + " ") { return (entry, 2) }
      return nil
    }
    guard let rank = ranked.map(\.1).min() else { throw SiriMediaFailure.noMatch }
    return ranked.filter { $0.1 == rank }.map(\.0)
      .sorted {
        if $0.identity.kind != $1.identity.kind {
          return $0.identity.kind.rawValue < $1.identity.kind.rawValue
        }
        return $0.identity.id < $1.identity.id
      }
  }

  static func validateOptions(_ intent: INPlayMediaIntent) throws {
    guard (intent.mediaItems?.count ?? 0) <= 1,
      intent.playShuffled != true,
      [.unknown, .none].contains(intent.playbackRepeatMode),
      [.unknown, .now].contains(intent.playbackQueueLocation),
      intent.playbackSpeed == nil,
      intent.resumePlayback != false,
      intent.mediaContainer == nil || intent.mediaItems?.isEmpty != false
    else { throw SiriMediaFailure.unsupported }
    if let search = intent.mediaSearch {
      guard search.artistName == nil,
        search.genreNames?.isEmpty != false,
        search.moodNames?.isEmpty != false,
        search.releaseDate == nil,
        [.unknown, .my].contains(search.reference),
        search.sortOrder == .unknown
      else { throw SiriMediaFailure.unsupported }
    }
  }
}

struct SiriMediaRequest: Sendable {
  let identifier: String?
  let selectedTitle: String?
  let name: String
  let album: String
  let mediaType: INMediaItemType

  init(_ intent: INPlayMediaIntent) throws {
    try SiriCatalog.validateOptions(intent)
    let selected = intent.mediaItems?.first ?? intent.mediaContainer
    identifier = selected?.identifier ?? intent.mediaSearch?.mediaIdentifier
    selectedTitle = selected?.title
    name = intent.mediaSearch?.mediaName ?? selected?.title ?? ""
    album = intent.mediaSearch?.albumName ?? ""
    mediaType = intent.mediaSearch?.mediaType ?? selected?.type ?? .unknown
  }
}

protocol SiriCatalogReadHandle {
  func read(upToCount count: Int) throws -> Data?
  func close() throws
}

extension FileHandle: SiriCatalogReadHandle {}

struct SiriCatalogFile: Sendable {
  let url: URL
  private let openForReading: @Sendable (URL) async throws -> any SiriCatalogReadHandle
  private static let maximumBytes = 32 * 1024 * 1024
  private static let log = Log.as("SiriCatalogFile")

  init(
    url: URL,
    openForReading: @escaping @Sendable (URL) async throws -> any SiriCatalogReadHandle = {
      try FileHandle(forReadingFrom: $0)
    }
  ) {
    self.url = url
    self.openForReading = openForReading
  }

  @concurrent func read() async throws -> SiriCatalog {
    let operation = SiriResolutionOperation.current
    operation?.begin(.read)
    let handle = try await openForReading(url)
    let data: Data?
    do {
      data = try handle.read(upToCount: Self.maximumBytes + 1)
    } catch {
      do { try handle.close() } catch {
        Self.log.caughtError("Could not close Siri catalog after read failure", error)
      }
      throw error
    }
    try handle.close()
    operation?.readBytes(data?.count ?? 0)
    guard let data, data.count <= Self.maximumBytes else { throw SiriMediaFailure.unavailable }
    operation?.begin(.decode)
    let catalog = try JSONDecoder().decode(SiriCatalog.self, from: data)
    guard catalog.schemaVersion == 1 else { throw SiriMediaFailure.unavailable }
    operation?.decoded(catalog)
    return catalog
  }

  func write(_ catalog: SiriCatalog) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode(catalog)
      .write(
        to: url,
        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
      )
  }

  func invalidate() throws {
    try Data()
      .write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}

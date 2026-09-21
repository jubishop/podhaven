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
    name.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    .components(separatedBy: CharacterSet.alphanumerics.inverted)
    .filter { !$0.isEmpty }.joined(separator: " ")
  }

  func matches(_ intent: INPlayMediaIntent) throws -> [Entry] {
    guard schemaVersion == 1 else { throw SiriMediaFailure.unavailable }
    try Self.validateOptions(intent)
    let items = intent.mediaItems ?? []
    let selected = items.first ?? intent.mediaContainer
    if let identifier = selected?.identifier ?? intent.mediaSearch?.mediaIdentifier {
      let identity = try SiriMediaIdentity(identifier: identifier)
      guard let entry = entries.first(where: { $0.identity == identity }) else {
        throw SiriMediaFailure.noMatch
      }
      if let title = selected?.title, title != entry.displayTitle {
        throw SiriMediaFailure.noMatch
      }
      return [entry]
    }
    let query = Self.normalize(intent.mediaSearch?.mediaName ?? selected?.title ?? "")
    guard !query.isEmpty else { throw SiriMediaFailure.needsName }
    let mediaType = intent.mediaSearch?.mediaType ?? selected?.type ?? .unknown
    guard [.unknown, .podcastShow, .podcastEpisode].contains(mediaType) else {
      throw SiriMediaFailure.unsupported
    }
    let podcastName = Self.normalize(intent.mediaSearch?.albumName ?? "")
    let ranked = entries.compactMap { entry -> (Entry, Int)? in
      if mediaType == .podcastShow && entry.identity.kind != .podcast { return nil }
      if mediaType == .podcastEpisode && entry.identity.kind != .episode { return nil }
      if !podcastName.isEmpty, Self.normalize(entry.podcastTitle ?? "") != podcastName {
        return nil
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

protocol SiriCatalogReadHandle {
  func read(upToCount count: Int) throws -> Data?
  func close() throws
}

extension FileHandle: SiriCatalogReadHandle {}

struct SiriCatalogFile: Sendable {
  let url: URL
  private let openForReading: @Sendable (URL) throws -> any SiriCatalogReadHandle
  private static let maximumBytes = 32 * 1024 * 1024
  private static let log = Log.as("SiriCatalogFile")

  init(
    url: URL,
    openForReading: @escaping @Sendable (URL) throws -> any SiriCatalogReadHandle = {
      try FileHandle(forReadingFrom: $0)
    }
  ) {
    self.url = url
    self.openForReading = openForReading
  }

  func read() throws -> SiriCatalog {
    let handle = try openForReading(url)
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
    guard let data, data.count <= Self.maximumBytes else { throw SiriMediaFailure.unavailable }
    let catalog = try JSONDecoder().decode(SiriCatalog.self, from: data)
    guard catalog.schemaVersion == 1 else { throw SiriMediaFailure.unavailable }
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

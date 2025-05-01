// Copyright Justin Bishop, 2025

import Foundation
import GRDB

public protocol Savable: Codable, Hashable, FetchableRecord, PersistableRecord, Sendable {}

extension Savable {
  static var databaseTableName: String {
    let prefix = "Unsaved"
    let structName = String(describing: Self.self)

    guard
      let typeName = structName.components(separatedBy: ".").last,
      typeName.hasPrefix(prefix)
    else { Log.fatal("Type: \"\(structName)\" must start with \"\(prefix)\".") }

    let suffix = typeName.dropFirst(prefix.count)
    guard let firstCharacter = suffix.first
    else { Log.fatal("Struct name: \"\(structName)\" after \"\(prefix)\" prefix is empty.") }

    return firstCharacter.lowercased() + suffix.dropFirst()
  }
}

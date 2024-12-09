// Copyright Justin Bishop, 2024

import Foundation
import GRDB

public protocol Savable:
  Codable,
  CustomStringConvertible,
  Hashable,
  FetchableRecord,
  PersistableRecord,
  Sendable
{}

extension Savable {
  static var databaseTableName: String {
    let prefix = "Unsaved"
    let structName = String(describing: Self.self)

    guard
      let typeName = structName.components(separatedBy: ".").last,
      typeName.hasPrefix(prefix)
    else {
      fatalError(
        "Type: \"\(structName)\" must start with \"\(prefix)\"."
      )
    }

    let suffix = typeName.dropFirst(prefix.count)
    guard let firstCharacter = suffix.first else {
      fatalError(
        "Struct name: \"\(structName)\" after \"\(prefix)\" prefix is empty."
      )
    }

    return firstCharacter.lowercased() + suffix.dropFirst()
  }
}

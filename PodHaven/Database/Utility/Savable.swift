// Copyright Justin Bishop, 2024

import Foundation
import GRDB

public protocol Savable:
  Codable,
  Hashable,
  FetchableRecord,
  PersistableRecord,
  Sendable
{}

extension Savable {
  static var databaseTableName: String {
    let prefix = "Unsaved"

    let typeName =
      String(describing: Self.self).components(separatedBy: ".").last ?? ""
    guard typeName.hasPrefix(prefix) else {
      fatalError("Struct name: \(typeName) must start with \"\(prefix)\".")
    }

    let suffix = typeName.dropFirst(prefix.count)
    guard let firstCharacter = suffix.first else {
      fatalError("Struct name after '\(prefix)' prefix is empty.")
    }

    let tableName = firstCharacter.lowercased() + suffix.dropFirst()
    return tableName
  }
}

// Copyright Justin Bishop, 2025

import Foundation

struct PersistenceKey<T> {
  enum KeyName : StringLiteralType {
    case currentEpisodeID
    case currentSortOrder
    case seekForwardLength
  }
  let key: KeyName
}

struct Persistence {
  static let currentEpisodeID = PersistenceKey<Episode.ID>(key: .currentEpisodeID)
  static let currentSortOrder = PersistenceKey<String>(key: .currentSortOrder)
  static let seekForwardLength = PersistenceKey<Int>(key: .seekForwardLength)

  static func save<T>(_ value: T, for key: PersistenceKey<T>) {
    UserDefaults.standard.set(value, forKey: key.key.rawValue)
  }

  static func load<T>(for key: PersistenceKey<T>) -> T? {
    UserDefaults.standard.object(forKey: key.key.rawValue) as? T
  }

  static func save<T: Codable>(_ value: T, for key: PersistenceKey<T>) {
    let encoder = JSONEncoder()
    if let encoded = try? encoder.encode(value) {
      UserDefaults.standard.set(encoded, forKey: key.key.rawValue)
    }
  }

  static func load<T: Codable>(for key: PersistenceKey<T>) -> T? {
    let decoder = JSONDecoder()
    if let data = UserDefaults.standard.data(forKey: key.key.rawValue),
       let decoded = try? decoder.decode(T.self, from: data) {
      return decoded
    }
    return nil
  }
}


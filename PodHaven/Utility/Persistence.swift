// Copyright Justin Bishop, 2025

import Foundation

struct Persistence {
  static let currentEpisodeID = Key<Episode.ID>("currentEpisodeID")

  struct Key<T> {
    let name: String

    fileprivate init(_ name: String) {
      self.name = name
    }
  }

  static func save<T>(_ value: T, for key: Key<T>) {
    UserDefaults.standard.set(value, forKey: key.name)
  }

  static func load<T>(_ key: Key<T>) -> T? {
    UserDefaults.standard.object(forKey: key.name) as? T
  }

  static func save<T: Codable>(_ value: T, for key: Key<T>) {
    let encoder = JSONEncoder()
    if let encoded = try? encoder.encode(value) {
      UserDefaults.standard.set(encoded, forKey: key.name)
    }
  }

  static func load<T: Codable>(_ key: Key<T>) -> T? {
    let decoder = JSONDecoder()
    if let data = UserDefaults.standard.data(forKey: key.name),
      let decoded = try? decoder.decode(T.self, from: data)
    {
      return decoded
    }
    return nil
  }
}

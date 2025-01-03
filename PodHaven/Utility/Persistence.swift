// Copyright Justin Bishop, 2025

import Foundation

enum Persistence: String {
  case currentEpisodeID

  func save(_ value: Any?) {
    UserDefaults.standard.set(value, forKey: self.rawValue)
  }

  func save<T: Codable>(_ value: T) {
    let encoder = JSONEncoder()
    if let encoded = try? encoder.encode(value) {
      UserDefaults.standard.set(encoded, forKey: self.rawValue)
    }
  }

  func load<T>() -> T? {
    UserDefaults.standard.object(forKey: self.rawValue) as? T
  }

  func load<T: Codable>() -> T? {
    let decoder = JSONDecoder()
    if let data = UserDefaults.standard.data(forKey: self.rawValue),
      let decoded = try? decoder.decode(T.self, from: data)
    {
      return decoded
    }
    return nil
  }
}

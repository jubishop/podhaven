// Copyright Justin Bishop, 2026

import FactoryKit
import GRDB

extension Schema {
  static func migrateV74(_: Database) throws {
    Container.shared.standardDefaults().removeObject(forKey: "transcriptionQueue")
  }
}

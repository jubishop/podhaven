// Copyright Justin Bishop, 2026

import FactoryKit
import GRDB

extension Schema {
  static func migrateV63(_: Database) throws {
    // Search results are list-only now; drop the orphaned grid/list pref.
    Container.shared.standardDefaults().removeObject(forKey: "SearchView-displayMode")
  }
}

// Copyright Justin Bishop, 2025

import GRDB
import Logging

enum Schema {
  static let log = Log.as(LogSubsystem.Database.schema)

  // MARK: - Columns

  static let id = Column("id")
  static let creationDate = Column("creationDate")

  // MARK: - Migration

  static func migrate(_ db: some DatabaseWriter) {
    do {
      try makeMigrator().migrate(db)
    } catch {
      Assert.fatal("Schema migration failed: \(ErrorKit.message(for: error))")
    }
  }

  // MARK: - Migrator

  // Each migration body is a static func on Schema defined in its own file.
  // Registration order here is authoritative; never reorder or edit a shipped
  // migration, only append the next one.
  static func makeMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1", migrate: migrateV1)
    migrator.registerMigration("v18", migrate: migrateV18)
    migrator.registerMigration("v19", migrate: migrateV19)
    migrator.registerMigration("v20", migrate: migrateV20)
    migrator.registerMigration("v21", migrate: migrateV21)
    migrator.registerMigration("v22", migrate: migrateV22)
    migrator.registerMigration("v23", migrate: migrateV23)
    migrator.registerMigration("v24", migrate: migrateV24)
    migrator.registerMigration("v25", migrate: migrateV25)
    migrator.registerMigration("v26", migrate: migrateV26)
    migrator.registerMigration("v27", migrate: migrateV27)
    migrator.registerMigration("v28", migrate: migrateV28)
    migrator.registerMigration("v29", migrate: migrateV29)
    migrator.registerMigration("v30", migrate: migrateV30)
    migrator.registerMigration("v31", migrate: migrateV31)
    migrator.registerMigration("v32", migrate: migrateV32)
    migrator.registerMigration("v33", migrate: migrateV33)
    migrator.registerMigration("v34", migrate: migrateV34)
    migrator.registerMigration("v35", migrate: migrateV35)
    migrator.registerMigration("v36", migrate: migrateV36)
    migrator.registerMigration("v37", migrate: migrateV37)
    migrator.registerMigration("v38", migrate: migrateV38)
    migrator.registerMigration("v39", migrate: migrateV39)
    migrator.registerMigration("v40", migrate: migrateV40)
    migrator.registerMigration("v41", migrate: migrateV41)
    migrator.registerMigration("v42", migrate: migrateV42)
    migrator.registerMigration("v43", migrate: migrateV43)
    migrator.registerMigration("v44", migrate: migrateV44)
    migrator.registerMigration("v45", migrate: migrateV45)
    migrator.registerMigration("v46", migrate: migrateV46)
    migrator.registerMigration("v47", migrate: migrateV47)
    migrator.registerMigration("v48", migrate: migrateV48)
    migrator.registerMigration("v49", migrate: migrateV49)
    migrator.registerMigration("v50", migrate: migrateV50)
    migrator.registerMigration("v51", migrate: migrateV51)
    migrator.registerMigration("v52", migrate: migrateV52)
    migrator.registerMigration("v53", migrate: migrateV53)
    migrator.registerMigration("v54", migrate: migrateV54)
    migrator.registerMigration("v55", migrate: migrateV55)
    migrator.registerMigration("v56", migrate: migrateV56)
    migrator.registerMigration("v57", migrate: migrateV57)
    migrator.registerMigration("v58", migrate: migrateV58)
    migrator.registerMigration("v59", migrate: migrateV59)
    return migrator
  }
}

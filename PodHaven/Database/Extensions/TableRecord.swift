// Copyright Justin Bishop, 2025

import Foundation
import GRDB

extension TableRecord {
  public static func hasManyAnnotation<Destination>(
    _ destination: Destination.Type,
    using foreignKeyColumn: Column? = nil
  ) -> QueryInterfaceRequest<Destination> where Self: Identifiable, Destination: TableRecord {
    let foreignKeyColumn = foreignKeyColumn ?? Column("\(Self.databaseTableName)Id")
    let tableAlias = TableAlias()
    _ = Self.aliased(tableAlias)
    return Destination.filter(foreignKeyColumn == tableAlias[Schema.idColumn])
  }
}

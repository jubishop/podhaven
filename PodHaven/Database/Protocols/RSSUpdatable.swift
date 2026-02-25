// Copyright Justin Bishop, 2025

import GRDB

protocol RSSUpdatable: TableRecord {
  var rssUpdatableColumns: [(any ColumnExpression, any SQLExpressible)] { get }
  func rssEquals(_ other: Self) -> Bool

  var rssColumnAssignments: [ColumnAssignment] { get }
}

extension RSSUpdatable {
  var rssColumnAssignments: [ColumnAssignment] {
    rssUpdatableColumns.map { column, value in
      column.set(to: value)
    }
  }

  func rssUpsertAssignments(_ excluded: TableAlias<Self>) -> [ColumnAssignment] {
    rssUpdatableColumns.map { column, _ in
      column.set(to: excluded[Column(column.name)])
    }
  }
}

// Copyright Justin Bishop, 2025

import GRDB

protocol RSSUpdatable {
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
}

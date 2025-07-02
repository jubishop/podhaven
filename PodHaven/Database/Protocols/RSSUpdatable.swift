// Copyright Justin Bishop, 2025

import GRDB

protocol RSSUpdatable {
  var rssUpdatableColumns: [(ColumnExpression, SQLExpressible)] { get }
}

extension RSSUpdatable {
  func rssColumnAssignments() -> [ColumnAssignment] {
    rssUpdatableColumns.map { column, value in
      column.set(to: value)
    }
  }
}
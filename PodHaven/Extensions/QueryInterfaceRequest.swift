// Copyright Justin Bishop, 2025

import Foundation
import GRDB

extension QueryInterfaceRequest {
  func filtered(with sqlExpression: SQLSpecificExpressible?) -> Self {
    guard let sqlExpression = sqlExpression else { return self }
    return self.filter(sqlExpression)
  }
}

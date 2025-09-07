// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Tagged

extension Tagged: @retroactive SQLExpressible
where RawValue: SQLExpressible {}

extension Tagged: @retroactive StatementBinding
where RawValue: StatementBinding {}

extension Tagged: @retroactive StatementColumnConvertible
where RawValue: StatementColumnConvertible {}

extension Tagged: @retroactive DatabaseValueConvertible
where RawValue: DatabaseValueConvertible {}

extension Tagged: Stringable where Self: RawRepresentable, RawValue == URL {
  var toString: String { rawValue.hash() }
}

extension Tagged where RawValue == URL {
  func convertToHTTPSURL() throws -> Self {
    Self(try rawValue.convertToHTTPSURL())
  }
}

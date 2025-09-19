// Copyright Justin Bishop, 2025

import Foundation

protocol RangeBoundsConvertible {
  associatedtype Bound: Comparable
  var bounds: RangeBounds<Bound> { get }
}

struct RangeBounds<Bound: Comparable> {
  let lower: Bound?
  let upper: Bound?
}

extension ClosedRange: RangeBoundsConvertible {
  var bounds: RangeBounds<Bound> { RangeBounds(lower: lowerBound, upper: upperBound) }
}

extension PartialRangeFrom: RangeBoundsConvertible {
  var bounds: RangeBounds<Bound> { RangeBounds(lower: lowerBound, upper: nil) }
}

extension PartialRangeThrough: RangeBoundsConvertible {
  var bounds: RangeBounds<Bound> { RangeBounds(lower: nil, upper: upperBound) }
}

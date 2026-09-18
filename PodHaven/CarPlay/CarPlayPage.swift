// Copyright Justin Bishop, 2026

struct CarPlayPage {
  let index: Int
  let last: Int
  let range: Range<Int>
  let canPage: Bool
  let limited: Bool
  let leadingCount: Int

  init(count: Int, page: Int, limits: CarPlayListLimits, restricted: Bool, leading: Int = 0) {
    let budget = limits.sections > 0 ? max(0, min(50, limits.items)) : 0
    leadingCount = min(leading, budget)
    let available = budget - leadingCount
    canPage = !restricted && available >= 3 && count > available
    let capacity = canPage ? available - 2 : max(1, available)
    last = max(0, (count - 1) / capacity)
    index = canPage ? min(page, last) : 0
    let start = index * capacity
    range = start..<min(count, start + min(capacity, available))
    limited = !canPage && range.count < count
  }

  var controls: [(title: String, target: Int)] {
    guard canPage else { return [] }
    return [("Previous page", index - 1), ("Next page", index + 1)]
      .filter { $0.1 >= 0 && $0.1 <= last }
  }
}

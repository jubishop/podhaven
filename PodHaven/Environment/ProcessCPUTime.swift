// Copyright Justin Bishop, 2026

import Darwin
import FactoryKit
import Foundation

extension Container {
  var processCPUTime: Factory<@Sendable () -> ProcessCPUTime> {
    Factory(self) { ProcessCPUTime.sample }.scope(.cached)
  }
}

enum ProcessCPUTime: Sendable {
  case seconds(Double)
  case unavailable(Int32)

  static func sample() -> ProcessCPUTime {
    var usage = rusage()
    guard unsafe getrusage(RUSAGE_SELF, &usage) == 0 else { return .unavailable(errno) }
    return .seconds(
      Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    )
  }

  func elapsed(since initial: ProcessCPUTime) -> String {
    switch (initial, self) {
    case (.seconds(let start), .seconds(let end)):
      guard end >= start else { return "unavailable(nonmonotonic)" }
      return String(end - start)
    case (.unavailable(let code), _), (_, .unavailable(let code)):
      return "unavailable(errno:\(code))"
    }
  }
}

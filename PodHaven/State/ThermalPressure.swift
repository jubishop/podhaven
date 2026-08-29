// Copyright Justin Bishop, 2026

import Foundation

enum ThermalPressure: String, Sendable {
  case nominal
  case fair
  case serious
  case critical
  case unknown

  init(_ state: ProcessInfo.ThermalState) {
    self =
      switch state {
      case .nominal: .nominal
      case .fair: .fair
      case .serious: .serious
      case .critical: .critical
      @unknown default: .unknown
      }
  }

  var permitsDiscretionaryWork: Bool {
    switch self {
    case .nominal, .fair: true
    case .serious, .critical, .unknown: false
    }
  }
}

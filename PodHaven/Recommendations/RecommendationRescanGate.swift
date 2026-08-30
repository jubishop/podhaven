// Copyright Justin Bishop, 2026

enum DeferredRescan: Int, Comparable, Sendable {
  case none = 0
  case recommendations = 1
  case cache = 2

  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

final class RescanGate: Sendable {
  enum Decision { case proceed, deferred }

  private enum SceneState: Sendable {
    case foreground
    case background
  }

  private struct State: Sendable {
    var sceneState = SceneState.foreground
    var thermalPressure = ThermalPressure.nominal
    var pending = DeferredRescan.none

    var permitsWork: Bool {
      sceneState == .foreground && thermalPressure.permitsDiscretionaryWork
    }

    mutating func drainIfPermitted() -> DeferredRescan {
      guard permitsWork else { return .none }
      let snapshot = pending
      pending = .none
      return snapshot
    }
  }

  private let storage = ThreadSafe(State())

  @discardableResult
  func deferOrProceed(_ kind: DeferredRescan) -> Decision {
    storage { state in
      guard !state.permitsWork else { return .proceed }
      state.pending = max(state.pending, kind)
      return .deferred
    }
  }

  func enterBackground() {
    storage { $0.sceneState = .background }
  }

  func enterForeground() -> DeferredRescan {
    storage { state in
      state.sceneState = .foreground
      return state.drainIfPermitted()
    }
  }

  func updateThermalPressure(_ pressure: ThermalPressure) -> DeferredRescan {
    storage { state in
      state.thermalPressure = pressure
      return state.drainIfPermitted()
    }
  }
}

// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

extension Container {
  var currentThermalPressure: Factory<@Sendable () -> ThermalPressure> {
    Factory(self) { { ThermalPressure(ProcessInfo.processInfo.thermalState) } }.scope(.cached)
  }

  var thermalPressureMonitor: Factory<ThermalPressureMonitor> {
    Factory(self) { ThermalPressureMonitor() }.scope(.cached)
  }
}

struct ThermalPressureMonitor: Sendable {
  @DynamicInjected(\.currentThermalPressure) private var currentThermalPressure
  @DynamicInjected(\.embeddingProcessor) private var embeddingProcessor
  @DynamicInjected(\.notificationObserver) private var notificationObserver
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.transcriptionProcessor) private var transcriptionProcessor

  private static let log = Log.as("ThermalPressureMonitor")

  private let startOnce = Once()

  fileprivate init() {}

  func start() {
    startOnce.run {
      let currentThermalPressure = self.currentThermalPressure
      let embeddingProcessor = self.embeddingProcessor
      let recommendationEngine = self.recommendationEngine
      let sharedState = self.sharedState
      let transcriptionProcessor = self.transcriptionProcessor
      let applyPressure: @Sendable (ThermalPressure) -> Void = { pressure in
        sharedState.setThermalPressure(pressure)
        embeddingProcessor.handleThermalPressureChange(to: pressure)
        recommendationEngine.handleThermalPressureChange(to: pressure)
        transcriptionProcessor.handleThermalPressureChange(to: pressure)
      }
      let applyChange: @Sendable (ThermalPressure) -> Void = { pressure in
        applyPressure(pressure)
        let message: Logging.Logger.Message =
          "Thermal state changed to: \(pressure.rawValue)"
        if pressure.permitsDiscretionaryWork {
          Self.log.debug(message)
        } else {
          Self.log.warning(message)
        }
      }

      let initialPressure = currentThermalPressure()
      applyPressure(initialPressure)
      notificationObserver.observe(ProcessInfo.thermalStateDidChangeNotification) {
        applyChange(currentThermalPressure())
      }

      let registeredPressure = currentThermalPressure()
      if registeredPressure != initialPressure { applyChange(registeredPressure) }
    }
  }
}

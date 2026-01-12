// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

@Observable @MainActor
class Debouncer<Value: Equatable> {
  // MARK: - Dependencies

  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper

  // MARK: - Configuration

  @ObservationIgnored var debounceDuration: Duration
  private let initialValue: Value
  private let onChange: @MainActor (Value) async -> Void

  // MARK: - State

  var currentValue: Value {
    didSet {
      guard currentValue != oldValue else { return }
      debounce()
    }
  }
  private(set) var debouncedValue: Value

  @ObservationIgnored private var task: Task<Void, Never>?

  // MARK: - Initialization

  init(
    initialValue: Value,
    debounceDuration: Duration = .zero,
    onChange: @escaping @MainActor (Value) async -> Void
  ) {
    self.initialValue = initialValue
    self.currentValue = initialValue
    self.debouncedValue = initialValue
    self.debounceDuration = debounceDuration
    self.onChange = onChange
  }

  // MARK: - Public API

  func reset() {
    currentValue = initialValue
    debouncedValue = initialValue
    task?.cancel()
  }

  // MARK: - Private Helpers

  private func debounce() {
    task?.cancel()

    task = Task { [weak self, currentValue] in
      guard let self else { return }

      do {
        if debounceDuration > .zero {
          try await sleeper.sleep(for: debounceDuration)
        }
        guard !Task.isCancelled else { return }
        guard debouncedValue != currentValue else { return }

        debouncedValue = currentValue
        await onChange(currentValue)
      } catch {
        // Sleep was cancelled or interrupted - this is expected behavior
      }
    }
  }
}

// MARK: - StringDebouncer

@Observable @MainActor
final class StringDebouncer: Debouncer<String> {
  override init(
    initialValue: String = "",
    debounceDuration: Duration = .zero,
    onChange: @escaping @MainActor (String) async -> Void
  ) {
    super
      .init(
        initialValue: initialValue,
        debounceDuration: debounceDuration,
        onChange: onChange
      )
  }
}

// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

@Observable @MainActor
class Debouncer<Value: Equatable & Sendable> {
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

  @ObservationIgnored private lazy var debounceAction = Debounce(duration: debounceDuration)

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
    debounceAction.cancel()
  }

  // Cancels an in-flight debounce without discarding the current value, so a
  // pending fire can't land after the owner tears down.
  func cancelPending() {
    debounceAction.cancel()
  }

  // MARK: - Private Helpers

  private func debounce() {
    let value = currentValue
    debounceAction { [weak self] in
      guard let self else { return }
      await applyDebouncedValue(value)
    }
  }

  private func applyDebouncedValue(_ value: Value) async {
    guard debouncedValue != value else { return }
    debouncedValue = value
    await onChange(value)
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

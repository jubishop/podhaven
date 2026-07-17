// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

// MARK: - Container

extension Container {
  var transcriptionAvailability: Factory<TranscriptionAvailability> {
    Factory(self) { TranscriptionAvailability() }.scope(.cached)
  }
}

// MARK: - TranscriptionAvailability

struct TranscriptionAvailability: Sendable {
  @DynamicInjected(\.speechModelManager) private var speechModelManager

  enum State: Equatable, Sendable {
    case unknown
    case available
    case unavailable
  }

  static let locale = Locale(identifier: "en-US")

  @Broadcasted var state: State = .unknown

  private let prepareOnce = AsyncOnce()

  fileprivate init() {}

  var isAvailable: Bool {
    state == .available
  }

  func prepare() async {
    await prepareOnce.run {
      let identifier = Self.locale.identifier(.bcp47)
      let supported = await self.speechModelManager.supportedLocaleIdentifiers()
      self.$state.new(supported.contains(identifier) ? .available : .unavailable)
    }
  }
}

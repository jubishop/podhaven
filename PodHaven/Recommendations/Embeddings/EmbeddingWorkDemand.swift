// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

extension Container {
  var embeddingWorkDemand: Factory<EmbeddingWorkDemand> {
    Factory(self) {
      EmbeddingWorkDemand(
        pipelineVersion: EmbeddingPipelineVersion(
          embeddingRevision: self.contextualEmbedding().revision,
          recipeVersion: EmbeddingService.recipeVersion
        ),
        store: self.standardDefaults()
      )
    }
    .scope(.cached)
  }
}

struct EmbeddingPipelineVersion: Codable, Equatable, Sendable {
  let embeddingRevision: Int
  let recipeVersion: Int
}

struct EmbeddingWorkDemand: Sendable {
  struct Snapshot: Sendable {
    let generation: Int
    let requiresFullRefresh: Bool
  }

  private enum Status: String, Codable, Sendable {
    case idle
    case pending
  }

  private struct State: Codable, DefaultsStorable {
    var generation = 0
    var status = Status.idle
    var completedPipelineVersion: EmbeddingPipelineVersion?
  }

  private static let key = "embeddingWorkDemand"

  private let pipelineVersion: EmbeddingPipelineVersion
  private let state: ThreadSafe<State>
  private let store: any KeyValueStore

  fileprivate init(
    pipelineVersion: EmbeddingPipelineVersion,
    store: any KeyValueStore
  ) {
    self.pipelineVersion = pipelineVersion
    self.store = store

    var persisted = State.load(from: store, forKey: Self.key) ?? State()
    if persisted.completedPipelineVersion != pipelineVersion {
      persisted.generation += 1
      persisted.status = .pending
      persisted.store(to: store, forKey: Self.key)
    }
    state = ThreadSafe(persisted)
  }

  var hasWork: Bool {
    state().status == .pending
  }

  func snapshot() -> Snapshot {
    state { state in
      Snapshot(
        generation: state.generation,
        requiresFullRefresh: state.completedPipelineVersion != pipelineVersion
      )
    }
  }

  func markAvailable() {
    state { state in
      state.generation += 1
      state.status = .pending
      state.store(to: store, forKey: Self.key)
    }
  }

  func ensureAvailable() {
    state { state in
      guard state.status == .idle else { return }
      state.generation += 1
      state.status = .pending
      state.store(to: store, forKey: Self.key)
    }
  }

  @discardableResult
  func clear(ifUnchanged snapshot: Snapshot) -> Bool {
    state { state in
      guard state.generation == snapshot.generation else { return false }
      state.status = .idle
      state.completedPipelineVersion = pipelineVersion
      state.store(to: store, forKey: Self.key)
      return true
    }
  }
}

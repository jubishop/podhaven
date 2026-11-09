// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// Observed values whose tracked region leaves out playback progress, so
// playback checkpoints don't re-run the fetch. Each refresh restarts the
// observation instead, whose first fetch then reads the positions stored up to
// that refresh.
struct SettledPlaybackObservation<Value: Equatable & Sendable>: AsyncSequence, Sendable {
  private enum Event: Sendable {
    case value(generation: Int, Value)
    case failure(generation: Int, any Error)
    case refresh
  }

  private let observe: @Sendable () -> AsyncValueObservation<Value>
  private let refreshes: @Sendable () -> [any AsyncSequence<Void, Never> & Sendable]

  init(
    observe: @escaping @Sendable () -> AsyncValueObservation<Value>,
    refreshes: @escaping @Sendable () -> [any AsyncSequence<Void, Never> & Sendable]
  ) {
    self.observe = observe
    self.refreshes = refreshes
  }

  func makeAsyncIterator() -> AsyncThrowingStream<Value, any Error>.Iterator {
    let observe = observe
    let refreshes = refreshes
    return AsyncThrowingStream<Value, any Error> { continuation in
      let driver = Task {
        await Self.drive(observe: observe, refreshes: refreshes(), into: continuation)
      }
      continuation.onTermination = { _ in driver.cancel() }
    }
    .makeAsyncIterator()
  }

  // One loop owns the generation and the last delivered value, so a replaced
  // observation's late values are dropped and a restart that fetches an
  // unchanged value delivers nothing.
  private static func drive(
    observe: @escaping @Sendable () -> AsyncValueObservation<Value>,
    refreshes: [any AsyncSequence<Void, Never> & Sendable],
    into continuation: AsyncThrowingStream<Value, any Error>.Continuation
  ) async {
    let (events, input) = AsyncStream<Event>.makeStream()
    let forwarders = refreshes.map { refreshes in
      Task {
        for await _ in refreshes {
          input.yield(.refresh)
        }
      }
    }
    var generation = 0
    var observing = startObserving(observe(), generation: generation, into: input)
    defer {
      observing.cancel()
      for forwarder in forwarders { forwarder.cancel() }
      input.finish()
    }

    var latest: Value?
    for await event in events {
      switch event {
      case .refresh:
        observing.cancel()
        generation += 1
        observing = startObserving(observe(), generation: generation, into: input)
      case .value(let valueGeneration, let value):
        guard valueGeneration == generation, value != latest else { continue }
        latest = value
        continuation.yield(value)
      case .failure(let failureGeneration, let error):
        guard failureGeneration == generation else { continue }
        continuation.finish(throwing: error)
        return
      }
    }
    continuation.finish()
  }

  private static func startObserving(
    _ observation: AsyncValueObservation<Value>,
    generation: Int,
    into input: AsyncStream<Event>.Continuation
  ) -> Task<Void, Never> {
    Task {
      do {
        for try await value in observation {
          input.yield(.value(generation: generation, value))
        }
      } catch {
        input.yield(.failure(generation: generation, error))
      }
    }
  }
}

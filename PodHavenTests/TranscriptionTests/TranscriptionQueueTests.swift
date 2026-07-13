// Copyright Justin Bishop, 2026

import FactoryKit
import Testing

@testable import PodHaven

@Suite("of TranscriptionQueue", .container)
struct TranscriptionQueueTests {
  private let queue = Container.shared.transcriptionQueue()

  private func id(_ value: Int64) -> Episode.ID { Episode.ID(rawValue: value) }

  @Test("enqueue appends in order and ignores duplicates")
  func enqueueOrderAndDedup() {
    queue.enqueue(id(1))
    queue.enqueue(id(2))
    queue.enqueue(id(1))
    #expect(queue.episodeIDs == [id(1), id(2)])
  }

  @Test("remove drops the episode and clears its progress")
  func removeDropsEpisode() {
    for episodeID in [id(1), id(2)] {
      queue.enqueue(episodeID)
    }
    queue.setProgress(0.5, for: id(1))
    queue.remove(id(1))
    #expect(queue.episodeIDs == [id(2)])
    #expect(queue.progress[id(1)] == nil)
  }

  @Test("stream yields one queue head at a time")
  func streamYieldsOneHeadAtATime() async {
    var iterator = queue.makeStream().makeAsyncIterator()
    defer { queue.finishStream() }
    queue.enqueue(id(1))
    queue.enqueue(id(2))

    #expect(await iterator.next() == id(1))

    queue.remove(id(1))
    #expect(await iterator.next() == id(2))
  }

  @Test("a new stream replays an interrupted head")
  func newStreamReplaysInterruptedHead() async {
    queue.enqueue(id(1))
    var firstIterator = queue.makeStream().makeAsyncIterator()
    #expect(await firstIterator.next() == id(1))
    queue.finishStream()

    var resumedIterator = queue.makeStream().makeAsyncIterator()
    defer { queue.finishStream() }
    #expect(await resumedIterator.next() == id(1))
  }

  @Test("status prefers transcribed, then transcribing, then queued, then failed")
  func statusDerivation() {
    #expect(queue.status(for: id(9), hasTranscript: false) == .none)

    queue.enqueue(id(1))
    #expect(queue.status(for: id(1), hasTranscript: true) == .transcribed)
    #expect(queue.status(for: id(1), hasTranscript: false) == .queued)

    queue.setProgress(0.25, for: id(1))
    #expect(queue.status(for: id(1), hasTranscript: false) == .transcribing(0.25))

    queue.fail(id(2))
    #expect(queue.status(for: id(2), hasTranscript: false) == .failed)
  }

  @Test("enqueue clears a prior failure for the same episode")
  func enqueueClearsFailure() {
    queue.fail(id(1))
    #expect(queue.failed.contains(id(1)))

    queue.enqueue(id(1))
    #expect(!queue.failed.contains(id(1)))
    #expect(queue.episodeIDs == [id(1)])
  }
}

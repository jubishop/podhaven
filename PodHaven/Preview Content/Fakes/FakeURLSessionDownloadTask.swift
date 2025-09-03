#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation

actor FakeURLSessionDownloadTask: DownloadingTask {
  let taskID: DownloadTaskID

  private var resumed = false
  private var cancelled = false

  init() {
    taskID = DownloadTaskID(Int.random(in: 1_000_000...9_999_999))
  }

  nonisolated func resume() {
    Task { await markAsResumed() }
  }

  nonisolated func cancel() {
    Task { await markAsCancelled() }
  }

  func assertResumed(_ resumed: Bool = true) {
    Assert.precondition(
      self.resumed == resumed,
      "Expected resumed to be \(resumed) but was \(self.resumed)"
    )
  }

  func assertCancelled(_ cancelled: Bool = true) {
    Assert.precondition(
      self.cancelled == cancelled,
      "Expected cancelled to be \(cancelled) but was \(self.cancelled)"
    )
  }

  private func markAsResumed() {
    resumed = true
  }

  private func markAsCancelled() {
    cancelled = true
  }
}
#endif

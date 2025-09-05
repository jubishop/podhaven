#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation

actor FakeURLSessionDownloadTask: DownloadingTask {
  let taskID: URLSessionDownloadTask.ID

  var isResumed = false
  var isCancelled = false

  init() {
    taskID = URLSessionDownloadTask.ID(Int.random(in: 1_000_000...9_999_999))
  }

  nonisolated func resume() {
    Task { await markAsResumed() }
  }

  nonisolated func cancel() {
    Task { await markAsCancelled() }
  }

  func assertResumed(_ resumed: Bool = true) {
    Assert.precondition(
      isResumed == resumed,
      "Expected resumed to be \(resumed) but was \(isResumed)"
    )
  }

  func assertCancelled(_ cancelled: Bool = true) {
    Assert.precondition(
      isCancelled == cancelled,
      "Expected cancelled to be \(cancelled) but was \(isCancelled)"
    )
  }

  private func markAsResumed() {
    isResumed = true
  }

  private func markAsCancelled() {
    isCancelled = true
  }
}
#endif

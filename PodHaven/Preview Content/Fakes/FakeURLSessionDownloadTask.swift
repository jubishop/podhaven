#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation
import Tagged

actor FakeURLSessionDownloadTask: DownloadingTask {
  let taskID: URLSessionDownloadTask.ID

  let isResumed = ThreadSafe(false)
  let isCancelled = ThreadSafe(false)

  init() {
    taskID = URLSessionDownloadTask.ID(Int.random(in: 1_000_000...9_999_999))
  }

  nonisolated func resume() {
    isResumed(true)
  }

  nonisolated func cancel() {
    isCancelled(true)
  }

  func assertResumed(_ resumed: Bool = true) {
    Assert.precondition(
      isResumed() == resumed,
      "Expected resumed to be \(resumed) but was \(isResumed())"
    )
  }

  func assertCancelled(_ cancelled: Bool = true) {
    Assert.precondition(
      isCancelled() == cancelled,
      "Expected cancelled to be \(cancelled) but was \(isCancelled())"
    )
  }
}
#endif

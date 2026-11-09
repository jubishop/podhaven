// Copyright Justin Bishop, 2026

import Foundation
import Testing

// Measures the CPU time of the calling thread, which load from other tests and
// processes can't inflate the way it inflates wall-clock time. The work must
// finish on the thread that started it.
enum ThreadCPUTime {
  static func measure<T>(
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () async throws -> T
  ) async throws -> (result: T, duration: Duration) {
    let thread = pthread_self()
    let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    let result = try await body()
    let end = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    try #require(
      pthread_equal(thread, pthread_self()) != 0,
      "The measured work finished on another thread",
      sourceLocation: sourceLocation
    )
    return (result, .nanoseconds(end - start))
  }
}

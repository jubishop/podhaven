// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
@_spi(Private) import Sentry

@testable import PodHaven

extension Container {
  var fakeSentryFeedbackCapture: Factory<FakeSentryFeedbackCapture> {
    Factory(self) { FakeSentryFeedbackCapture() }.scope(.cached)
  }
}

final class FakeSentryFeedbackCapture {
  private let capturedFeedbacks = ThreadSafe<[CapturedSentryFeedback]>([])
  private let submissionResult = ThreadSafe<FeedbackSubmissionResult>(.queued)

  var feedbacks: [CapturedSentryFeedback] {
    capturedFeedbacks()
  }

  func submit(_ feedback: SentryFeedback) -> FeedbackSubmissionResult {
    let result = submissionResult()
    guard result == .queued else { return result }
    let serialized = feedback.serialize()
    let capturedFeedback = CapturedSentryFeedback(
      message: serialized["message"] as? String,
      name: serialized["name"] as? String,
      email: serialized["contact_email"] as? String,
      source: serialized["source"] as? String,
      attachments: feedback.attachmentsForEnvelope()
        .map {
          CapturedSentryAttachment(
            filename: $0.filename,
            path: $0.path,
            contentType: $0.contentType,
            data: $0.data
          )
        }
    )
    capturedFeedbacks { $0.append(capturedFeedback) }
    return result
  }

  func setSubmissionResult(_ result: FeedbackSubmissionResult) {
    submissionResult(result)
  }
}

struct CapturedSentryFeedback: Sendable {
  let message: String?
  let name: String?
  let email: String?
  let source: String?
  let attachments: [CapturedSentryAttachment]
}

struct CapturedSentryAttachment: Sendable {
  let filename: String
  let path: String?
  let contentType: String?
  let data: Data?
}

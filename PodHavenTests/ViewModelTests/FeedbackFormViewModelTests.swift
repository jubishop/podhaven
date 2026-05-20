// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing
import UIKit

@testable import PodHaven

@Suite("of FeedbackFormViewModel tests", .container)
@MainActor final class FeedbackFormViewModelTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.fakeSentryFeedbackCapture) private var fakeSentryFeedbackCapture

  @Test("sendFeedback sends report and presents confirmation alert")
  func sendFeedbackSendsReportAndPresentsConfirmationAlert() throws {
    let viewModel = FeedbackFormViewModel()
    let screenshotData = try #require(Self.screenshotData())
    viewModel.message = "Please add folders."
    viewModel.name = "Justin"
    viewModel.email = "justin@example.com"
    viewModel.screenshotData.new(screenshotData)

    viewModel.sendFeedback()

    #expect(fakeSentryFeedbackCapture.feedbacks.count == 1)
    let feedback = try #require(fakeSentryFeedbackCapture.feedbacks.first)
    #expect(feedback.message == "Please add folders.")
    #expect(feedback.name == "Justin")
    #expect(feedback.email == "justin@example.com")
    #expect(feedback.source == "custom")

    let attachments = feedback.attachments
    #expect(attachments.map(\.filename) == ["log.ndjson", "widget-log.ndjson", "screenshot.png"])
    #expect(attachments[0].path == AppInfo.logFileURL.path)
    #expect(attachments[1].path == WidgetInfo.logFileURL.path)
    #expect(attachments[2].contentType == "image/png")
    #expect(attachments[2].data == UIImage(data: screenshotData)?.pngData())
    #expect(alert.config?.title == "Feedback Sent")
  }

  private static func screenshotData() -> Data? {
    UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
      .image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
      }
      .pngData()
  }
}

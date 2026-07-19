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

  @Test("sendFeedback sends report, multiple photos, and confirmation")
  func sendFeedbackSendsReportAndPresentsConfirmationAlert() throws {
    let viewModel = FeedbackFormViewModel()
    let firstPhotoData = try #require(Self.photoData(color: .red))
    let secondPhotoData = try #require(Self.photoData(color: .blue))
    viewModel.message = "Please add folders."
    viewModel.name = "Justin"
    viewModel.email = "justin@example.com"
    viewModel.photoData.new([firstPhotoData, secondPhotoData])

    viewModel.sendFeedback()

    #expect(fakeSentryFeedbackCapture.feedbacks.count == 1)
    let feedback = try #require(fakeSentryFeedbackCapture.feedbacks.first)
    #expect(feedback.message == "Please add folders.")
    #expect(feedback.name == "Justin")
    #expect(feedback.email == "justin@example.com")
    #expect(feedback.source == "custom")

    let attachments = feedback.attachments
    #expect(
      attachments.map(\.filename) == [
        "log.ndjson",
        "widget-log.ndjson",
        "screenshot.jpg",
        "screenshot-2.jpg",
      ]
    )
    #expect(attachments[0].path == AppInfo.logFileURL.path)
    #expect(attachments[1].path == WidgetInfo.logFileURL.path)
    #expect(attachments[2].contentType == "image/jpeg")
    #expect(attachments[2].data == firstPhotoData)
    #expect(attachments[3].contentType == "image/jpeg")
    #expect(attachments[3].data == secondPhotoData)
    #expect(alert.config?.title == "Feedback Sent")
  }

  private static func photoData(color: UIColor) -> Data? {
    UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
      .image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
      }
      .jpegData(compressionQuality: 0.9)
  }
}

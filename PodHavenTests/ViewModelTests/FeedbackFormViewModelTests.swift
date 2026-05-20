// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of FeedbackFormViewModel tests", .container)
@MainActor final class FeedbackFormViewModelTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.feedbackSender) private var feedbackSender

  private var fakeFeedbackSender: FakeFeedbackSender { feedbackSender as! FakeFeedbackSender }

  @Test("sendFeedback sends report and presents confirmation alert")
  func sendFeedbackSendsReportAndPresentsConfirmationAlert() throws {
    let viewModel = FeedbackFormViewModel()
    let screenshotData = Data([1, 2, 3])
    viewModel.message = "Please add folders."
    viewModel.name = "Justin"
    viewModel.email = "justin@example.com"
    viewModel.screenshotData.new(screenshotData)

    viewModel.sendFeedback()

    #expect(fakeFeedbackSender.reports.count == 1)
    let report = try #require(fakeFeedbackSender.reports.first)
    #expect(report.message == "Please add folders.")
    #expect(report.name == "Justin")
    #expect(report.email == "justin@example.com")
    #expect(report.screenshotData == screenshotData)
    #expect(alert.config?.title == "Feedback Sent")
  }
}

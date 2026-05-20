// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

final class FakeFeedbackSender: FeedbackSending {
  private(set) var reports: [FeedbackReport] = []

  func send(_ report: FeedbackReport) {
    reports.append(report)
  }
}

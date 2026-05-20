// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Sentry
import UIKit

protocol FeedbackSending {
  func send(_ report: FeedbackReport)
}

extension Container {
  var feedbackSender: Factory<any FeedbackSending> {
    Factory(self) { SentryFeedbackSender() }.scope(.cached)
  }
}

struct FeedbackReport {
  let message: String
  let name: String?
  let email: String?
  let screenshotData: Data?
}

struct SentryFeedbackSender: FeedbackSending {
  func send(_ report: FeedbackReport) {
    var attachments: [Attachment] = [
      Attachment(path: AppInfo.logFileURL.path, filename: "log.ndjson"),
      Attachment(path: WidgetInfo.logFileURL.path, filename: "widget-log.ndjson"),
    ]
    if let data = report.screenshotData,
      let pngData = UIImage(data: data)?.pngData()
    {
      attachments.append(
        Attachment(data: pngData, filename: "screenshot.png", contentType: "image/png")
      )
    }

    SentrySDK.capture(
      feedback: .init(
        message: report.message,
        name: report.name,
        email: report.email,
        source: .custom,
        attachments: attachments
      )
    )
  }
}

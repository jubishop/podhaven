// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of WidgetInfo tests", .container)
struct WidgetInfoTests {
  @Test("persists the extension build and timeline-request time synchronously")
  func persistsExtensionAcknowledgmentSynchronously() throws {
    let requestDate = Date(timeIntervalSince1970: 1_800_000_000)
    let dateProvider = Container.shared.dateProvider() as! FakeDate
    dateProvider.freeze(at: requestDate)

    let acknowledgment = try WidgetInfo.recordExtensionTimelineRequest()
    let persisted = try WidgetInfo.readExtensionAcknowledgment()

    #expect(acknowledgment.buildNumber == AppInfo.buildNumber)
    #expect(acknowledgment.latestTimelineRequestAt == requestDate)
    #expect(persisted == acknowledgment)
    #expect(Container.shared.fileManager().fileExists(at: WidgetInfo.extensionAcknowledgmentURL))
  }
}

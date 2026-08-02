// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of WidgetInfo tests", .container)
struct WidgetInfoTests {
  @Test("distinguishes extension initialization from timeline requests")
  func distinguishesInitializationFromTimelineRequests() throws {
    let initializationDate = Date(timeIntervalSince1970: 1_800_000_000)
    let dateProvider = Container.shared.dateProvider() as! FakeDate
    dateProvider.freeze(at: initializationDate)

    let initialization = try WidgetInfo.recordExtensionInitialization()
    let persistedInitialization = try WidgetInfo.readExtensionAcknowledgment()

    #expect(initialization.buildNumber == AppInfo.buildNumber)
    #expect(initialization.initializedAt == initializationDate)
    #expect(initialization.latestTimelineRequestAt == nil)
    #expect(persistedInitialization == initialization)

    let requestDate = initializationDate.addingTimeInterval(30)
    dateProvider.freeze(at: requestDate)

    let request = try WidgetInfo.recordExtensionTimelineRequest()
    let persistedRequest = try WidgetInfo.readExtensionAcknowledgment()

    #expect(request.buildNumber == AppInfo.buildNumber)
    #expect(request.timelineRequestAt == requestDate)
    #expect(persistedRequest?.initializedAt == initializationDate)
    #expect(persistedRequest?.latestTimelineRequestAt == requestDate)
    #expect(Container.shared.fileManager().fileExists(at: WidgetInfo.extensionAcknowledgmentURL))
  }
}

// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Testing

@testable import PodHaven

@Suite("of unexpected remote command event tests", .container)
@MainActor struct UnexpectedRemoteCommandEventTests {
  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }

  @Test(
    "remote commands log and reject an unexpected event type",
    arguments: FakeMPRemoteCommandCenter.TypedEventCommand.allCases
  )
  func remoteCommandsRejectUnexpectedEventType(
    command: FakeMPRemoteCommandCenter.TypedEventCommand
  ) {
    LogCapture.withSink { sink in
      CommandCenter.registerRemoteCommandHandlers()

      let status = mpRemoteCommandCenter.fire(FakeMPRemoteCommandEvent(), at: command)

      #expect(status == .commandFailed)
      let captured = sink.captured()
      #expect(
        captured.contains { $0.level == .warning && $0.message.contains("\(command)") },
        "Expected a warning naming \(command)"
      )
      #expect(!captured.contains { $0.message.hasPrefix("Remote command received") })
    }
  }
}

// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import Testing

@testable import PodHaven

@Suite("Silence diagnostic policy", .container)
struct SilenceDiagnosticPolicyTests {
  @Test("a later interruption preserves completed files and separates discarded progress")
  func completedAndDiscardedWork() throws {
    Container.shared.fakeContinuousClock().freeze()
    let entries = LogCapture.withSink { sink in
      let run = Container.shared.silenceDiagnostics().startRun(id: UUID(), background: true)
      run.beginAttempt(filename: "first", generation: "published")
      run.progress(processedSeconds: 30, totalSeconds: 30)
      run.finishAttempt(.published)
      run.beginAttempt(filename: "second", generation: "interrupted")
      run.progress(processedSeconds: 10, totalSeconds: 100)
      run.finish(expired: true)
      return sink.captured()
    }
    let summary = try #require(entries.last)
    for field in [
      "completedFiles=1", "publishedFiles=1", "processedAudioSeconds=40.0",
      "discardedAudioSeconds=10.0", "attemptAudioSeconds=10.0", "totalAudioSeconds=100.0",
      "backgroundExpired=true", "outcome=interrupted", "sessionBackgroundRuns=1",
    ] {
      #expect(summary.message.contains(field), "Missing field: \(field)")
    }
  }

  @Test("warning budget resets after its window and reports suppressed events")
  func warningBudget() throws {
    let clock = Container.shared.fakeContinuousClock()
    clock.freeze()
    let diagnostics = Container.shared.silenceDiagnostics()
    let entries = LogCapture.withSink { sink in
      for index in 0..<5 {
        let run = diagnostics.startRun(id: UUID(), background: true)
        run.beginAttempt(filename: "fixture", generation: "\(index)")
        clock.advance(by: .seconds(20))
        run.progress(processedSeconds: 5, totalSeconds: 5)
        run.finishAttempt(.published)
        run.finish(expired: false)
      }
      return sink.captured()
    }
    #expect(entries.filter { $0.level == .warning }.count == 6)
    let last = try #require(entries.last)
    #expect(last.level == .info)
    #expect(last.message.contains("sessionRuns=5"))
    #expect(last.message.contains("sessionCompletedRuns=5"))
    #expect(last.message.contains("sessionPublishedFiles=5"))
    #expect(last.message.contains("suppressedWarnings=4"))
    #expect(last.message.contains("warningSuppressed=true"))

    clock.advance(by: .minutes(15))
    let next = LogCapture.withSink { sink in
      let run = diagnostics.startRun(id: UUID(), background: true)
      run.beginAttempt(filename: "fixture", generation: "next")
      clock.advance(by: .seconds(20))
      run.progress(processedSeconds: 5, totalSeconds: 5)
      run.finishAttempt(.published)
      run.finish(expired: false)
      return sink.captured()
    }
    #expect(next.filter { $0.level == .warning }.count == 2)
    #expect(next.last?.message.contains("suppressedWarnings=4") == true)
  }

  @Test("repeated expiration reports aggregated discarded work and then ages out")
  func expirationWindow() throws {
    let clock = Container.shared.fakeContinuousClock()
    clock.freeze()
    let diagnostics = Container.shared.silenceDiagnostics()
    let entries = LogCapture.withSink { sink in
      for _ in 0..<3 {
        let run = diagnostics.startRun(id: UUID(), background: true)
        run.beginAttempt(filename: "fixture", generation: "same")
        run.progress(processedSeconds: 5, totalSeconds: 100)
        run.finish(expired: true)
        clock.advance(by: .seconds(1))
      }
      return sink.captured()
    }
    let warnings = entries.filter { $0.level == .warning }
    #expect(warnings.count == 1)
    let warning = try #require(warnings.first)
    #expect(warning.message.contains("expirationCount=3"))
    #expect(warning.message.contains("expirationDiscardedSeconds=15.0"))
    #expect(warning.message.contains("sessionDiscardedAudioSeconds=15.0"))
    #expect(warning.message.contains("sessionExpirations=3"))
    #expect(!warning.message.contains("previousExpiredRunID=none"))
    clock.advance(by: .minutes(15))
    let aged = LogCapture.withSink { sink in
      let run = diagnostics.startRun(id: UUID(), background: true)
      run.beginAttempt(filename: "fixture", generation: "same")
      run.progress(processedSeconds: 5, totalSeconds: 100)
      run.finish(expired: true)
      return sink.captured()
    }
    #expect(aged.allSatisfy { $0.level < .warning })
    #expect(aged.last?.message.contains("expirationCount=1") == true)
    #expect(aged.last?.message.contains("previousExpiredRunID=none") == true)
  }

  @Test("expiration history evicts old content after its bounded capacity")
  func expirationCapacity() {
    let clock = Container.shared.fakeContinuousClock()
    clock.freeze()
    let diagnostics = Container.shared.silenceDiagnostics()
    for index in 0..<65 {
      let run = diagnostics.startRun(id: UUID(), background: true)
      run.beginAttempt(filename: "fixture", generation: "\(index)")
      run.progress(processedSeconds: 5, totalSeconds: 100)
      run.finish(expired: true)
      clock.advance(by: .seconds(1))
    }
    let entries = LogCapture.withSink { sink in
      let run = diagnostics.startRun(id: UUID(), background: true)
      run.beginAttempt(filename: "fixture", generation: "0")
      run.progress(processedSeconds: 5, totalSeconds: 100)
      run.finish(expired: true)
      return sink.captured()
    }
    #expect(entries.last?.message.contains("expirationCount=1") == true)
    #expect(entries.last?.message.contains("previousExpiredRunID=none") == true)
  }

  @Test("only thermal interruption with discarded progress promotes a short run")
  func interruptionSeverity() throws {
    Container.shared.fakeContinuousClock().freeze()
    let diagnostics = Container.shared.silenceDiagnostics()
    let reasons: [SilenceAnalysisRun.StopReason] = [.lifecycle, .eligibility, .thermal]
    for reason in reasons {
      let entries = LogCapture.withSink { sink in
        let run = diagnostics.startRun(id: UUID(), background: false)
        run.beginAttempt(filename: "fixture", generation: UUID().uuidString)
        run.progress(processedSeconds: 2, totalSeconds: 100)
        if reason == .thermal { Container.shared.sharedState().setThermalPressure(.serious) }
        run.interrupt(reason)
        run.finish(expired: false)
        return sink.captured()
      }
      let summary = try #require(entries.last)
      #expect(summary.message.contains("stopReason=\(reason.rawValue)"))
      #expect(summary.message.contains("discardedAudioSeconds=2.0"))
      #expect(summary.level == (reason == .thermal ? .warning : .info))
    }
    let deferred = LogCapture.withSink { sink in
      let run = diagnostics.startRun(id: UUID(), background: true)
      run.interrupt(.thermal)
      run.finish(expired: false)
      return sink.captured()
    }
    #expect(deferred.last?.message.contains("outcome=deferred") == true)
    #expect(deferred.last?.level == .info)
  }

  @Test("CPU evidence is process-wide and unavailable sampling stays explicit")
  func cpuEvidence() throws {
    Container.shared.fakeContinuousClock().freeze()
    let cpu = ThreadSafe(ProcessCPUTime.seconds(10))
    Container.shared.processCPUTime.context(.test) { { cpu() } }.reset(.scope)
    let entries = LogCapture.withSink { sink in
      let run = Container.shared.silenceDiagnostics().startRun(id: UUID(), background: true)
      run.beginAttempt(filename: "fixture", generation: "cpu")
      cpu(.seconds(12))
      run.progress(processedSeconds: 1, totalSeconds: 1)
      run.finishAttempt(.published)
      run.finish(expired: false)
      return sink.captured()
    }
    let summary = try #require(entries.last)
    #expect(summary.message.contains("processCPUSeconds=2.0 cpuScope=process"))
    #expect(ProcessCPUTime.unavailable(22).elapsed(since: .seconds(10)) == "unavailable(errno:22)")
    #expect(ProcessCPUTime.seconds(10).elapsed(since: .unavailable(22)) == "unavailable(errno:22)")
    let handler = SentryLogHandler(label: Log.as("SilenceDiagnostics").label)
    #expect(handler.logLevel == .warning)
    #expect(summary.level < handler.logLevel)
  }
}

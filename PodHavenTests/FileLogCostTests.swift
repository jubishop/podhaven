// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Logging
import Testing

@testable import PodHaven

@Suite("Production file logging measurement", .container)
struct FileLogCostTests {
  @Test("compare the same accepted burst with production sink sizes")
  func measure() throws {
    Container.shared.fakeContinuousClock().freeze()
    for repetition in 0..<7 {
      for sync in repetition.isMultiple(of: 2) ? [true, false] : [false, true] {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = [
          directory.appendingPathComponent("full.ndjson"),
          directory.appendingPathComponent("recent.ndjson"),
        ]
        let built = ThreadSafe(0)
        let handlers = paths.enumerated()
          .map { index, path in
            var handler = FileLogHandler(
              label: "PodHaven/ProductionProbe",
              fileURL: path,
              maxFileSizeBytes: index == 0
                ? AppInfo.logMaxFileSizeBytes : AppInfo.recentLogMaxFileSizeBytes,
              targetFileSizeBytes: index == 0
                ? AppInfo.logTargetFileSizeBytes : AppInfo.recentLogTargetFileSizeBytes,
              historyPolicy: index == 0 ? .rolling : .preservePreviousSession,
              writeSynchronously: { _ in sync }
            )
            handler.metadataProvider = .init {
              built { $0 += 1 }
              return ["active": "true", "operation": "automatic-transition"]
            }
            return handler
          }
        let logger = Logger(label: "PodHaven/ProductionProbe") { _ in MultiplexLogHandler(handlers)
        }
        var samples: [Double] = []
        let cpuStart = ProcessCPUTime.sample()
        let start = ContinuousClock.now
        for index in 0..<100 {
          let callStart = ContinuousClock.now
          logger.debug(
            "transition phase=\(index) active=true count=2",
            file: "ProductionProbe.swift",
            function: "measure()",
            line: UInt(index % 10)
          )
          samples.append(ms(callStart.duration(to: .now)))
        }
        let caller = ms(start.duration(to: .now))
        let drainStart = ContinuousClock.now
        for path in paths { FileLogHandler.flush(fileURL: path) }
        let drain = ms(drainStart.duration(to: .now))
        let cpu = ProcessCPUTime.sample().elapsed(since: cpuStart)
        let data = try paths.map { try Data(contentsOf: $0) }
        #expect(built() == 200)
        #expect(data.allSatisfy { $0.split(separator: 0x0A).count == 100 })
        samples.sort()
        print(
          "PRODUCTION_FILE_PROBE repetition=\(repetition) sync=\(sync) records=100 sinks=2 caller_ms=\(caller) drain_ms=\(drain) cpu_s=\(cpu) p50_ms=\(samples[50]) p95_ms=\(samples[95]) p99_ms=\(samples[99]) bytes=\(data.reduce(0) { $0 + $1.count }) constructed=\(built())"
        )
      }
    }
  }

  private func ms(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
  }
}

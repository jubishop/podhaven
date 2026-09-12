// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Testing

@testable import PodHaven

@Suite("Worker task priorities", .container)
struct WorkerTaskPriorityTests {
  enum Process: String, CaseIterable, Sendable {
    case silenceAnalysis
    case transcription
    case embeddingComputation
    case publisherTranscripts
    case cachePurge
    case feedRefresh

    var priority: TaskPriority { self == .feedRefresh ? .utility : .background }

    func register() {
      switch self {
      case .silenceAnalysis: Container.shared.silenceProcessor().register()
      case .transcription: Container.shared.transcriptionProcessor().register()
      case .embeddingComputation: Container.shared.embeddingProcessor().register()
      case .publisherTranscripts: Container.shared.publisherTranscriptProcessor().register()
      case .cachePurge: Container.shared.cachePurger().register()
      case .feedRefresh: Container.shared.refreshScheduler().register()
      }
    }
  }

  enum PriorityOverride: CaseIterable, Sendable {
    case unchanged
    case high
    case inherit

    func resolve(_ requested: TaskPriority?) -> TaskPriority? {
      switch self {
      case .unchanged: requested
      case .high: .high
      case .inherit: nil
      }
    }
  }

  @Test(
    "OS grants request each process policy and apply the injected priority to execution",
    .timeLimit(.minutes(5)),
    arguments: Process.allCases,
    PriorityOverride.allCases
  )
  func backgroundExecution(process: Process, override: PriorityOverride) async throws {
    let fake = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    process.register()
    let requests = ThreadSafe<[TaskPriority?]>([])
    Container.shared.taskPriority
      .context(.test) {
        { requested in
          requests { $0.append(requested) }
          return override.resolve(requested)
        }
      }
      .reset(.scope)
    let expectedPriority = override.resolve(process.priority) ?? Task.currentPriority
    let task = try #require(
      fake.launchTask(withIdentifier: "\(AppInfo.bundleIdentifier).\(process.rawValue)")
    )
    defer { task.expire() }
    #expect(requests().first == process.priority)
    try await task.completed.wait()
    #expect(task.completionResults == [true])
    #expect(task.completionBasePriorities == [expectedPriority])
  }
}

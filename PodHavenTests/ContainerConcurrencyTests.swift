// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of concurrent test containers", .container)
struct ContainerConcurrencyTests {
  @Test("a dependency another test is still building does not block resolution in this test")
  func independentResolution() async throws {
    let other = Container()
    let building = ThreadSafe(false)
    let release = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let slowDependency = Factory<Int>(other, key: "slowDependency") {
      building(true)
      release.wait()
      return 0
    }
    Thread { _ = slowDependency() }.start()
    try await Wait.until({ building() }, { "The other container never began building" })

    let container = Container.shared
    let resolved = ThreadSafe(false)
    Thread {
      _ = container.sleeper()
      resolved(true)
    }
    .start()
    try await Wait.until(
      { resolved() },
      { "Resolution waited for a dependency another container was building" }
    )
  }

  @Test("concurrent first resolutions of a cached dependency build it once")
  func cachedBuiltOnce() async throws {
    let container = Container()
    let builds = ThreadSafe(0)
    let building = ThreadSafe(false)
    let release = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let dependency = Factory<UUID>(container, key: "cachedDependency") {
      let first = builds { count in
        count += 1
        return count == 1
      }
      if first {
        building(true)
        release.wait()
      }
      return UUID()
    }
    .scope(.cached)
    let resolved = ThreadSafe<[UUID]>([])
    Thread {
      let instance = dependency()
      resolved { $0.append(instance) }
    }
    .start()
    try await Wait.until({ building() }, { "The first resolution never began building" })

    let secondStarted = ThreadSafe(false)
    Thread {
      secondStarted(true)
      let instance = dependency()
      resolved { $0.append(instance) }
    }
    .start()
    try await Wait.until({ secondStarted() }, { "The second resolution never started" })
    do {
      try await Wait.until(
        maxAttempts: 100,
        delay: .milliseconds(5),
        { builds() > 1 },
        { "no second build was observed" }
      )
    } catch {
      // The timeout is the expected path while the first build holds the cached slot.
    }
    release.signal()
    try await Wait.until({ resolved().count == 2 }, { "Both resolutions must finish" })
    #expect(builds() == 1)
    #expect(Set(resolved()).count == 1)
  }
}

// Copyright Justin Bishop, 2026

@testable import PodHaven

final class FakeSentryLogger: SentryLogEmitting {
  struct Record {
    let severity: String
    let body: String
    let attributes: [String: Any]
  }
  private(set) var records: [Record] = []

  func trace(_ body: String, attributes: [String: Any]) {
    records.append(Record(severity: "trace", body: body, attributes: attributes))
  }
  func debug(_ body: String, attributes: [String: Any]) {
    records.append(Record(severity: "debug", body: body, attributes: attributes))
  }
  func info(_ body: String, attributes: [String: Any]) {
    records.append(Record(severity: "info", body: body, attributes: attributes))
  }
  func warn(_ body: String, attributes: [String: Any]) {
    records.append(Record(severity: "warning", body: body, attributes: attributes))
  }
  func error(_ body: String, attributes: [String: Any]) {
    records.append(Record(severity: "error", body: body, attributes: attributes))
  }
  func fatal(_ body: String, attributes: [String: Any]) {
    records.append(Record(severity: "fatal", body: body, attributes: attributes))
  }
}

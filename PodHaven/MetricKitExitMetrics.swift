// Copyright Justin Bishop, 2026

import Foundation
import Logging
import MetricKit

struct ForegroundExitCounts {
  let normalAppExit: Int
  let memoryResourceLimit: Int
  let badAccess: Int
  let abnormal: Int
  let illegalInstruction: Int
  let appWatchdog: Int

  init(
    normalAppExit: Int = 0,
    memoryResourceLimit: Int = 0,
    badAccess: Int = 0,
    abnormal: Int = 0,
    illegalInstruction: Int = 0,
    appWatchdog: Int = 0
  ) {
    self.normalAppExit = normalAppExit
    self.memoryResourceLimit = memoryResourceLimit
    self.badAccess = badAccess
    self.abnormal = abnormal
    self.illegalInstruction = illegalInstruction
    self.appWatchdog = appWatchdog
  }

  var directive: MetricKitLogDirective {
    let counts: [(String, Int)] = [
      ("memoryResourceLimit", memoryResourceLimit), ("badAccess", badAccess),
      ("abnormal", abnormal), ("illegalInstruction", illegalInstruction),
      ("appWatchdog", appWatchdog),
    ]
    let abnormalReasons = counts.filter { $0.1 > 0 }.map(\.0)
    var metadata = Logging.Logger.Metadata(
      uniqueKeysWithValues:
        counts.map { ($0.0, .string(String($0.1))) }
    )
    metadata["normalAppExit"] = .string(String(normalAppExit))
    return MetricKitLogDirective(
      level: abnormalReasons.isEmpty ? .info : .critical,
      message: abnormalReasons.isEmpty
        ? "MetricKit foreground-exit metrics — routine"
        : "MetricKit foreground-exit metrics — abnormal: \(abnormalReasons.joined(separator: ", "))",
      metadata: metadata
    )
  }
}

struct MetricKitReportingPeriod {
  let begin: Date
  let end: Date
  let latestApplicationVersion: String
  let applicationBuildVersion: String?
  let includesMultipleApplicationVersions: Bool

  var metadata: Logging.Logger.Metadata {
    let build: String
    if let applicationBuildVersion {
      build = String(applicationBuildVersion.prefix(64))
    } else {
      build = "unknown"
    }
    return [
      "metricKit.kind": "aggregate_exits",
      "metricKit.periodStart": .string(begin.ISO8601Format()),
      "metricKit.periodEnd": .string(end.ISO8601Format()),
      "metricKit.latestVersion": .string(String(latestApplicationVersion.prefix(64))),
      "metricKit.payloadBuild": .string(build),
      "metricKit.multipleVersions": .string(String(includesMultipleApplicationVersions)),
      "metricKit.attribution": "reporting_period",
    ]
  }
}

protocol MetricKitMetricReporting {
  var foregroundExitCounts: ForegroundExitCounts? { get }
  var backgroundExitCounts: BackgroundExitCounts? { get }
  var reportingPeriod: MetricKitReportingPeriod { get }
}

extension MXMetricPayload: MetricKitMetricReporting {
  var foregroundExitCounts: ForegroundExitCounts? {
    guard let data = applicationExitMetrics?.foregroundExitData else { return nil }
    return ForegroundExitCounts(
      normalAppExit: data.cumulativeNormalAppExitCount,
      memoryResourceLimit: data.cumulativeMemoryResourceLimitExitCount,
      badAccess: data.cumulativeBadAccessExitCount,
      abnormal: data.cumulativeAbnormalExitCount,
      illegalInstruction: data.cumulativeIllegalInstructionExitCount,
      appWatchdog: data.cumulativeAppWatchdogExitCount
    )
  }

  var backgroundExitCounts: BackgroundExitCounts? {
    guard let data = applicationExitMetrics?.backgroundExitData else { return nil }
    return BackgroundExitCounts(data)
  }

  var reportingPeriod: MetricKitReportingPeriod {
    MetricKitReportingPeriod(
      begin: timeStampBegin,
      end: timeStampEnd,
      latestApplicationVersion: latestApplicationVersion,
      applicationBuildVersion: metaData?.applicationBuildVersion,
      includesMultipleApplicationVersions: includesMultipleApplicationVersions
    )
  }
}

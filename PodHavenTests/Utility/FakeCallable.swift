// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

protocol MethodCalling: Sendable {
  var callOrder: Int { get }
  var methodName: String { get }
  var toString: String { get }
}

struct MethodCall<Parameters: Sendable>: MethodCalling {
  let callOrder: Int
  let methodName: String
  let parameters: Parameters
  var toString: String {
    "\(methodName)(\(parameters))"
  }
}

protocol FakeCallable: Actor {
  var callOrder: Int { get set }
  var callsByType: [ObjectIdentifier: [any MethodCalling]] { get set }
}

extension FakeCallable {
  // MARK: - Call Tracking

  func recordCall<Parameters: Sendable>(
    methodName: String,
    parameters: Parameters = ()
  ) {
    callOrder += 1
    let call = MethodCall(
      callOrder: callOrder,
      methodName: methodName,
      parameters: parameters
    )
    let key = ObjectIdentifier(MethodCall<Parameters>.self)
    callsByType[key, default: []].append(call)
  }

  func clearAllCalls() {
    callOrder = 0
    callsByType.removeAll()
  }

  var allCallsInOrder: [any MethodCalling] {
    callsByType.values
      .flatMap { $0 }
      .sorted { $0.callOrder < $1.callOrder }
  }

  // MARK: - Call Filtering

  func calls<T: MethodCalling>(of type: T.Type) -> [T] {
    let key = ObjectIdentifier(type)
    return (callsByType[key] as? [T]) ?? []
  }

  // MARK: - Assertion Helpers

  func expectCalls(methodName: String, count: Int = 1) throws -> [any MethodCalling] {
    let allCalls = callsByType.values.flatMap { $0 }
    let methodMatchingCalls = allCalls.filter { call in
      call.methodName == methodName
    }
    guard methodMatchingCalls.count == count else {
      throw TestError.unexpectedCallCount(
        expected: count,
        actual: methodMatchingCalls.count,
        type: methodName
      )
    }
    return methodMatchingCalls
  }

  func expectCall<Parameters: Sendable>(methodName: String, parameters: Parameters.Type)
    throws -> MethodCall<Parameters>
  {
    let call = try expectCalls(methodName: methodName).first!
    guard let typedCall = call as? MethodCall<Parameters> else {
      throw TestError.unexpectedCall(
        type: "MethodCall<\(String(describing: Parameters.self))>.\(methodName)",
        calls: [call.toString]
      )
    }
    return typedCall
  }

  func expectNoCall(methodName: String) throws {
    let allCalls = callsByType.values.flatMap { $0 }
    let methodMatchingCalls = allCalls.filter { call in call.methodName == methodName }
    guard methodMatchingCalls.isEmpty else {
      throw TestError.unexpectedCall(
        type: methodName,
        calls: methodMatchingCalls.map(\.toString)
      )
    }
  }
}

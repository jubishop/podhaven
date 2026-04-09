// Copyright Justin Bishop, 2026

import Foundation

protocol Embeddable: Sendable {
  func vector(for text: String) throws -> [Float]
  var revision: Int { get }
  var maximumInputLength: Int { get }
}

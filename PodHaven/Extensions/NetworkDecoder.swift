// Copyright Justin Bishop, 2025

import Foundation
import Network

extension NetworkDecoder {
  func decode<Response: Decodable>(_ data: Data) throws -> Response {
    try decode(Response.self, from: data)
  }
}

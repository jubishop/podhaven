// Copyright Justin Bishop, 2025

import Foundation
import NukeUI
import SwiftUI

protocol ImageFetchable: Sendable {
  func fetch(_ url: URL) async throws -> UIImage
}

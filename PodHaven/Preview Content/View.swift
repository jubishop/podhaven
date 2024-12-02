// Copyright Justin Bishop, 2024 

import Foundation
import SwiftUI

#if DEBUG
extension View {
  func forPreview() -> some View {
    self.environment(Navigation())
  }
}
#endif

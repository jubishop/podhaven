// Copyright Justin Bishop, 2024 

import Foundation
import SwiftUI

#if DEBUG
extension View {
  func environmentScaffolding() -> some View {
    self.environmentObject(Navigation())
  }
}
#endif

// Copyright Justin Bishop, 2026

import FactoryKit

extension Container {
  var bgTaskScheduler: Factory<any BGTaskScheduling> {
    Factory(self) { SystemBGTaskScheduler() }
  }
}

// Copyright Justin Bishop, 2026

import SwiftUI

struct ChartDiagnosticBoundary<Content: View>: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var instance = ChartProgressInstance()

  let input: ChartProgressInput
  @ViewBuilder let content: () -> Content

  var body: some View {
    GeometryReader { geometry in
      ChartDiagnosticContent(
        input: input,
        instance: instance,
        size: geometry.size,
        scene: scenePhase,
        content: content
      )
      .transaction { transaction in
        instance.record(input, scene: scenePhase, phase: .transaction, transaction: transaction)
      }
      .onAppear { instance.record(input, scene: scenePhase, phase: .appeared) }
      .onDisappear { instance.record(input, scene: scenePhase, phase: .disappeared) }
      .onChange(of: scenePhase) { _, phase in
        instance.record(input, scene: phase, phase: .scene)
      }
    }
  }
}

private struct ChartDiagnosticContent<Content: View>: View {
  let input: ChartProgressInput
  let instance: ChartProgressInstance
  let size: CGSize
  let scene: ScenePhase
  @ViewBuilder let content: () -> Content

  var body: some View {
    // Record before constructing Charts content; onChange runs after that boundary.
    instance.record(input, size: size, scene: scene, phase: .render)
    return content()
  }
}

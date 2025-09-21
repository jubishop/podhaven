// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct CustomProgressBar: View {
  @Environment(\.colorScheme) private var colorScheme
  @Namespace private var glassNamespace
  @Binding var value: Double
  @Binding var isDragging: Bool
  let range: ClosedRange<Double>
  let animationDuration: Double

  private var normalHeight: CGFloat { 3 }
  private var dragHeight: CGFloat { 8 }
  private var touchHeight: CGFloat { 36 }
  private var currentHeight: CGFloat { isDragging ? dragHeight : normalHeight }
  private var knobDiameter: CGFloat { isDragging ? 16 : 11 }

  private var progress: Double {
    guard range.upperBound > range.lowerBound else { return 0 }
    return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
  }

  private var clampedProgress: Double {
    guard progress.isFinite else { return 0 }
    return max(0, min(progress, 1))
  }

  var body: some View {
    GeometryReader { geometry in
      let progressWidth = max(0, CGFloat(clampedProgress) * geometry.size.width)
      let trackShape = Capsule(style: .continuous)

      GlassEffectContainer(spacing: dragHeight) {
        ZStack(alignment: .leading) {
          trackShape
            .frame(height: currentHeight)
            .glassEffect(trackGlass, in: trackShape)

          trackShape
            .frame(width: progressWidth, height: currentHeight)
            .glassEffect(progressGlass, in: trackShape)
            .glassEffectUnion(id: GlassID.active, namespace: glassNamespace)

          Circle()
            .frame(width: knobDiameter, height: knobDiameter)
            .offset(
              x: max(0, min(CGFloat(clampedProgress) * geometry.size.width, geometry.size.width))
                - knobDiameter / 2
            )
            .glassEffect(knobGlass, in: Circle())
            .glassEffectUnion(id: GlassID.active, namespace: glassNamespace)
            .allowsHitTesting(false)
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle().size(width: .infinity, height: touchHeight))
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { gestureValue in
              if !isDragging {
                isDragging = true
              }

              let clampedX = max(0, min(gestureValue.location.x, geometry.size.width))
              let newProgress = clampedX / geometry.size.width
              let newValue =
                range.lowerBound + newProgress * (range.upperBound - range.lowerBound)
              value = newValue
            }
            .onEnded { _ in
              isDragging = false
            }
        )
      }
    }
    .frame(height: dragHeight)
    .animation(.easeInOut(duration: animationDuration), value: isDragging)
  }
}

extension CustomProgressBar {
  private enum GlassID: Hashable {
    case active
  }

  private var trackGlass: Glass {
    Glass.regular
      .tint(trackTint)
  }

  private var progressGlass: Glass {
    Glass.regular
      .tint(Color.accentColor.opacity(colorScheme == .dark ? 0.45 : 0.35))
      .interactive()
  }

  private var knobGlass: Glass {
    Glass.regular
      .tint(Color.accentColor.opacity(colorScheme == .dark ? 0.35 : 0.28))
      .interactive()
  }

  private var trackTint: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.2)
      : Color.black.opacity(0.08)
  }
}

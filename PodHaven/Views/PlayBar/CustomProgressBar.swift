// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct CustomProgressBar: View {
  @Environment(\.colorScheme) private var colorScheme
  @Binding var value: Double
  @Binding var isDragging: Bool
  let range: ClosedRange<Double>
  let animationDuration: Double

  private var normalHeight: CGFloat { 4 }
  private var dragHeight: CGFloat { 12 }
  private var touchHeight: CGFloat { 44 }
  private var currentHeight: CGFloat { isDragging ? dragHeight : normalHeight }
  private var knobDiameter: CGFloat { isDragging ? 18 : 12 }

  private var progress: Double {
    guard range.upperBound > range.lowerBound else { return 0 }
    return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
  }

  private var clampedProgress: Double {
    guard progress.isFinite else { return 0 }
    return max(0, min(progress, 1))
  }

  private var trackFill: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.18)
      : Color.black.opacity(0.08)
  }

  private var progressFill: LinearGradient {
    LinearGradient(
      colors: [
        Color.accentColor.opacity(colorScheme == .dark ? 0.95 : 0.85),
        Color.accentColor.opacity(colorScheme == .dark ? 0.55 : 0.45),
      ],
      startPoint: .leading,
      endPoint: .trailing
    )
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        // Background track
        RoundedRectangle(cornerRadius: currentHeight / 2)
          .fill(trackFill)
          .frame(height: currentHeight)

        // Progress track
        RoundedRectangle(cornerRadius: currentHeight / 2)
          .fill(progressFill)
          .frame(width: max(0, CGFloat(progress) * geometry.size.width), height: currentHeight)
          .shadow(
            color: Color.accentColor.opacity(colorScheme == .dark ? 0.6 : 0.4),
            radius: isDragging ? 6 : 3,
            y: 0
          )

        Circle()
          .fill(Color.white)
          .frame(width: knobDiameter, height: knobDiameter)
          .overlay(
            Circle()
              .strokeBorder(trackFill.opacity(0.8), lineWidth: 1)
          )
          .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 4, y: 2)
          .offset(
            x: max(0, min(CGFloat(clampedProgress) * geometry.size.width, geometry.size.width))
              - knobDiameter / 2
          )
          .frame(maxWidth: .infinity, alignment: .leading)
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
    .frame(height: dragHeight)
    .animation(.easeInOut(duration: animationDuration), value: isDragging)
  }
}

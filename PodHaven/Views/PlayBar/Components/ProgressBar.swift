// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct ProgressBar: View {
  @Binding var value: Double
  @Binding var isDragging: Bool
  let range: ClosedRange<Double>
  let animationDuration: Double
  let normalHeight: CGFloat = 4
  let dragHeight: CGFloat = 12
  let touchHeight: CGFloat = 36

  private var currentHeight: CGFloat { isDragging ? dragHeight : normalHeight }

  private var progress: Double {
    guard range.upperBound > range.lowerBound else { return 0 }
    return (value.clamped(to: range) - range.lowerBound) / (range.upperBound - range.lowerBound)
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        // Background track
        RoundedRectangle(cornerRadius: currentHeight / 2)
          .fill(Color.white.opacity(0.3))
          .frame(height: currentHeight)

        // Progress track
        RoundedRectangle(cornerRadius: currentHeight / 2)
          .fill(Color.white)
          .frame(width: max(0, CGFloat(progress) * geometry.size.width), height: currentHeight)
      }
      .frame(maxHeight: .infinity, alignment: .center)
      .contentShape(Rectangle().size(width: .infinity, height: touchHeight))
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { gestureValue in
            if !isDragging {
              isDragging = true
            }

            let clampedX = gestureValue.location.x.clamped(to: 0...geometry.size.width)
            let newProgress = clampedX / geometry.size.width
            let newValue = range.lowerBound + (newProgress * (range.upperBound - range.lowerBound))
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

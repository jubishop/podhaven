// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct CustomProgressBar: View {
  @Binding var value: Double
  @Binding var isDragging: Bool
  let range: ClosedRange<Double>
  let animationDuration: Double

  @State private var dragOffset: CGFloat = 0
  @State private var barWidth: CGFloat = 0

  private var normalHeight: CGFloat { 4 }
  private var dragHeight: CGFloat { 12 }
  private var currentHeight: CGFloat { isDragging ? dragHeight : normalHeight }

  private var progress: Double {
    guard range.upperBound > range.lowerBound else { return 0 }
    return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
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
      .onAppear {
        barWidth = geometry.size.width
      }
      .onChange(of: geometry.size.width) { _, newWidth in
        barWidth = newWidth
      }
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { gestureValue in
            if !isDragging {
              isDragging = true
            }

            let clampedX = max(0, min(gestureValue.location.x, geometry.size.width))
            let newProgress = clampedX / geometry.size.width
            let newValue = range.lowerBound + newProgress * (range.upperBound - range.lowerBound)
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

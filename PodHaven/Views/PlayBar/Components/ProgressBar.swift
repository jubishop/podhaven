// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct ProgressBar: View {
  @Binding var value: Double
  @Binding var isDragging: Bool
  let range: ClosedRange<Double>
  let animationDuration: Double
  var tickMarks: [Double]?
  var maxPlaybackPosition: Double?
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

        // Tick marks
        if let tickMarks {
          ForEach(tickMarks, id: \.self) { position in
            tickMark(at: position, width: geometry.size.width)
          }
        }

        if let maxPlaybackPosition {
          maxPlaybackMarkerView(at: maxPlaybackPosition, width: geometry.size.width)
        }
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

  // MARK: - Tick Marks

  private func tickMark(at position: Double, width: CGFloat) -> some View {
    let markerWidth: CGFloat = 2
    let normalized = (position - range.lowerBound) / (range.upperBound - range.lowerBound)

    return RoundedRectangle(cornerRadius: markerWidth / 2)
      .fill(Color.white)
      .frame(width: markerWidth, height: currentHeight + 4)
      .position(x: CGFloat(normalized) * width, y: dragHeight / 2)
  }

  private func maxPlaybackMarkerView(at position: Double, width: CGFloat) -> some View {
    let clamped = position.clamped(to: range)
    let normalized = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    let diameter: CGFloat = currentHeight + 6

    return Circle()
      .fill(Color.accentColor)
      .overlay(Circle().stroke(Color.white, lineWidth: 1))
      .frame(width: diameter, height: diameter)
      .position(x: CGFloat(normalized) * width, y: dragHeight / 2)
  }
}

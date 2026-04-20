// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct ProgressBar: View {
  @Binding var value: Double
  @Binding var isDragging: Bool
  let range: ClosedRange<Double>
  let animationDuration: Double
  var tickMarks: [Double]?
  var maxPlaybackTime: Double?
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
          .fill(Color.primary.opacity(0.3))
          .frame(height: currentHeight)

        // Progress track
        RoundedRectangle(cornerRadius: currentHeight / 2)
          .fill(Color.primary)
          .frame(width: max(0, CGFloat(progress) * geometry.size.width), height: currentHeight)

        // Tick marks
        if let tickMarks {
          ForEach(tickMarks, id: \.self) { time in
            marker(at: time, containerWidth: geometry.size.width, color: .primary)
          }
        }

        if let maxPlaybackTime {
          marker(at: maxPlaybackTime, containerWidth: geometry.size.width, color: .accentColor)
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

  // MARK: - Markers

  private func marker(at time: Double, containerWidth: CGFloat, color: Color) -> some View {
    let markerWidth: CGFloat = 2
    let position = (time - range.lowerBound) / (range.upperBound - range.lowerBound)

    return RoundedRectangle(cornerRadius: markerWidth / 2)
      .fill(color)
      .frame(width: markerWidth, height: currentHeight + 4)
      .position(x: CGFloat(position) * containerWidth, y: dragHeight / 2)
  }
}

// MARK: - Previews

#if DEBUG
private struct ProgressBarSample: View {
  let title: String
  let duration: Double
  let tickMarks: [Double]?
  let maxPlaybackTime: Double?
  let forceDragging: Bool

  @State private var value: Double
  @State private var isDragging: Bool

  init(
    _ title: String,
    duration: Double = 600,
    value: Double = 0,
    tickMarks: [Double]? = nil,
    maxPlaybackTime: Double? = nil,
    forceDragging: Bool = false
  ) {
    self.title = title
    self.duration = duration
    self.tickMarks = tickMarks
    self.maxPlaybackTime = maxPlaybackTime
    self.forceDragging = forceDragging
    self._value = State(initialValue: value)
    self._isDragging = State(initialValue: forceDragging)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.primary)

      ProgressBar(
        value: $value,
        isDragging: $isDragging,
        range: 0...duration,
        animationDuration: 0.15,
        tickMarks: tickMarks,
        maxPlaybackTime: maxPlaybackTime
      )

      HStack {
        Text("\(Int(value))s")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer()
        Text("\(Int(duration))s")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct ProgressBarPreviewGallery: View {
  var body: some View {
    ZStack {
      Color(.systemBackground).ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Group {
            sectionHeader("Plain progress")
            ProgressBarSample("empty", value: 0)
            ProgressBarSample("25%", value: 150)
            ProgressBarSample("halfway", value: 300)
            ProgressBarSample("almost done", value: 580)
          }

          sectionDivider

          Group {
            sectionHeader("Chapters (tick marks)")
            ProgressBarSample(
              "4 chapters, start of playback",
              value: 10,
              tickMarks: [60, 180, 360, 500]
            )
            ProgressBarSample(
              "4 chapters, mid-playback",
              value: 240,
              tickMarks: [60, 180, 360, 500]
            )
          }

          sectionDivider

          Group {
            sectionHeader("Max-playback marker")
            ProgressBarSample(
              "peak just ahead (~25s)",
              value: 150,
              maxPlaybackTime: 175
            )
            ProgressBarSample(
              "peak far ahead",
              value: 100,
              maxPlaybackTime: 420
            )
            ProgressBarSample(
              "peak near start (edge)",
              value: 5,
              maxPlaybackTime: 30
            )
            ProgressBarSample(
              "peak near end (edge)",
              value: 300,
              maxPlaybackTime: 595
            )
          }

          sectionDivider

          Group {
            sectionHeader("Chapters + max marker together")
            ProgressBarSample(
              "peak between ticks",
              value: 80,
              tickMarks: [60, 180, 360, 500],
              maxPlaybackTime: 260
            )
            ProgressBarSample(
              "peak overlapping a tick",
              value: 80,
              tickMarks: [60, 180, 360, 500],
              maxPlaybackTime: 180
            )
            ProgressBarSample(
              "dense chapters + marker",
              value: 200,
              tickMarks: stride(from: 30.0, through: 570.0, by: 30.0).map { $0 },
              maxPlaybackTime: 450
            )
          }

          sectionDivider

          Group {
            sectionHeader("Dragging state (thicker bar)")
            ProgressBarSample(
              "dragging, no marker",
              value: 260,
              forceDragging: true
            )
            ProgressBarSample(
              "dragging, with chapters + marker",
              value: 260,
              tickMarks: [60, 180, 360, 500],
              maxPlaybackTime: 420,
              forceDragging: true
            )
          }
        }
        .padding(16)
      }
    }
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.headline)
      .foregroundStyle(.primary)
  }

  private var sectionDivider: some View {
    Divider().overlay(.secondary.opacity(0.4))
  }
}

#Preview("ProgressBar Gallery") {
  ProgressBarPreviewGallery()
}
#endif

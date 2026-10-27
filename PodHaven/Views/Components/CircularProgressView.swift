// Copyright Justin Bishop, 2025

import OrderedCollections
import SwiftUI

struct CircularProgressView: View {
  private let sectors: OrderedDictionary<Color, ProgressRingSector>
  private let innerRadiusRatio: Double

  init(
    totalAmount: Double = 1,
    colorAmounts: OrderedDictionary<Color, Double>,
    innerRadiusRatio: Double = 0.5
  ) {
    sectors = ProgressRingSector.sectors(total: totalAmount, amounts: colorAmounts)
    self.innerRadiusRatio = innerRadiusRatio
  }

  var body: some View {
    Canvas { context, size in
      let rect = CGRect(origin: .zero, size: size)
      for (color, sector) in sectors {
        let path = sector.path(in: rect, innerRadiusRatio: innerRadiusRatio)
        guard !path.isEmpty else { continue }
        context.fill(path, with: .style(color.gradient.in(path.cgPath.boundingBoxOfPath)))
      }
    }
    .aspectRatio(1, contentMode: .fit)
  }
}

// Fractions of the circle, clockwise from the top.
struct ProgressRingSector {
  let start: Double
  let end: Double

  static func sectors(
    total: Double,
    amounts: OrderedDictionary<Color, Double>
  ) -> OrderedDictionary<Color, ProgressRingSector> {
    let values = amounts.values.map { $0.isFinite && $0 > 0 ? $0 : 0 }
    let validTotal = total.isFinite && total > 0 ? total : 0
    // Dividing by the largest input first keeps the sum finite.
    let scale = max(validTotal, values.max() ?? 0)
    guard scale > 0 else { return [:] }

    let normalized = values.map { $0 / scale }
    let circle = max(validTotal / scale, normalized.reduce(0, +))
    var sectors: OrderedDictionary<Color, ProgressRingSector> = [:]
    var start = 0.0
    for (color, amount) in zip(amounts.keys, normalized) {
      let end = min(start + amount / circle, 1)
      guard end > start else { continue }
      sectors[color] = ProgressRingSector(start: start, end: end)
      start = end
    }
    return sectors
  }

  func path(in rect: CGRect, innerRadiusRatio: Double) -> Path {
    var path = Path()
    let outerRadius = Double(min(rect.width, rect.height)) / 2
    guard outerRadius.isFinite, outerRadius > 0, start.isFinite, end.isFinite else { return path }
    let from = min(max(start, 0), 1)
    let to = min(max(end, 0), 1)
    guard to > from else { return path }

    let center = CGPoint(x: rect.midX, y: rect.midY)
    let innerRadius =
      innerRadiusRatio.isFinite ? outerRadius * min(max(innerRadiusRatio, 0), 1) : 0
    if to - from >= 1 {
      path.addArc(
        center: center,
        radius: outerRadius,
        startAngle: .zero,
        endAngle: .radians(2 * .pi),
        clockwise: false
      )
      path.closeSubpath()
      guard innerRadius > 0 else { return path }
      path.move(to: CGPoint(x: center.x + innerRadius, y: center.y))
      path.addArc(
        center: center,
        radius: innerRadius,
        startAngle: .radians(2 * .pi),
        endAngle: .zero,
        clockwise: true
      )
      path.closeSubpath()
      return path
    }

    // Matches the former Charts angularInset: parallel-edged gaps that narrow on small rings.
    let edgeInset = min(max(outerRadius / 18, 1), 2)
    guard edgeInset < outerRadius else { return path }
    let sweep = (to - from) * 2 * .pi
    let startAngle = from * 2 * .pi - .pi / 2
    let endAngle = to * 2 * .pi - .pi / 2
    let outerInset = asin(edgeInset / outerRadius)
    guard sweep > 2 * outerInset else { return path }

    path.addArc(
      center: center,
      radius: outerRadius,
      startAngle: .radians(startAngle + outerInset),
      endAngle: .radians(endAngle - outerInset),
      clockwise: false
    )
    let innerEdge = max(innerRadius, edgeInset)
    let innerInset = asin(edgeInset / innerEdge)
    if sweep > 2 * innerInset {
      path.addArc(
        center: center,
        radius: innerEdge,
        startAngle: .radians(endAngle - innerInset),
        endAngle: .radians(startAngle + innerInset),
        clockwise: true
      )
    } else {
      // The gap edges meet before reaching the inner radius.
      let apex = edgeInset / sin(sweep / 2)
      let bisector = (startAngle + endAngle) / 2
      path.addLine(
        to: CGPoint(x: center.x + apex * cos(bisector), y: center.y + apex * sin(bisector))
      )
    }
    path.closeSubpath()
    return path
  }
}

#if DEBUG
#Preview {
  @Previewable @State var greenAmount: Double = 30
  @Previewable @State var redAmount: Double = 50
  @Previewable @State var blueAmount: Double = 10
  @Previewable @State var totalAmount: Double = 100

  VStack {
    CircularProgressView(
      totalAmount: totalAmount,
      colorAmounts: [
        .green: greenAmount, .red: redAmount, .blue: blueAmount,
      ]
    )
    .padding()

    Text(
      """
      Green: \(Int(greenAmount)), \
      Red: \(Int(redAmount)), \
      Blue: \(Int(blueAmount))
      """
    )

    Slider(value: $greenAmount, in: 0...totalAmount)
      .padding()
      .accentColor(.green)

    Slider(value: $redAmount, in: 0...totalAmount)
      .padding()
      .accentColor(.red)

    Slider(value: $blueAmount, in: 0...totalAmount)
      .padding()
      .accentColor(.blue)

    Slider(value: $totalAmount, in: 50...200)
      .padding()
      .accentColor(.gray)
  }
}

#Preview("Progress boundaries at row, detail, and full-width sizes") {
  let opmlStates: [(total: Double, amounts: OrderedDictionary<Color, Double>)] = [
    (10, [.green: 3, .blue: 2, .red: 1]),
    (10, [.green: 3, .blue: 0, .red: 1]),
    (6, [.green: 3, .blue: 2, .red: 1]),
    (4, [.green: 4, .blue: 1, .red: 1]),
  ]

  ScrollView {
    VStack(spacing: 12) {
      ForEach([0.0, 0.000001, 0.01, 0.05, 0.5, 0.99993, 1.0, 1.1], id: \.self) { progress in
        HStack {
          Text(progress, format: .number)
          Spacer()
          ForEach([12.0, 28.0], id: \.self) { size in
            CircularProgressView(colorAmounts: [.blue: progress], innerRadiusRatio: 0.4)
              .frame(width: size, height: size)
          }
        }
      }
      ForEach(opmlStates.indices, id: \.self) { index in
        let state = opmlStates[index]
        HStack {
          ForEach([12.0, 28.0], id: \.self) { size in
            CircularProgressView(totalAmount: state.total, colorAmounts: state.amounts)
              .frame(width: size, height: size)
          }
          CircularProgressView(totalAmount: state.total, colorAmounts: state.amounts)
            .frame(maxWidth: .infinity)
        }
      }
    }
    .padding()
  }
}
#endif

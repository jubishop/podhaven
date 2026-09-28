// Copyright Justin Bishop, 2025

import Charts
import OrderedCollections
import SwiftUI

struct CircularProgressView: View {
  private let totalAmount: Double
  private let colorAmounts: OrderedDictionary<Color, Double>
  private let innerRadiusRatio: Double
  private let source: ChartProgressInput.Source
  private let numerator: Double?
  private let denominator: Double?
  private let waitingCount: Int?
  private let angularInset: CGFloat?
  private var totalColorAmount: Double { colorAmounts.values.reduce(0, +) }
  private var diagnosticAngularInset: Double? {
    if let angularInset { return Double(angularInset) }
    return nil
  }

  init(
    totalAmount: Double = 1,
    colorAmounts: OrderedDictionary<Color, Double>,
    innerRadiusRatio: Double = 0.5,
    angularInset: CGFloat? = 2,
    source: ChartProgressInput.Source = .preview,
    numerator: Double? = nil,
    denominator: Double? = nil,
    waitingCount: Int? = nil
  ) {
    self.totalAmount = totalAmount
    self.colorAmounts = colorAmounts
    self.innerRadiusRatio = innerRadiusRatio
    self.source = source
    self.numerator = numerator
    self.denominator = denominator
    self.waitingCount = waitingCount
    self.angularInset = angularInset
  }

  var body: some View {
    ChartDiagnosticBoundary(
      input: ChartProgressInput(
        source: source,
        total: totalAmount,
        values: Array(colorAmounts.values),
        sectorKeys: colorAmounts.keys.map(\.hashValue),
        innerRadiusRatio: innerRadiusRatio,
        angularInset: diagnosticAngularInset,
        numerator: numerator,
        denominator: denominator,
        waitingCount: waitingCount
      )
    ) {
      Chart {
        ForEach(Array(colorAmounts.keys), id: \.self) { color in
          let amount = colorAmounts[color] ?? 0
          SectorMark(
            angle: .value("Value", amount),
            innerRadius: .ratio(innerRadiusRatio),
            angularInset: angularInset
          )
          .foregroundStyle(color.gradient)
        }
        if totalAmount > totalColorAmount {
          SectorMark(angle: .value("Value", totalAmount - totalColorAmount))
            .foregroundStyle(.opacity(0))
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
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
#Preview("Progress boundaries at row and detail sizes") {
  VStack(spacing: 12) {
    ForEach([0.0, 0.000001, 0.5, 1.0, 1.1], id: \.self) { progress in
      HStack {
        Text(progress, format: .number)
        ForEach([12.0, 28.0], id: \.self) { size in
          CircularProgressView(colorAmounts: [.blue: progress], innerRadiusRatio: 0.4)
            .frame(width: size, height: size)
        }
      }
    }
    CircularProgressView(totalAmount: 3, colorAmounts: [.green: 0, .blue: 1, .red: 1])
      .frame(width: 100, height: 100)
  }
  .padding()
}
#endif

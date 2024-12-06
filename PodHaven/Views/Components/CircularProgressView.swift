// Copyright Justin Bishop, 2024

import OrderedCollections
import SwiftUI

struct CircularProgressView: View {
  struct PieWedge: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
      var path = Path()
      let center = CGPoint(x: rect.midX, y: rect.midY)
      let radius = min(rect.width, rect.height) / 2
      path.move(to: center)
      path.addArc(
        center: center,
        radius: radius,
        startAngle: startAngle,
        endAngle: endAngle,
        clockwise: false
      )
      path.closeSubpath()
      return path
    }
  }

  private let totalAmount: Double
  private let colorAmounts: OrderedDictionary<Color, Double>
  private var totalColorAmount: Double {
    colorAmounts.values.reduce(0, +)
  }
  init(
    totalAmount: Double = 100,
    colorAmounts: OrderedDictionary<Color, Double>
  ) {
    self.totalAmount = totalAmount
    self.colorAmounts = colorAmounts
  }

  var body: some View {
    let (colorAngles, _) = colorAmounts.reduce(
      into: (OrderedDictionary<Color, (Double, Double)>(), Double(-90))
    ) { (dict_angle, element) in
      let computedAmount =
        totalColorAmount > totalAmount
        ? element.value * totalAmount / totalColorAmount : element.value
      let newAngle = (360 * computedAmount / totalAmount)
      dict_angle.0[element.key] = (dict_angle.1, dict_angle.1 + newAngle)
      dict_angle.1 += newAngle
    }
    ZStack {
      ForEach(Array(colorAngles.keys), id: \.self) { color in
        if let (startAngle, endAngle) = colorAngles[color] {
          PieWedge(
            startAngle: Angle.degrees(startAngle),
            endAngle: Angle.degrees(endAngle)
          )
          .fill(color.gradient)
        }
      }
      Circle()
        .stroke(.primary)
    }
  }
}

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

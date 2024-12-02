// Copyright Justin Bishop, 2024

import SwiftUI

struct OPMLProgressView: View {
  @Environment(\.colorScheme) var colorScheme

  @Binding var greenAmount: Double {
    didSet {
      validateAmounts()
    }
  }
  @Binding var redAmount: Double {
    didSet {
      validateAmounts()
    }
  }
  private var totalAmount: Double

  init(
    totalAmount: Double,
    greenAmount: Binding<Double>,
    redAmount: Binding<Double>
  ) {
    self.totalAmount = totalAmount
    self._greenAmount = greenAmount
    self._redAmount = redAmount
    validateAmounts()
  }

  var body: some View {
    GeometryReader { geometry in
      let totalWidth = geometry.size.width
      let greenWidth = totalWidth * (greenAmount / totalAmount)
      let redWidth = totalWidth * (redAmount / totalAmount)
      let remainingWidth = totalWidth - greenWidth - redWidth

      HStack(spacing: 0) {
        Rectangle()
          .fill(Color.green)
          .frame(width: greenWidth)

        Rectangle()
          .fill(Color.red)
          .frame(width: redWidth)

        Rectangle()
          .fill(Color.clear)
          .frame(width: remainingWidth)
      }
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(colorScheme == .dark ? .white : .black, lineWidth: 2)
      )
    }
  }

  private func validateAmounts() {
    if greenAmount + redAmount > totalAmount {
      fatalError("greenAmount + redAmount exceeds totalAmount.")
    }
  }
}

#Preview {
  OPMLProgressView(
    totalAmount: 100,
    greenAmount: .constant(40),
    redAmount: .constant(20)
  )
  .frame(height: 50)
  .padding()
}

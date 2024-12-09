// Copyright Justin Bishop, 2024

import SwiftUI

struct PlayBar: View {
  var body: some View {
    HStack {
      Button(action: {
      }) {
        Image(systemName: "backward.fill")
          .font(.title)
          .foregroundColor(.white)
      }

      Spacer()

      Button(action: {
      }) {
        Image(systemName: "play.fill")
          .font(.title)
          .foregroundColor(.white)
      }

      Spacer()

      Button(action: {
      }) {
        Image(systemName: "forward.fill")
          .font(.title)
          .foregroundColor(.white)
      }
    }
    .padding()
    .background(Capsule().fill(Color.blue))
  }
}

#Preview {
  PlayBar()
}

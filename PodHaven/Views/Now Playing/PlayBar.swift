// Copyright Justin Bishop, 2024

import AVFoundation
import SwiftUI

struct PlayBar: View {
  @State private var viewModel = PlayBarViewModel()

  var body: some View {
    VStack {
      HStack {
        Group {
          Button(action: {
            Task { @PlayActor in
              await PlayManager.shared.seekBackward()
            }
          }) {
            Image(systemName: "gobackward.10").foregroundColor(.white)
          }
          Button(action: {
            guard PlayState.shared.isActive, !PlayState.shared.isLoading
            else { return }
            if PlayState.shared.isPlaying {
              Task { @PlayActor in
                PlayManager.shared.pause()
              }
            } else {
              Task { @PlayActor in
                PlayManager.shared.play()
              }
            }
          }) {
            Image(
              systemName: PlayState.shared.isActive
                && !PlayState.shared.isLoading
                ? (PlayState.shared.isPlaying
                  ? "pause.circle" : "play.circle") : "xmark.circle"
            )
            .font(.largeTitle)
            .foregroundColor(.white)
          }
          Button(action: {
            Task { @PlayActor in
              await PlayManager.shared.seekForward()
            }
          }) {
            Image(systemName: "goforward.10").foregroundColor(.white)
          }
        }
        .padding(.horizontal)
      }
      .padding()
      .background(Color.blue)
      .cornerRadius(16)
      .onGeometryChange(for: CGFloat.self) { geometry in
        geometry.size.width
      } action: { newWidth in
        viewModel.barWidth = newWidth
      }
      Slider(
        value: $viewModel.sliderValue,
        in: 0...PlayState.shared.duration.seconds,
        onEditingChanged: { isEditing in
          viewModel.isDragging = isEditing
        }
      )
      .disabled(!PlayState.shared.isActive)
      .frame(width: viewModel.barWidth)
    }
  }
}

#Preview {
  struct PlayBarPreview: View {
    init() {
      Task {
        let podcastEpisode = try! await Repo.shared.db.read { db in
          try! Episode
            .including(required: Episode.podcast)
            .shuffled()
            .asRequest(of: PodcastEpisode.self)
            .fetchOne(db)!
        }
        try await PlayManager.shared.load(podcastEpisode)
      }
    }
    var body: some View {
      PlayBar()
    }
  }
  return Preview { PlayBarPreview() }
}

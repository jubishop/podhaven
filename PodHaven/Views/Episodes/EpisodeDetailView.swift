// Copyright Justin Bishop, 2025

import FactoryKit
import NukeUI
import SwiftUI

struct EpisodeDetailView<ViewModel: EpisodeDetailViewableModel>: View {
  @DynamicInjected(\.alert) private var alert

  private let viewModel: ViewModel

  init(viewModel: ViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .center, spacing: 16) {
          LazyImage(url: viewModel.episodeImage) { state in
            if let image = state.image {
              image
                .resizable()
                .aspectRatio(contentMode: .fill)
            } else {
              Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                  VStack {
                    Image(systemName: "photo")
                      .foregroundColor(.white.opacity(0.8))
                      .font(.title)
                    Text("No Image")
                      .font(.caption)
                      .foregroundColor(.white.opacity(0.8))
                  }
                )
            }
          }
          .frame(width: 200, height: 200)
          .clipped()
          .cornerRadius(12)
          .shadow(radius: 4)

          VStack(spacing: 8) {
            Text(viewModel.episodeTitle)
              .font(.title2)
              .fontWeight(.semibold)
              .multilineTextAlignment(.center)

            Text(viewModel.podcastTitle)
              .font(.headline)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
          }
        }
        .frame(maxWidth: .infinity)

        VStack(alignment: .leading, spacing: 16) {
          HStack {
            HStack(spacing: 8) {
              Image(systemName: "calendar")
                .foregroundColor(.secondary)
              Text("Published")
                .font(.caption)
                .foregroundColor(.secondary)
              Text(viewModel.episodePubDate.usShortWithTime)
                .font(.subheadline)
            }

            Spacer()

            if viewModel.episodeCached {
              VStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                  .foregroundColor(.green)
                Text("Cached")
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }

            Spacer()

            HStack(spacing: 8) {
              Image(systemName: "clock")
                .foregroundColor(.secondary)
              Text("Duration")
                .font(.caption)
                .foregroundColor(.secondary)
              Text(viewModel.episodeDuration.shortDescription)
                .font(.subheadline)
            }
          }
          .padding(.horizontal)

          if let description = viewModel.episodeDescription, !description.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("Description")
                .font(.headline)
                .padding(.horizontal)

              HTMLText(description)
                .font(.body)
                .padding(.horizontal)
            }
          }

          if !viewModel.onDeck {
            VStack(spacing: 12) {
              Button(action: viewModel.playNow) {
                HStack {
                  Image(systemName: "play.fill")
                  Text("Play Now")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
              }

              HStack(spacing: 12) {
                Button(action: viewModel.addToTopOfQueue) {
                  HStack {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    Text(viewModel.atTopOfQueue ? "Already at Top" : "Add to Top")
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                  .cornerRadius(10)
                }
                .disabled(viewModel.atTopOfQueue)

                Button(action: viewModel.appendToQueue) {
                  HStack {
                    Image(systemName: "text.line.last.and.arrowtriangle.forward")
                    Text(viewModel.atBottomOfQueue ? "Already at Bottom" : "Add to Bottom")
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                  .cornerRadius(10)
                }
                .disabled(viewModel.atBottomOfQueue)
              }
            }
            .padding(.horizontal)
          }
        }
      }
      .padding(.vertical)
    }
    .task { await viewModel.execute() }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var podcastEpisode: PodcastEpisode?

  NavigationStack {
    Group {
      if let podcastEpisode {
        EpisodeDetailView(viewModel: EpisodeDetailViewModel(podcastEpisode: podcastEpisode))
      } else {
        Text("No episodes in DB")
      }
    }
  }
  .preview()
  .task {
    podcastEpisode = try? await PreviewHelpers.loadPodcastEpisode()
  }
}
#endif

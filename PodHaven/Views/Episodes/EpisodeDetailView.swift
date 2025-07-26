// Copyright Justin Bishop, 2025

import FactoryKit
import NukeUI
import SwiftUI

struct EpisodeDetailView: View {
  @DynamicInjected(\.alert) private var alert

  private let viewModel: EpisodeDetailViewModel

  init(viewModel: EpisodeDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .center, spacing: 16) {
          LazyImage(url: viewModel.image) { state in
            if let image = state.image {
              image
                .resizable()
                .aspectRatio(contentMode: .fill)
            } else {
              Rectangle()
                .fill(Color.gray.opacity(0.3))
            }
          }
          .frame(width: 200, height: 200)
          .clipped()
          .cornerRadius(12)
          .shadow(radius: 4)

          VStack(spacing: 8) {
            Text(viewModel.episode.title)
              .font(.title2)
              .fontWeight(.semibold)
              .multilineTextAlignment(.center)

            Text(viewModel.podcast.title)
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
              Text(viewModel.episode.pubDate.usShortWithTime)
                .font(.subheadline)
            }

            Spacer()

            HStack(spacing: 8) {
              Image(systemName: "clock")
                .foregroundColor(.secondary)
              Text("Duration")
                .font(.caption)
                .foregroundColor(.secondary)
              Text(viewModel.episode.duration.shortDescription)
                .font(.subheadline)
            }
          }
          .padding(.horizontal)

          if let description = viewModel.episode.description, !description.isEmpty {
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
                    Text("Add to Top")
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                  .background(Color.secondary.opacity(0.2))
                  .cornerRadius(10)
                }

                Button(action: viewModel.appendToQueue) {
                  HStack {
                    Image(systemName: "text.line.last.and.arrowtriangle.forward")
                    Text("Add to Bottom")
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                  .background(Color.secondary.opacity(0.2))
                  .cornerRadius(10)
                }
              }
            }
            .padding(.horizontal)
          }
        }
      }
      .padding(.vertical)
    }
    .task(viewModel.execute)
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

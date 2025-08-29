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
                    AppLabel.noImage.image
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

            Button(action: {
              viewModel.showPodcast()
            }) {
              Text(viewModel.podcastTitle)
                .font(.headline)
                .foregroundColor(.accentColor)
                .multilineTextAlignment(.center)
                .underline()
            }
            .buttonStyle(PlainButtonStyle())
          }
        }
        .frame(maxWidth: .infinity)

        VStack(alignment: .leading, spacing: 16) {
          HStack {
            HStack(spacing: 8) {
              AppLabel.publishDate.image
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
                AppLabel.episodeCached.image
                  .foregroundColor(.green)
                Text("Cached")
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }

            Spacer()

            HStack(spacing: 8) {
              AppLabel.duration.image
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
                  AppLabel.playNow.image
                  Text(AppLabel.playNow.text)
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
                    AppLabel.queueLatestToTop.image
                    Text(viewModel.atTopOfQueue ? "Already at Top" : AppLabel.addToTop.text)
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                  .cornerRadius(10)
                }
                .disabled(viewModel.atTopOfQueue)

                Button(action: viewModel.appendToQueue) {
                  HStack {
                    AppLabel.queueLatestToBottom.image
                    Text(
                      viewModel.atBottomOfQueue ? "Already at Bottom" : AppLabel.addToBottom.text
                    )
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                  .cornerRadius(10)
                }
                .disabled(viewModel.atBottomOfQueue)
              }
              
              if !viewModel.episodeCached {
                Button(action: viewModel.cacheEpisode) {
                  HStack {
                    if viewModel.isCaching {
                      ProgressView()
                        .scaleEffect(0.8)
                      Text("Caching in Progress")
                    } else {
                      AppLabel.cacheEpisode.image
                      Text(AppLabel.cacheEpisode.text)
                    }
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                  .background(viewModel.isCaching ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
                  .foregroundColor(viewModel.isCaching ? .orange : .green)
                  .cornerRadius(10)
                }
                .disabled(viewModel.isCaching)
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
        EpisodeDetailView(viewModel: EpisodeDetailViewModel(episode: podcastEpisode))
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

// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

struct WidgetEpisode: Equatable, Identifiable {
  let id: Episode.ID
  let title: String
  let pubDate: Date
  let duration: CMTime
  let episodeImage: URL?
  let podcastImage: URL

  var image: URL { episodeImage ?? podcastImage }

  init(_ podcastEpisode: PodcastEpisode) {
    id = podcastEpisode.id
    title = podcastEpisode.title
    pubDate = podcastEpisode.pubDate
    duration = podcastEpisode.duration
    episodeImage = podcastEpisode.episode.image
    podcastImage = podcastEpisode.podcast.image
  }

  init(_ episode: ListablePodcastEpisode) {
    id = episode.id
    title = episode.title
    pubDate = episode.pubDate
    duration = episode.duration
    episodeImage = episode.episodeImage
    podcastImage = episode.podcastImage
  }
}

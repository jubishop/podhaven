// Copyright Justin Bishop, 2026

#if DEBUG
import SwiftUI

struct DescriptionDetailPreview: View {
  enum Sample: String, CaseIterable {
    case short = "Short"
    case long = "Long"
    case paragraph = "Huge paragraph"
    case shortParagraphs = "Short paragraphs"
    case empty = "Empty"

    var html: String {
      switch self {
      case .short:
        return """
          <p>Beginning: <b>bold</b>, <i>italic</i>, and 👩🏽‍💻 Unicode.</p>
          <p><a href="https://example.com">External notes</a> and chapter 12:34.</p>
          <ol><li>First item</li><li>Second item</li></ol>
          """
      case .long:
        return Sample.short.html
          + (1...1484)
          .map {
            "<p>Paragraph \($0): "
              + String(repeating: "Full description text remains readable. ", count: 4) + "</p>"
          }
          .joined()
          + "<p>End of description. Chapter 1:02:15.</p>"
      case .paragraph:
        return "<p>Beginning. "
          + String(repeating: "One huge paragraph with 👩🏽‍💻 Unicode and readable words. ", count: 3500)
          + " End of description.</p>"
      case .empty:
        return ""
      case .shortParagraphs:
        return String(repeating: "<p>V</p>", count: 6000)
      }
    }
  }

  let sample: Sample
  let podcast: Bool

  var body: some View {
    NavigationStack {
      if podcast {
        podcastPreview
      } else {
        EpisodeDetailView(
          viewModel: EpisodeDetailViewModel(
            episode: DisplayedEpisode(
              UnsavedPodcastEpisode(
                unsavedPodcast: try! Create.unsavedPodcast(title: "Description Preview"),
                unsavedEpisode: try! Create.unsavedEpisode(
                  title: "\(sample.rawValue) Description",
                  description: sample.html
                )
              )
            )
          )
        )
      }
    }
    .preview()
  }

  private var podcastPreview: some View {
    let model = PodcastDetailViewModel(
      unsavedPodcastSeries: UnsavedPodcastSeries(
        unsavedPodcast: try! Create.unsavedPodcast(
          title: "Description Preview",
          description: sample.html
        ),
        unsavedEpisodes: [try! Create.unsavedEpisode(title: "Preview Episode")]
      )
    )
    model.displayingAboutSection = true
    return PodcastDetailView(viewModel: model)
  }

}

#Preview("Long Episode Description") {
  DescriptionDetailPreview(sample: .long, podcast: false)
}

#Preview("Huge Paragraph at Large Text") {
  DescriptionDetailPreview(sample: .paragraph, podcast: false)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Long Podcast Description") {
  DescriptionDetailPreview(sample: .long, podcast: true)
}

#Preview("Short Paragraphs at Largest Text") {
  DescriptionDetailPreview(sample: .shortParagraphs, podcast: false)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Short Description") {
  DescriptionDetailPreview(sample: .short, podcast: false)
}

#Preview("Empty Description") {
  DescriptionDetailPreview(sample: .empty, podcast: false)
}
#endif

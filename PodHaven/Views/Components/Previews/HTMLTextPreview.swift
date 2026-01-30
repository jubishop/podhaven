// Copyright Justin Bishop, 2026

#if DEBUG
import SwiftUI

// MARK: - Standard HTMLText Previews

private struct HTMLTextPreviewList: View {
  struct Sample {
    let description: String
    let html: String
    let color: Color
    let font: Font
  }

  let title: String
  let samples: [Sample]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(title)
          .font(.title2)
          .bold()

        ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
          VStack(alignment: .leading, spacing: 8) {
            Text(sample.description)
              .font(.headline)
            HTMLText(sample.html)
              .font(sample.font)
              .foregroundStyle(sample.color)
          }

          if index < samples.count - 1 {
            Divider()
          }
        }
      }
      .padding()
    }
  }
}

private struct HTMLTextPreviewGroup {
  let title: String
  let samples: [HTMLTextPreviewList.Sample]
}

private let htmlTextPreviewGroups: [HTMLTextPreviewGroup] = [
  .init(
    title: "Basic Styles",
    samples: [
      .init(
        description: "Bold, italic, and underline",
        html: "<b>Bold text</b>, <i>italic text</i>, and <u>underlined text</u>.",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Strong and emphasis tags",
        html: "<strong>Strong text</strong> and <em>emphasized text</em> work too.",
        color: .secondary,
        font: .body
      ),
      .init(
        description: "Tags with attributes",
        html:
          "<b class=\"hero\">Bold with class</b> and <i style=\"font-style: italic\">italic with style</i> still render.",
        color: .indigo,
        font: .body
      ),
      .init(
        description: "Nested combinations",
        html:
          "You can combine <b><i>bold and italic</i></b>, or even <b><i><u>all three styles</u></i></b>!",
        color: .blue,
        font: .body
      ),
      .init(
        description: "Different font scales",
        html: "<b>Large Title:</b> This is <i>important</i> information!",
        color: .purple,
        font: .largeTitle
      ),
    ]
  ),
  .init(
    title: "Paragraphs & Line Breaks",
    samples: [
      .init(
        description: "Paragraph separation",
        html: "<p>First paragraph with some content.</p><p>Second paragraph after a break.</p>",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Explicit line breaks",
        html: "Line one<br/>Line two<br />Line three<br>Line four",
        color: .orange,
        font: .body
      ),
      .init(
        description: "Truncated API response",
        html:
          "<h1>Episode Title That Got Cut Off</h1><p>This simulates how PodcastIndex API truncates descriptions mid-sentence without proper closing tags",
        color: .red,
        font: .body
      ),
    ]
  ),
  .init(
    title: "Block Tags & Headings",
    samples: [
      .init(
        description: "Div blocks",
        html: "<div>Intro line.</div><div>Second line with <b>bold</b>.</div>",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Heading levels",
        html: "<h1>Main Title</h1><h2>Subtitle</h2><div>Body text follows under headings.</div>",
        color: .secondary,
        font: .body
      ),
      .init(
        description: "Section and article tags",
        html:
          "<section>Section opener</section><article>Article body with <em>emphasis</em>.</article>",
        color: .orange,
        font: .body
      ),
    ]
  ),
  .init(
    title: "Entities & Symbols",
    samples: [
      .init(
        description: "Quotes and punctuation",
        html: "Quotation marks: &lsquo;single&rsquo; and &ldquo;double&rdquo; quotes work great!",
        color: .purple,
        font: .body
      ),
      .init(
        description: "Common entities",
        html:
          "Common entities: &amp; (ampersand), &lt; (less than), &gt; (greater than), &quot;quotes&quot;",
        color: .blue,
        font: .body
      ),
      .init(
        description: "Special characters",
        html: "Special chars: &mdash; em dash, &ndash; en dash, &hellip; ellipsis, &bull; bullet",
        color: .orange,
        font: .body
      ),
      .init(
        description: "Symbols and currency",
        html:
          "Symbols: &copy; &reg; &trade; &deg; &plusmn; &times; &divide; &euro;100 &pound;50 &yen;1000",
        color: .green,
        font: .body
      ),
    ]
  ),
  .init(
    title: "Links",
    samples: [
      .init(
        description: "Basic link",
        html: "Visit <a href=\"https://www.apple.com\">Apple's website</a> for more information.",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Multiple links",
        html:
          "Check out <a href=\"https://github.com\">GitHub</a> and <a href=\"https://stackoverflow.com\">Stack Overflow</a> for coding help.",
        color: .blue,
        font: .body
      ),
      .init(
        description: "Formatted links",
        html:
          "<b>Links can have formatting:</b> <a href=\"https://www.swift.org\"><i>Swift.org</i></a> and <a href=\"https://developer.apple.com\"><b>Apple Developer</b></a>",
        color: .purple,
        font: .body
      ),
      .init(
        description: "Single quote href",
        html: #"Single quotes work too: <a href='https://www.example.com'>Example Site</a>"#,
        color: .green,
        font: .callout
      ),
    ]
  ),
  .init(
    title: "Complex & Edge Cases",
    samples: [
      .init(
        description: "Welcome message",
        html: """
          <p><b>Welcome to our app!</b></p>
          <p>Here you can find <i>amazing</i> content with <u>special</u> formatting.</p>
          <p>We support <b><i>multiple</i></b> styles and <br/><strong>proper paragraph spacing</strong>.</p>
          """,
        color: .indigo,
        font: .body
      ),
      .init(
        description: "Unclosed tags",
        html: "Edge case: <b>Unclosed bold and <i>nested italic</i> should still work properly.",
        color: .red,
        font: .caption
      ),
      .init(
        description: "Plain text fallback",
        html:
          "This text has no HTML tags, so it should display normally with the specified color and font.",
        color: .mint,
        font: .subheadline
      ),
      .init(
        description: "Truncated search snippet",
        html:
          "<p>Ever wondered how a podcast can truly reflect the soul of a city? Join us as we turn the tables on Erik Nilsson, the dynamic host who finds himself on the other side of the microphone...",
        color: .orange,
        font: .body
      ),
    ]
  ),
  .init(
    title: "Long-form Descriptions",
    samples: [
      .init(
        description: "Multi-paragraph episode synopsis",
        html: """
          <p><b>Episode 142: Mapping the Future</b> invites urban planner <i>Dr. Elena Cruz</i> to unpack how cities redesign transit for the AI era.</p>
          <p>We explore <u>dynamic zoning</u>, commuter twins, and why open data is the hidden catalyst for equitable streets. Discover the pilot projects rolling out in Austin, Seattle, and Berlin—and what it will take to scale them.</p>
          <p><a href=\"https://example.com/show-notes\">Read the full show notes</a> for maps, datasets, and a timeline of reforms.</p>
          """,
        color: .primary,
        font: .body
      ),
      .init(
        description: "Newsletter-style recap",
        html: """
          <p>Another week, another burst of podcast discovery: <strong>three new indie launches</strong>, an <em>audio drama revival</em>, and chart insights from across the globe.</p>
          <p>Tap through for the curated feed bundle, or jump straight to <a href=\"https://podhaven.app/curation\">our curators' picks</a>.</p>
          """,
        color: .secondary,
        font: .callout
      ),
    ]
  ),
  .init(
    title: "Malformed HTML Recovery",
    samples: [
      .init(
        description: "Missing closing tags",
        html:
          "<p><b>Live from the floor</b> our hosts recap the keynote with <i>breaking reactions",
        color: .pink,
        font: .body
      ),
      .init(
        description: "Double-encoded entities & stray brackets",
        html:
          "Latest update &amp;amp; quick hotfix &lt;br&gt; rolling out now &mdash; watch for &lt;unexpected&gt; surprises.",
        color: .orange,
        font: .footnote
      ),
    ]
  ),
  .init(
    title: "Release Notes & Bullet Lists",
    samples: [
      .init(
        description: "Changelog with bullets",
        html: """
          <p>&bull; Added <b>Smart Queue</b> reordering<br/>&bull; Improved offline caching stability<br/>&bull; Fixed &ldquo;Resume" button getting stuck</p>
          """,
        color: .teal,
        font: .body
      ),
      .init(
        description: "Feature spotlight",
        html: """
          <p>&bull; Spotlight: <em>Episode Sync</em> mirrors progress across devices.<br/>&bull; Coming soon: <u>Sleep Sync</u> with Apple Health.</p>
          """,
        color: .indigo,
        font: .callout
      ),
    ]
  ),
  .init(
    title: "Localization Stress",
    samples: [
      .init(
        description: "German longform",
        html:
          "<p><b>Neu:</b> Ein tiefes Gespräch über <i>Klimadaten</i> und offene Sensoren in europäischen Metropolen.</p>",
        color: .primary,
        font: .body
      ),
      .init(
        description: "French teaser",
        html:
          "<p>Suivez notre <em>série spéciale</em> sur les studios indépendants &mdash; interviews, coulisses et playlists.</p>",
        color: .purple,
        font: .body
      ),
      .init(
        description: "RTL snippet",
        html:
          "<p>اكتشف أحدث حلقاتنا عن <strong>التقنية</strong> و<span>الابتكار</span> حول العالم.</p>",
        color: .mint,
        font: .body
      ),
    ]
  ),
  .init(
    title: "Custom Fonts",
    samples: [
      .init(
        description: "Serif emphasis",
        html:
          "<p><b>Editor's Letter:</b> Discover the stories shaping podcasting this quarter.</p>",
        color: .primary,
        font: .system(size: 18, weight: .medium, design: .serif)
      ),
      .init(
        description: "Title casing",
        html: "<p><em>Spotlight:</em> Acoustic Design</p>",
        color: .brown,
        font: .title3
      ),
    ]
  ),
  .init(
    title: "Emoji & Multicodepoint",
    samples: [
      .init(
        description: "Emoji-rich teaser",
        html:
          "<p>🎙️ New episode drops tomorrow! 🚀 Dive into space tech with NASA's mission crew.</p>",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Flags and sequences",
        html: "<p>Global round-up 🇺🇸 🇩🇪 🇯🇵 — plus bonus segments on music 🎧 and wellness 🧘‍♂️.</p>",
        color: .orange,
        font: .callout
      ),
      .init(
        description: "Entity + emoji mix",
        html: "<p>&#128640; &mdash; Counting down to launch with behind-the-scenes 📸.</p>",
        color: .blue,
        font: .body
      ),
    ]
  ),
  .init(
    title: "Font Variations",
    samples: [
      .init(
        description: "Default body",
        html: "<b>Body:</b> Inherits the environment body font size.",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Semibold rounded",
        html: "<b>Rounded Semibold:</b> Emphasized text with a rounded design.",
        color: .mint,
        font: .system(size: 20, weight: .semibold, design: .rounded)
      ),
      .init(
        description: "Serif light",
        html: "<b>Serif Light:</b> Elegant typography for long-form reading.",
        color: .indigo,
        font: .system(size: 22, weight: .light, design: .serif)
      ),
      .init(
        description: "Monospaced heavy",
        html: "<b>Monospaced Heavy:</b> Great for highlighting code or identifiers.",
        color: .orange,
        font: .system(size: 18, weight: .heavy, design: .monospaced)
      ),
      .init(
        description: "Large title stylistic",
        html: "<b>Large Title:</b> This headline uses a palette-accented foreground.",
        color: .pink,
        font: .largeTitle
      ),
    ]
  ),
  .init(
    title: "Lists",
    samples: [
      .init(
        description: "Well-formed list",
        html: "<ul><li>First item</li><li>Second item</li><li>Third item</li></ul>",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Ordered list",
        html: "<ol><li>Step one</li><li>Step two</li><li>Step three</li></ol>",
        color: .primary,
        font: .body
      ),
      .init(
        description: "List with formatted content",
        html:
          "<ul><li><b>Bold item</b> with extra text</li><li>Item with <i>italic</i> styling</li><li>Item with a <a href=\"https://example.com\">link</a></li></ul>",
        color: .blue,
        font: .body
      ),
      .init(
        description: "Unclosed <li> tags (truncated feed)",
        html: "<ul><li>First item<li>Second item<li>Third item",
        color: .orange,
        font: .body
      ),
      .init(
        description: "Mixed closed and unclosed",
        html: "<ul><li>First item</li><li>Second item<li>Third item</li>",
        color: .purple,
        font: .body
      ),
      .init(
        description: "Orphan <li> without <ul>",
        html: "<p>Some text</p><li>Standalone item</li><li>Another item</li><p>More text</p>",
        color: .pink,
        font: .body
      ),
      .init(
        description: "List in context with paragraphs",
        html:
          "<p><b>What's New:</b></p><ul><li>Improved search algorithm</li><li>Better battery efficiency</li><li>New themes available</li></ul><p>Enjoy the update!</p>",
        color: .green,
        font: .callout
      ),
      .init(
        description: "List with HTML entities",
        html:
          "<ul><li>Support for &amp; symbols</li><li>Em dashes &mdash; work great</li><li>Quotes: &ldquo;double&rdquo; and &lsquo;single&rsquo;</li></ul>",
        color: .teal,
        font: .body
      ),
      .init(
        description: "Malformed: no closing tags at all",
        html: "<ul><li>Feature one<li>Feature two<li>Feature three",
        color: .red,
        font: .caption
      ),
      .init(
        description: "Empty list items",
        html: "<ul><li></li><li>Actual content</li><li></li></ul>",
        color: .secondary,
        font: .body
      ),
    ]
  ),
  .init(
    title: "Text Decorations",
    samples: [
      .init(
        description: "Simple strikethrough",
        html: "<s>Deprecated:</s> Old show notes link",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Multiple strikes",
        html: "<strong>Updates:</strong> <del>Conference delayed</del> <s>Venue TBD</s>",
        color: .orange,
        font: .callout
      ),
      .init(
        description: "Highlighted snippet",
        html: "Remember to <mark>subscribe</mark> for bonus tips!",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Dark theme check",
        html: "Night mode <mark>highlight</mark> with <s>strike</s> mix",
        color: .secondary,
        font: .body
      ),
    ]
  ),
]

struct HTMLTextPreviewGallery: View {
  var body: some View {
    NavigationStack {
      List(htmlTextPreviewGroups, id: \.title) { group in
        NavigationLink(group.title) {
          HTMLTextPreviewList(title: group.title, samples: group.samples)
            .navigationTitle(group.title)
            .navigationBarTitleDisplayMode(.inline)
        }
      }
      .navigationTitle("HTMLText Scenarios")
    }
  }
}

// MARK: - Menu HTMLText Previews

struct HTMLTextMenuPreview: View {
  private let timestampPattern = #/\d{1,2}:\d{2}(?::\d{2})?/#

  struct MenuSample {
    let description: String
    let html: String
  }

  private let samples: [MenuSample] = [
    // MARK: - Basic menu with surrounding formatting
    MenuSample(
      description: "Bold text before timestamp",
      html: "<b>Chapter 1:</b> 00:15:30 - Introduction to the topic"
    ),
    MenuSample(
      description: "Italic text after timestamp",
      html: "00:30:00 - <i>Special guest interview</i> with the author"
    ),
    MenuSample(
      description: "Multiple formats on same line",
      html: "<b>Act II</b> 01:15:00 - The <i>turning point</i> arrives"
    ),
    MenuSample(
      description: "Bold, italic, and underline mixed",
      html: "<b><i>Important:</i></b> 00:45:30 - <u>Key takeaway</u> from discussion"
    ),
    MenuSample(
      description: "Strikethrough and mark",
      html: "<s>Old chapter</s> <mark>NEW:</mark> 02:00:00 - Updated content"
    ),
    MenuSample(
      description: "Link on same line as timestamp",
      html:
        "00:20:00 - Check out <a href=\"https://example.com\">this resource</a> for more info"
    ),
    MenuSample(
      description: "Multiple timestamps with formatting",
      html: "<b>Intro:</b> 00:00:00 | <i>Main:</i> 00:10:00 | <u>Outro:</u> 00:55:00"
    ),
    MenuSample(
      description: "Nested formatting around timestamp",
      html: "Before <b>the <i>big</i> moment</b> at 00:25:00 comes <i>the <b>setup</b></i>"
    ),
    MenuSample(
      description: "Multi-line with mixed formatting",
      html: """
        <p><b>Episode Chapters:</b></p>
        <p>00:00:00 - <i>Welcome</i> and introductions</p>
        <p><b>Part 1:</b> 00:05:30 - Background context</p>
        <p><mark>Highlight:</mark> 00:30:00 - The <b>key revelation</b></p>
        <p>01:00:00 - <u>Closing thoughts</u> and <a href=\"https://example.com\">links</a></p>
        """
    ),
    MenuSample(
      description: "Plain line (no timestamp) between formatted lines",
      html: """
        <b>Chapter 1:</b> 00:10:00 - Opening
        This line has no timestamp but has <b>bold</b> and <i>italic</i> text.
        <b>Chapter 2:</b> 00:20:00 - Continuation
        """
    ),
    MenuSample(
      description: "HTML entities with formatting",
      html:
        "<b>Q&amp;A:</b> 00:40:00 - Listener questions &mdash; <i>&ldquo;Best practices?&rdquo;</i>"
    ),
    MenuSample(
      description: "List items with timestamps",
      html: """
        <ul>
        <li><b>Intro:</b> 00:00:00 - Welcome</li>
        <li><i>Deep dive:</i> 00:15:00 - Technical details</li>
        <li><u>Wrap-up:</u> 00:45:00 - Summary</li>
        </ul>
        """
    ),

    // MARK: - Formatted Timestamps (timestamp itself is styled)
    MenuSample(
      description: "Bold timestamp",
      html: "Chapter starts at <b>00:15:30</b> with the introduction"
    ),
    MenuSample(
      description: "Italic timestamp",
      html: "The key moment is at <i>01:23:45</i> in the recording"
    ),
    MenuSample(
      description: "Underlined timestamp",
      html: "Skip to <u>00:30:00</u> for the good part"
    ),
    MenuSample(
      description: "Bold italic timestamp",
      html: "Don't miss <b><i>02:00:00</i></b> - it's the climax!"
    ),
    MenuSample(
      description: "Marked/highlighted timestamp",
      html: "Jump to <mark>00:45:00</mark> for the spoiler"
    ),
    MenuSample(
      description: "Strikethrough timestamp (corrected)",
      html: "Was at <s>00:10:00</s>, now at <b>00:12:30</b>"
    ),
    MenuSample(
      description: "Linked timestamp",
      html: "See <a href=\"https://example.com/clip\">00:05:00</a> for the viral clip"
    ),
    MenuSample(
      description: "Multiple formatted timestamps",
      html: "<b>00:00:00</b> Intro | <i>00:10:00</i> Main | <u>00:50:00</u> Outro"
    ),
    MenuSample(
      description: "Formatted timestamp with formatted surrounding text",
      html: "<b>Important:</b> Check <i>00:25:00</i> for the <u>key insight</u>"
    ),
    MenuSample(
      description: "All formatting styles on timestamps",
      html: """
        <b>00:00:00</b> Bold
        <i>00:01:00</i> Italic
        <u>00:02:00</u> Underline
        <s>00:03:00</s> Strike
        <mark>00:04:00</mark> Mark
        <b><i>00:05:00</i></b> Bold+Italic
        """
    ),

    // MARK: - Multi-format text segments (format changes within text around timestamps)
    MenuSample(
      description: "Bold then italic before timestamp",
      html: "<b>Bold</b> and <i>italic</i> 00:15:00 - after"
    ),
    MenuSample(
      description: "Multiple formats before and after timestamp",
      html: "<b>Start bold</b> <i>then italic</i> 00:20:00 <u>underline</u> <s>strike</s> end"
    ),
    MenuSample(
      description: "Format change mid-word before timestamp",
      html: "Half<b>bold</b> 00:10:00 - description"
    ),
    MenuSample(
      description: "Complex: all formats before timestamp",
      html:
        "<b>Bold</b> <i>Italic</i> <u>Under</u> <s>Strike</s> <mark>Mark</mark> 00:30:00 - plain after"
    ),
    MenuSample(
      description: "Alternating formats around multiple timestamps",
      html:
        "<b>Ch1</b> 00:00:00 <i>intro</i> | <u>Ch2</u> 00:10:00 <s>old</s> | <mark>Ch3</mark> 00:20:00 end"
    ),
    MenuSample(
      description: "Nested formats before timestamp",
      html: "<b>Bold <i>and italic</i> just bold</b> 00:25:00 - plain"
    ),
    MenuSample(
      description: "Link and bold before timestamp",
      html: "<a href=\"https://example.com\">Link text</a> and <b>bold</b> 00:35:00 - more"
    ),
    MenuSample(
      description: "Format spanning before and after timestamp",
      html: "<b>Bold before</b> 00:40:00 <b>bold after</b> with <i>italic</i> mixed"
    ),
    MenuSample(
      description: "Many format changes in one line",
      html:
        "<b>A</b><i>B</i><u>C</u><s>D</s><mark>E</mark> 00:45:00 <mark>F</mark><s>G</s><u>H</u><i>I</i><b>J</b>"
    ),
    MenuSample(
      description: "Real-world chapter list with mixed formatting",
      html: """
        <b>Introduction</b> - <i>Setting the scene</i> 00:00:00
        <b>Part 1:</b> The <i>journey</i> begins 00:05:00
        <mark>KEY:</mark> <b>Critical</b> <i>insight</i> revealed 00:15:00
        <b>Conclusion</b> - <u>Final thoughts</u> 00:45:00
        """
    ),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Menu with HTML Formatting")
          .font(.title2)
          .bold()

        Text("Timestamps are interactive menus; other text preserves HTML styling.")
          .font(.caption)
          .foregroundStyle(.secondary)

        ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
          VStack(alignment: .leading, spacing: 8) {
            Text(sample.description)
              .font(.headline)

            HTMLText(sample.html, menuMatching: timestampPattern) { timestamp in
              Button("Play from \(timestamp)") {}
              Button("Copy timestamp") {}
            }
            .font(.body)
          }

          if index < samples.count - 1 {
            Divider()
          }
        }
      }
      .padding()
    }
  }
}
#endif

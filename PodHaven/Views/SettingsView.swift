// Copyright Justin Bishop, 2024

import OPML
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @Environment(Navigation.self) var navigation

  let opmlType = UTType(filenameExtension: "opml", conformingTo: .xml)

  @State private var opmlImporting = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Importing / Exporting") {
          Button(
            action: {
              #if targetEnvironment(simulator)
                guard
                  let url = Bundle.main.url(
                    forResource: "podcasts",
                    withExtension: "opml"
                  )
                else {
                  print("failed to locate opml in resources")
                  return
                }
                do {
                  let opml = try OPML(file: url)
                  print(url)
                  print(opml)
                } catch {
                  fatalError(error.localizedDescription)
                }
              #else
                opmlImporting = true
              #endif
            },
            label: { Text("Import OPML") }
          )
        }
        Section("Navigating") {
          Button(
            action: { navigation.currentTab = .upNext },
            label: { Text("Go to UpNext") }
          )
        }
      }
      .navigationTitle("Settings")
    }
    .fileImporter(
      isPresented: $opmlImporting,
      allowedContentTypes: [.text]
    ) { result in
      switch result {
      case .success(let url):
        print(url)
        do {
          if url.startAccessingSecurityScopedResource() {
            //            let contents = try String(
            //              contentsOfFile: url.path,
            //              encoding: String.Encoding.utf8
            //            )
            //            print(
            //              contents
            //            )
            let opml = try OPML(file: url)
            print(url)
            print(opml)
          } else {
            print("couldn't start accessing security scoped response")
          }
          url.stopAccessingSecurityScopedResource()
        } catch {
          fatalError(error.localizedDescription)
        }
      case .failure(let error):
        print(error.localizedDescription)
      }
    }
  }
}

#Preview {
  SettingsView().environment(Navigation())
}

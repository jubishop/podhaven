// Copyright Justin Bishop, 2026

import SwiftUI

struct IconPickerView: View {
  @Binding var selection: LucideIcon

  @Environment(\.dismiss) private var dismiss

  @State private var search = ""

  private let columns = [GridItem(.adaptive(minimum: 64), spacing: 12)]

  var body: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: 16, pinnedViews: [.sectionHeaders]) {
        ForEach(filteredGroups) { group in
          Section {
            ForEach(group.entries) { entry in
              iconButton(entry)
            }
          } header: {
            header(group.category)
          }
        }
      }
      .padding(.horizontal)
    }
    .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
    .autocorrectionDisabled()
    .textInputAutocapitalization(.never)
    .navigationTitle("Choose Icon")
    .navigationBarTitleDisplayMode(.inline)
    .overlay {
      if filteredGroups.isEmpty {
        ContentUnavailableView.search(text: search)
      }
    }
  }

  private func iconButton(_ entry: LucideIcon.Entry) -> some View {
    let isSelected = entry.icon == selection
    return Button {
      selection = entry.icon
      dismiss()
    } label: {
      VStack(spacing: 4) {
        LucideIconView(icon: entry.icon)
          .frame(width: 30, height: 30)
          .foregroundStyle(isSelected ? Color.accentColor : .primary)
        Text(entry.label)
          .font(.caption2)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
      )
    }
    .buttonStyle(.plain)
  }

  private func header(_ category: LucideIcon.Category) -> some View {
    Text(category.rawValue)
      .font(.subheadline.weight(.semibold))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 6)
      .background(.bar)
  }

  private var filteredGroups: [LucideIcon.Group] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return LucideIcon.groups }
    return LucideIcon.groups.compactMap { group in
      let entries = group.entries.filter {
        $0.label.lowercased().contains(query) || $0.icon.rawValue.contains(query)
      }
      return entries.isEmpty ? nil : LucideIcon.Group(category: group.category, entries: entries)
    }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var selection: LucideIcon = .tag
  return NavigationStack {
    IconPickerView(selection: $selection)
  }
}
#endif

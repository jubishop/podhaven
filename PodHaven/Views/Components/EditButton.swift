import SwiftUI

struct EditButton<Label: View>: View {
  @Environment(\.editMode) private var editMode

  private var isEditing: Bool { editMode?.wrappedValue == .active }
  private var onToggle: ((Bool) -> Void)?
  private var label: (Bool) -> Label

  init(
    onToggle: ((Bool) -> Void)? = nil,
    @ViewBuilder label: @escaping (Bool) -> Label = { isEditing in
      Text(isEditing ? "Done" : "Edit")
    }
  ) {
    self.onToggle = onToggle
    self.label = label
  }

  var body: some View {
    Button(
      action: {
        withAnimation {
          editMode?.wrappedValue = isEditing ? .inactive : .active
          onToggle?(isEditing)
        }
      },
      label: {
        label(isEditing)
      }
    )
  }
}

#if DEBUG
#Preview {
  @Previewable @State var defaultText: String = "Unclicked"
  @Previewable @State var customText: String = "Unclicked"
  @Previewable @Environment(\.editMode) var editMode
  var isEditing: Bool { editMode?.wrappedValue == .active }

  VStack(spacing: 20) {
    Text("Edit mode: \(isEditing ? "active" : "inactive")")

    // Default Everything
    EditButton()

    // Custom Toggle Only
    Text(defaultText)
    EditButton { isEditing in
      defaultText = "Default editing?: \(isEditing ? "yes" : "no")"
    }

    // Custom Label Only
    EditButton(
      label: { isEditing in
        Text(isEditing ? "Finish Editing" : "Start Editing")
          .bold()
          .foregroundColor(.blue)
      }
    )

    // Custom Button Style Only
    EditButton()
      .padding()
      .background(isEditing ? Color.green : Color.white)
      .cornerRadius(8)
      .shadow(radius: 3)

    // Custom Everything
    Text(customText)
    EditButton(
      onToggle: { isEditing in
        customText = "Custom editing?: \(isEditing ? "yes" : "no")"
      },
      label: { isEditing in
        HStack {
          Image(systemName: isEditing ? "checkmark.circle" : "pencil.circle")
          Text(isEditing ? "Done Editing" : "Edit Mode")
        }
      }
    )
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(isEditing ? Color.blue : Color.black)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.white, lineWidth: 2)
    )
    .foregroundStyle(Color.white)
  }
  .padding()
}
#endif

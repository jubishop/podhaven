import SwiftUI

struct EditButton<Label: View>: View {
  @Binding var editMode: EditMode
  var isEditing: Bool { editMode == .active }

  var onToggle: ((Bool) -> Void)?
  var label: (Bool) -> Label

  init(
    editMode: Binding<EditMode>,
    onToggle: ((Bool) -> Void)? = nil,
    @ViewBuilder label: @escaping (Bool) -> Label = { isEditing in
      Text(isEditing ? "Done" : "Edit")
    }
  ) {
    self._editMode = editMode
    self.onToggle = onToggle
    self.label = label
  }

  var body: some View {
    Button(
      action: {
        withAnimation {
          editMode = isEditing ? .inactive : .active
          onToggle?(isEditing)
        }
      },
      label: {
        label(isEditing)
      }
    )
  }
}

#Preview {
  @Previewable @State var editMode: EditMode = .inactive

  VStack(spacing: 20) {
    // Default Everything
    EditButton(editMode: $editMode)

    // Custom Toggle Only
    EditButton(editMode: $editMode) { isEditing in
      print("Now editing?: \(isEditing ? "yes" : "no")")
    }

    // Custom Label Only
    EditButton(
      editMode: $editMode,
      label: { isEditing in
        Text(isEditing ? "Finish Editing" : "Start Editing")
          .bold()
          .foregroundColor(.blue)
      }
    )

    // Custom Button Style Only
    EditButton(editMode: $editMode)
      .padding()
      .background(editMode == .active ? Color.green : Color.white)
      .cornerRadius(8)
      .shadow(radius: 3)

    // Custom Everything
    EditButton(
      editMode: $editMode,
      onToggle: { isEditing in
        print("Editing mode is now: \(isEditing ? "Active" : "Inactive")")
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
        .fill(editMode == .active ? Color.blue : Color.black)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.white, lineWidth: 2)
    )
    .foregroundStyle(Color.white)
  }
  .padding()
}

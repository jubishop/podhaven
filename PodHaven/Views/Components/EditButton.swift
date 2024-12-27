import SwiftUI

struct EditButton<Label: View, StyledButton: View>: View {
  @Environment(\.editMode) private var editMode
  var onToggle: ((Bool) -> Void)?
  var label: (Bool) -> Label
  var buttonStyle: (Button<Label>, Bool) -> StyledButton

  init(
    onToggle: ((Bool) -> Void)? = nil,
    @ViewBuilder label: @escaping (Bool) -> Label = { isEditing in
      Text(isEditing ? "Done" : "Edit")
    },
    @ViewBuilder buttonStyle: @escaping (Button<Label>, Bool) -> StyledButton
  ) {
    self.onToggle = onToggle
    self.label = label
    self.buttonStyle = buttonStyle
  }

  init(
    onToggle: ((Bool) -> Void)? = nil,
    @ViewBuilder label: @escaping (Bool) -> Text = { isEditing in
      Text(isEditing ? "Done" : "Edit")
    }
  ) where StyledButton == Button<Text>, Label == Text {
    self.init(
      onToggle: onToggle,
      label: label,
      buttonStyle: { button, _ in button }
    )
  }

  var body: some View {
    let isEditing = editMode?.wrappedValue == .active
    let button = Button(
      action: {
        withAnimation {
          editMode?.wrappedValue = isEditing ? .inactive : .active
          onToggle?(!isEditing)
        }
      },
      label: {
        label(isEditing)
      }
    )
    buttonStyle(button, isEditing)
  }
}

#Preview {
  VStack(spacing: 20) {
    // Default Everything
    EditButton()

    // Custom Toggle Only
    EditButton { isEditing in
      print("Now editing?: \(isEditing ? "yes" : "no")")
    }

    // Custom Label Only
    EditButton(
      label: { isEditing in
        Text(isEditing ? "Finish Editing" : "Start Editing")
          .bold()
          .foregroundColor(.blue)
      })

    // Custom Button Style Only
    EditButton(
      buttonStyle: { button, isEditing in
        button
          .padding()
          .background(isEditing ? Color.green : Color.red)
          .cornerRadius(8)
          .shadow(radius: 3)
      }
    )

    // Custom Everything
    EditButton(
      onToggle: { isEditing in
        print("Editing mode is now: \(isEditing ? "Active" : "Inactive")")
      },
      label: { isEditing in
        HStack {
          Image(systemName: isEditing ? "checkmark.circle" : "pencil.circle")
          Text(isEditing ? "Done Editing" : "Edit Mode")
        }
      },
      buttonStyle: { button, isEditing in
        button
          .padding(10)
          .background(
            RoundedRectangle(cornerRadius: 10)
              .fill(isEditing ? Color.blue : Color.gray)
              .animation(.easeInOut, value: isEditing)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Color.white, lineWidth: 2)
          )
          .foregroundStyle(isEditing ? Color.white : Color.black)
      }
    )
  }
  .padding()
}

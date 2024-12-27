// Copyright Justin Bishop, 2024

import SwiftUI

struct EditButton<Label: View>: View {
  @Environment(\.editMode) private var editMode
  var onToggle: ((Bool) -> Void)?
  var label: (Bool) -> Label
  var buttonStyle: (Button<Label>, Bool) -> AnyView

  init(
    onToggle: ((Bool) -> Void)? = nil,
    @ViewBuilder label: @escaping (Bool) -> Label = { isEditing in
      Text(isEditing ? "Done" : "Edit")
    },
    buttonStyle: @escaping (Button<Label>, Bool) -> AnyView = { button, _ in
      AnyView(button)
    }
  ) {
    self.onToggle = onToggle
    self.label = label
    self.buttonStyle = buttonStyle
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
    // Default EditButton
    EditButton()

    // Toggle Only
    EditButton { isEditing in
      print("now editing: \(isEditing ? "yes" : "no")")
    }

    // Custom Label Only
    EditButton(label: { isEditing in
      Text(isEditing ? "Finish Editing" : "Start Editing")
        .bold()
        .foregroundColor(.blue)
    })

    // Custom Button Style
    EditButton(
      label: { isEditing in
        Text(isEditing ? "Done" : "Edit")
          .padding()
      },
      buttonStyle: { button, isEditing in
        AnyView(
          button
            .background(isEditing ? Color.green : Color.red)
            .cornerRadius(8)
            .shadow(radius: 3)
        )
      }
    )

    // Custom Button Style and Toggle Action
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
        AnyView(
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
        )
      }
    )

    // Animated style
    EditButton(
      label: { isEditing in
        Text(isEditing ? "Finish Editing" : "Start Editing")
          .bold()
          .foregroundColor(.white)
      },
      buttonStyle: { button, isEditing in
        AnyView(
          button
            .padding(10)
            .background(
              RoundedRectangle(cornerRadius: 10)
                .fill(isEditing ? Color.blue : Color.gray)
                .animation(.easeInOut, value: isEditing)
            )
        )
      }
    )
  }
  .padding()
}

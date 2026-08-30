import SwiftUI

/// Shared multi-selection list used by catalog filter screens.
struct CatalogFilterSelectionView<Value: Hashable>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Set<Value>
    let label: (Value) -> String

    var body: some View {
        List {
            ForEach(values, id: \.self) { value in
                Button {
                    if selection.contains(value) {
                        selection.remove(value)
                    } else {
                        selection.insert(value)
                    }
                } label: {
                    HStack {
                        Text(label(value))
                            .foregroundStyle(.primary)

                        Spacer()

                        if selection.contains(value) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

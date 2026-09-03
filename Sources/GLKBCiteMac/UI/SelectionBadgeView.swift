import SwiftUI

struct SelectionBadgeView: View {
    let onFindCitations: () -> Void

    var body: some View {
        Button(action: onFindCitations) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(Color(nsColor: .selectedMenuItemTextColor))
                .background(.tint, in: Circle())
                .shadow(radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .help("Find citations with GLKB Cite")
        .accessibilityLabel("Find citations for selected text")
    }
}

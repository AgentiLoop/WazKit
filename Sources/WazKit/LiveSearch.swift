//
//  LiveSearch.swift
//  WazKit
//
//  The search text that filters a page's tiles (and Live TV's channels). It lives in its own object so
//  typing does not re-render the window and its toolbar, which would drop the field's focus. On the Mac
//  the field sits in the window toolbar; on iPhone the apps bind it to .searchable.
//
import SwiftUI
public final class LiveSearch: ObservableObject {
    @Published public var text = ""
    public init() {}
}
/// The toolbar's search field, with a clear (X) button while it has text.
public struct LiveSearchField: View {
    @ObservedObject var search: LiveSearch
    public init(search: LiveSearch) { self.search = search }
    public var body: some View {
        TextField("Search channels and shows", text: $search.text)
            .textFieldStyle(.roundedBorder)
            .overlay(alignment: .trailing) {
                if !search.text.isEmpty {
                    Button {
                        search.text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                    .help("Clear search")
                }
            }
            .frame(width: 220)
    }
}

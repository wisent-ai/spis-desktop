import SwiftUI
import WisentDesignSystem

// The reader for the page a search hit points at.
//
// Split out of `DocsCorpusView.swift`, which had grown past the
// three-hundred-line limit.

/// Full-text reader for the selected hit.
struct DocsReaderPane: View {
    @Environment(DocsCorpusModel.self) private var model

    var body: some View {
        Group {
            if model.pageLoading {
                // The same three zones the loaded page draws — header, rule,
                // scrolling body — so nothing moves when the text lands, and
                // so the body's bars measure the scroll view rather than the
                // window.
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        WisentSkeleton(.heading, width: 280, height: 20)
                        WisentSkeleton(.line, width: 220)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)

                    Divider()

                    ScrollView {
                        WisentSkeletonText(lines: 9, label: "Loading page")
                            .padding(20)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if let page = model.page {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(page.title.isEmpty ? page.url : page.title)
                            .font(.title3.bold())
                            .lineLimit(2)
                        Text(page.url)
                            .font(.caption)
                            .foregroundStyle(.link)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 10) {
                            ForEach(page.detailRows, id: \.0) { key, value in
                                Text("\(key): \(value)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)

                    Divider()

                    ScrollView {
                        Text(page.text)
                            .font(.system(.body, design: .serif))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                }
            } else if let hit = model.selectedHit {
                ContentUnavailableView(
                    "Could not load page",
                    systemImage: "exclamationmark.triangle",
                    description: Text("No readable text is available for \(hit.url).")
                )
            } else {
                ContentUnavailableView(
                    "Select a result",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Pick a search hit to read its extracted full text.")
                )
            }
        }
    }
}

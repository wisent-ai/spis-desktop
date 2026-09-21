import SwiftUI
import WisentDesignSystem

// The documentation corpus on screen: the site list, the streaming search
// and the page reader.
//
// The model these views drive is Docs/DocsCorpusModel.swift; they were one
// 518-line file until 2026-09-21, past the three-hundred-line limit.

struct DocsCorpusView: View {
    @State private var model = DocsCorpusModel()

    var body: some View {
        NavigationSplitView {
            DocsSidebar()
        } detail: {
            if let error = model.loadError {
                ContentUnavailableView(
                    "Documentation unavailable",
                    systemImage: "questionmark.folder",
                    description: Text(error)
                )
            } else {
                DocsSearchPane()
                    .task { await model.loadSites() }
                    .onDisappear { model.cancelAll() }
            }
        }
        .environment(model)
    }
}

private extension DocsCorpusModel {
    func cancelAll() {
        searchTask?.cancel()
        pageTask?.cancel()
        searching = false
        pageLoading = false
    }
}

/// Sidebar: the 50-site list with crawl progress.
struct DocsSidebar: View {
    @Environment(DocsCorpusModel.self) private var model

    var body: some View {
        Group {
            if model.sites.isEmpty && model.sitesLoading {
                // Inside a scroll view, like the list it stands in for: the
                // skeleton's own bars measure their nearest scrolling
                // container, and with none they would measure the window.
                ScrollView {
                    WisentSkeletonList(rows: 8, lines: 2, media: false, label: "Loading sites")
                        .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            } else {
                List(model.sites) { site in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(site.name)
                                .font(.body)
                                .lineLimit(1)
                            Spacer()
                            if site.done {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .help("Complete")
                            }
                        }
                        Text("\(site.cumulativeOK) available · \(site.inventoryURLCount) total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: site.progress)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            }
        }
        .refreshable { await model.loadSites() }
        .overlay(alignment: .bottom) {
            // A refresh of a list already on screen replaces nothing, so it
            // stays a badge and the rows underneath stay put. It is out of the
            // first read, where the skeleton list above is the region's one
            // announcement.
            if model.sitesLoading && !model.sites.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
                .padding(6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Refreshing sites")
            }
        }
    }
}

/// Search field, live progress line, and the streaming hit list.
struct DocsSearchPane: View {
    @Environment(DocsCorpusModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search full text (min 2 characters)", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { model.queryChanged() }
                        .onChange(of: model.query) { _, _ in model.queryChanged() }
                    if model.searching {
                        // A scan in flight inside a text field: too small for a
                        // panel, and impersonating nothing, so it is the plain
                        // spinner it describes. The results pane below carries
                        // the region's progress report.
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Searching")
                    } else if !model.query.isEmpty {
                        Button {
                            model.query = ""
                            model.queryChanged()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.query.isEmpty)
                    }
                }
                .padding(8)

                Divider()

                if !model.progressText.isEmpty || model.scannedPages > 0 {
                    HStack(spacing: 8) {
                        Text(model.progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(model.hits.count) result\(model.hits.count == 1 ? "" : "s")")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }

                if model.hits.isEmpty {
                    Group {
                        if model.searching {
                            // A scan already in flight, not content being read:
                            // it has no unloaded target to impersonate, so it
                            // reports its real status.
                            WisentProgressPanel(
                                title: "Searching",
                                detail: "Scanning the documentation corpus site by site."
                            )
                            .padding(20)
                        } else {
                            ContentUnavailableView(
                                "No results yet",
                                systemImage: "text.magnifyingglass",
                                description: Text("Enter at least 2 characters to search.")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(model.hits) { hit in
                        DocsHitRow(hit: hit, isSelected: model.selectedHit?.url == hit.url)
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(hit) }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(minWidth: 360, idealWidth: 440)

            DocsReaderPane()
                .frame(minWidth: 380)
        }
    }
}

struct DocsHitRow: View {
    let hit: DocsSearchHit
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hit.title?.isEmpty == false ? hit.title! : hit.url)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
            Text(hit.snippet ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(hit.site)
                    .font(.caption2)
                Text(hit.url)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
    }
}


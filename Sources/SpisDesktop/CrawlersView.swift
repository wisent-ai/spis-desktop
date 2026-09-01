import SwiftUI

struct CrawlersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "book.circle")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Crawlers")
                            .font(.headline)
                        Text("Run evidence capture for interface families")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                Text("All families from the evidence corpus:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        Text("iOS apps, Android apps").font(.caption)
                        Text("macOS apps, desktop apps").font(.caption)
                        Text("Web apps (8 families)").font(.caption)
                        Text("Terminal applications").font(.caption)
                        Text("Command-line tools").font(.caption)
                        Text("Documentation sites").font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    Button(action: { model.load() }) {
                        Label("Reload Catalogs", systemImage: "arrow.clockwise")
                    }

                    Spacer()
                }
                .font(.caption)
            }
            .padding(16)
            .background(Color(.controlBackgroundColor))

            Divider()

            if model.catalogs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hourglass")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Awaiting implementation")
                        .font(.headline)
                    Text("Crawler execution requires `spis crawl start/status/resume/import` in core CLI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.controlBackgroundColor))
            } else {
                List(model.catalogs) { catalog in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(catalog.title)
                            .font(.headline)
                        Text(catalog.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Text("\(catalog.count) records")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(catalog.slug)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task { model.load() }
    }
}

#Preview {
    CrawlersView()
        .environment(AppModel())
}

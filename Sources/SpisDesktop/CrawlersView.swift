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
                        Text("Run evidence capture for all interface families")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                Text("This surface will coordinate real crawlers across Stado when the core CLI is ready. Available families:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        Text("Mobile: iOS apps, Android apps").font(.caption)
                        Text("Desktop: macOS apps, desktop apps").font(.caption)
                        Text("Web: 8 families (apps, dashboards, onboarding, stores, design systems, reports, pricing, landing)").font(.caption)
                        Text("Terminal & CLI: PTY-based crawlers").font(.caption)
                        Text("Documentation: HTTP-based corpus crawl").font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    Button(action: { model.load() }) {
                        Label("Reload Catalogs", systemImage: "arrow.clockwise")
                    }

                    Button(action: {}) {
                        Label("Start Crawl", systemImage: "play.circle")
                    }
                    .disabled(true)

                    Spacer()
                }
                .font(.caption)
            }
            .padding(16)
            .background(Color(.controlBackgroundColor))

            Divider()

            if model.catalogs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No catalogs loaded")
                        .font(.headline)
                    if let error = model.loadError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    } else {
                        Text("Tap Reload Catalogs to load available families")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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

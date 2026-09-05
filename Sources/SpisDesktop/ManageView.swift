import SwiftUI
import WisentDesignSystem

struct ManageView: View {
    @Environment(ManageModel.self) private var model

    var body: some View {
        NavigationSplitView {
            List {
                Section("Product types") {
                    ForEach(model.types) { type in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.title).font(.body)
                            Text("\(type.slug) · \(type.count) records")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .onTapGesture { model.loadReferences(for: type.slug) }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            VStack(spacing: 0) {
                if let slug = model.selectedCatalogSlug {
                    ReferencesManager(slug: slug)
                } else {
                    ContentUnavailableView("Select a product type", systemImage: "square.grid.2x2")
                        .frame(maxHeight: .infinity)
                }

                Divider()
                SpisCorpusAdoptionView()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)

                Divider()


                // Last on the surface, under the records it does not touch.
                // It sits outside the selection branch above because the
                // control has to be reachable whether or not a product type
                // is selected: a walkthrough you can only replay after
                // clicking into a catalog is a walkthrough half the operators
                // never find.
                SpisFirstRunWalkthroughRow()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
        }
        .task { model.reloadTypes() }
    }
}

struct ReferencesManager: View {
    @Environment(ManageModel.self) private var model
    let slug: String

    @State private var newName = ""
    @State private var newURL = ""
    @State private var newCategory = ""
    @State private var newNote = ""
    @State private var newImagePath = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                HStack {
                    TextField("Name", text: $newName).frame(width: 140)
                    TextField("Source URL", text: $newURL).frame(width: 220)
                    TextField("Category", text: $newCategory).frame(width: 140)
                    TextField("Selection note", text: $newNote)
                    TextField("Image path", text: $newImagePath).frame(width: 200)
                    Button("Add record") {
                        Task {
                            await model.addReference(
                                slug: slug,
                                name: newName,
                                sourceURL: newURL,
                                category: newCategory.isEmpty ? "uncategorized" : newCategory,
                                selectionNote: newNote.isEmpty ? "operator-added" : newNote,
                                visual: newImagePath
                            )
                            newName = ""; newURL = ""; newCategory = ""; newNote = ""; newImagePath = ""
                        }
                    }
                    .disabled(newName.isEmpty || newURL.isEmpty || newImagePath.isEmpty || model.running)
                }
                HStack {
                    TextField("Type title / description / rename", text: .constant("")).frame(width: 0)
                    Button("Derive guidelines draft") {
                        Task { await model.deriveGuidelines(slug: slug) }
                    }
                    Spacer()
                }
            }
            .padding(.horizontal).padding(.top, 8)

            List(model.references) { reference in
                HStack {
                    Text("\(reference.index)").monospacedDigit().frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reference.name).font(.body)
                        Text(reference.path).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(reference.evidenceStatus)
                        .font(.caption.bold())
                        .foregroundStyle(reference.evidenceStatus == "complete" ? .green : .orange)
                    Text("\(reference.evidenceGapCount) gaps")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Remove") {
                        Task { await model.removeReference(slug: slug, number: reference.number) }
                    }
                    .buttonStyle(.link)
                }
            }

            if model.running || model.output != nil {
                Divider()
                ConsoleOutput()
                    .padding(.horizontal).padding(.bottom, 12)
                    .frame(height: 170)
            }
        }
    }
}

struct ConsoleOutput: View {
    @Environment(ManageModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.running {
                // An operation already in flight, not content being read: the
                // console has no output yet to stand in for, so it reports the
                // operation's real status until the output lands.
                WisentProgressPanel(
                    title: model.statusText,
                    detail: "Spis is running this operation. Its output appears here when it finishes."
                )
            } else if let result = model.output {
                ScrollView {
                    Text(result.output.isEmpty ? "(no output)" : result.output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.succeeded ? .green : .red)
                    Text(result.refusal ?? "\(result.operation) finished")
                        .font(.caption)
                }
            }
        }
    }
}

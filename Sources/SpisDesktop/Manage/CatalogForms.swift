import SwiftUI

/// `spis catalog-type add`: a new product type with zero records. The
/// command's refusal (taken slug, invalid slug, refused index) shows in the
/// outcome panel verbatim.
struct NewCatalogForm: View {
    @Environment(ManageModel.self) private var model

    @State private var slug = ""
    @State private var title = ""
    @State private var description = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Slug (kebab-case)", text: $slug)
            TextField("Title", text: $title)
            TextField("Description", text: $description)
            Button("Add product type") {
                Task {
                    await model.addCatalog(slug: slug, title: title, description: description)
                    if model.output?.succeeded == true {
                        slug = ""
                        title = ""
                        description = ""
                    }
                }
            }
            .disabled(
                slug.isEmpty || title.isEmpty
                    || description.trimmingCharacters(in: .whitespaces).isEmpty || model.running)
        }
    }
}

/// `spis catalog-type edit` and `remove` for the selected product type.
/// Empty fields stay unchanged; removing a type that holds records asks first
/// and then passes `--force`.
struct CatalogEditor: View {
    @Environment(ManageModel.self) private var model
    let slug: String

    @State private var title = ""
    @State private var description = ""
    @State private var rename = ""
    @State private var confirmingRemoval = false

    /// The records the product type holds, or nil when the listing does not
    /// name the type or its count: an unknown count is asked about like a
    /// non-empty one, never read as none.
    private var recordCount: Int? {
        model.types.first { $0.slug == slug }?.count
    }

    private var removalQuestion: String {
        switch recordCount {
        case .some(let count):
            return "Remove \(slug) and its \(count) records?"
        case .none:
            return
                "Remove \(slug) and every record it holds? The listing does not say how many there are."
        }
    }

    var body: some View {
        HStack {
            TextField("New title", text: $title).frame(width: 180)
            TextField("New description", text: $description)
            TextField("New slug", text: $rename).frame(width: 180)
            Button("Save product type") {
                Task {
                    await model.editCatalog(
                        slug: slug, title: title, description: description, rename: rename)
                    if model.output?.succeeded == true {
                        title = ""
                        description = ""
                        rename = ""
                    }
                }
            }
            .disabled((title.isEmpty && description.isEmpty && rename.isEmpty) || model.running)
            Button("Remove product type", role: .destructive) {
                if recordCount != 0 {
                    confirmingRemoval = true
                } else {
                    Task { await model.removeCatalog(slug: slug, force: false) }
                }
            }
            .disabled(model.running)
        }
        .confirmationDialog(
            removalQuestion,
            isPresented: $confirmingRemoval
        ) {
            Button("Remove with its records", role: .destructive) {
                Task { await model.removeCatalog(slug: slug, force: true) }
            }
        } message: {
            Text("The records and their evidence files are deleted permanently.")
        }
    }
}

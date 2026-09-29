import SwiftUI

/// 类别管理：新增 / 改名 / 删除 / 排序，并可对未归类来源做一次自动归类。
/// 类别目录存在 LocalData 里，因此会随 JSON 备份一起迁移。
struct CategoriesSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var newName = ""
    @State private var autoAssignNotice: String?

    private var categories: [SourceCategory] { model.categories }

    var body: some View {
        Form {
            Section {
                ForEach(categories) { category in
                    NavigationLink {
                        CategoryEditorView(model: model, category: category)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.symbol)
                                .font(.body)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.displayName)
                                Text(String(format: AppLocalization.string("%lld sources"), Int64(count(of: category.id))))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets where categories.indices.contains(index) {
                        model.deleteCategory(categories[index].id)
                    }
                }
                .onMove { source, destination in
                    var updated = categories
                    updated.move(fromOffsets: source, toOffset: destination)
                    model.replaceCategories(updated)
                }
            } header: {
                Text("Categories")
            } footer: {
                Text("Sources are grouped by category on the Sources tab. Deleting a category moves its sources to “Other”; it never deletes a source.")
            }

            Section {
                HStack {
                    TextField("New category name", text: $newName)
                    Button("Add") { addCategory() }
                        .disabled(trimmedNewName.isEmpty)
                }
                Button {
                    let changed = model.autoCategorizeUnassigned()
                    autoAssignNotice = changed == 0
                        ? AppLocalization.string("Every source already has a category, or nothing could be inferred.")
                        : String(format: AppLocalization.string("Assigned categories to %lld sources."), Int64(changed))
                } label: {
                    Label("Auto-Categorize Unassigned Sources", systemImage: "wand.and.stars")
                }
            } header: {
                Text("Add & Organize")
            } footer: {
                Text("Auto-categorization only fills sources that have no category yet; it never overwrites your own choice.")
            }
        }
        .transparentListBackground()
        .navigationTitle("Categories")
        .toolbar { EditButton() }
        .alert("Done", isPresented: Binding(
            get: { autoAssignNotice != nil },
            set: { if !$0 { autoAssignNotice = nil } })) {
            Button("OK", role: .cancel) { autoAssignNotice = nil }
        } message: {
            Text(autoAssignNotice ?? "")
        }
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func count(of categoryID: String) -> Int {
        model.sources.filter { ($0.category ?? CategoryCatalog.uncategorizedID) == categoryID }.count
    }

    private func addCategory() {
        let name = trimmedNewName
        guard !name.isEmpty else { return }
        // 用 UUID 前缀做 id，保证与内置 slug 不会碰撞。
        var updated = categories
        updated.append(SourceCategory(id: "custom-\(UUID().uuidString.prefix(8))",
                                      customName: name, symbol: "tag"))
        model.replaceCategories(updated)
        newName = ""
    }
}

/// 单个类别：改名与换图标。
struct CategoryEditorView: View {
    @ObservedObject var model: AppModel
    let category: SourceCategory
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String

    /// 常用 SF Symbol，足够覆盖技术类目。
    private static let symbols = [
        "brain", "server.rack", "hammer", "network", "externaldrive",
        "square.grid.2x2", "tag", "cpu", "shippingbox", "lock.shield",
        "cloud", "terminal", "antenna.radiowaves.left.and.right", "paintbrush",
        "chart.bar", "gamecontroller", "camera", "music.note",
    ]

    init(model: AppModel, category: SourceCategory) {
        self.model = model
        self.category = category
        _name = State(initialValue: category.displayName)
        _symbol = State(initialValue: category.symbol)
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Category name", text: $name)
            }
            Section("Icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], spacing: 12) {
                    ForEach(Self.symbols, id: \.self) { candidate in
                        Button { symbol = candidate } label: {
                            Image(systemName: candidate)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(symbol == candidate ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(symbol == candidate ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(symbol == candidate ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .transparentListBackground()
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var updated = model.categories
                    guard let index = updated.firstIndex(where: { $0.id == category.id }) else { return dismiss() }
                    // 名称与内置本地化名一致时不必存自定义名，保留本地化能力。
                    let builtInName = AppLocalization.string(CategoryCatalog.nameKey(category.id))
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated[index].customName = (trimmed.isEmpty || trimmed == builtInName) ? nil : trimmed
                    updated[index].symbol = symbol
                    model.replaceCategories(updated)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

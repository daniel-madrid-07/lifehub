import SwiftUI

struct ClothingDetailView: View {
    @State private var item: ClothingItem
    let onUpdate: (ClothingItem?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var actionError: String?

    init(item: ClothingItem, onUpdate: @escaping (ClothingItem?) -> Void) {
        self._item = State(initialValue: item)
        self.onUpdate = onUpdate
    }

    var body: some View {
        Screen(title: item.name) {
            photoSection
            stateButtons
            attributesCard
            colorsSection
            tagsSection
            notesSection

            if let err = actionError {
                Text(err).font(Theme.dCaption).foregroundStyle(Theme.bad)
            }

            HButton(haptic: Haptics.medium) { showDeleteConfirm = true } label: {
                Label("Eliminar prenda", systemImage: "trash")
                    .font(Theme.dHeadline)
                    .foregroundStyle(Theme.bad)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .secondaryGlass(Theme.bad)
            .confirmationDialog("Eliminar prenda", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) { Task { await deleteItem() } }
            } message: {
                Text("Esta accion no se puede deshacer.")
            }
        }
        .toolbarBackground(Theme.bg, for: .navigationBar)
    }

    // ── Secciones ─────────────────────────────────────────────────────────────

    var photoSection: some View {
        Group {
            if let url = item.photo_url.flatMap({ API.shared.imageURL($0) }) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(maxWidth: .infinity, minHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else { photoPlaceholder }
                }
            } else {
                photoPlaceholder
            }
        }
    }

    var photoPlaceholder: some View {
        ZStack {
            Theme.surface2
            Image(systemName: item.category.icon)
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    var stateButtons: some View {
        HStack(spacing: 10) {
            stateBtn("Sucia", icon: "xmark.circle.fill", color: Theme.bad,
                     active: item.state == .dirty) {
                await setState(item.state == .dirty ? .clean : .dirty)
            }
            stateBtn("Lavadora", icon: "arrow.clockwise.circle.fill", color: Theme.accent2,
                     active: item.state == .washing) {
                await setState(item.state == .washing ? .clean : .washing)
            }
            stateBtn("Limpia", icon: "checkmark.circle.fill", color: Theme.good,
                     active: item.state == .clean) {
                if item.state != .clean { await setState(.clean) }
            }
        }
    }

    var attributesCard: some View {
        VStack(spacing: 10) {
            infoRow("Categoria",    value: item.category.label)
            if !item.subcategory.isEmpty {
                infoRow("Subcategoria", value: item.subcategory)
            }
            infoRow("Formalidad",   value: dots(item.formality))
            infoRow("Calor",        value: dots(item.warmth))
            infoRow("Reutilizacion",value: item.reuse_days == 0 ? "Cambio diario" : "Cada \(item.reuse_days) dia(s)")
            infoRow("Estado",       value: item.state.label)
            if let last = item.last_used {
                infoRow("Ultimo uso",   value: Fmt.short(last))
            }
            infoRow("Usos (14 dias)", value: "\(item.uses_14d)")
        }
        .card()
    }

    @ViewBuilder
    var colorsSection: some View {
        if !item.colors.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Colores")
                FlowLayout(spacing: 8) {
                    ForEach(item.colors, id: \.code) { c in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: c.code.hex))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                            Text("\(c.code.label) \(Int(c.pct * 100))%")
                                .font(Theme.dCaption)
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.surface, in: Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    var tagsSection: some View {
        if !item.tags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Etiquetas")
                FlowLayout(spacing: 6) {
                    ForEach(item.tags, id: \.self) { tag in
                        Text(tag)
                            .font(Theme.dCaption)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                    }
                }
            }
        }
    }

    @ViewBuilder
    var notesSection: some View {
        if let notes = item.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Notas")
                Text(notes)
                    .font(Theme.dSubheadline)
                    .foregroundStyle(Theme.muted)
                    .card()
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    @ViewBuilder
    func stateBtn(_ title: String, icon: String, color: Color, active: Bool,
                  action: @escaping () async -> Void) -> some View {
        HButton(haptic: Haptics.light) { Task { await action() } } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(Theme.dCaption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(active ? color : Theme.muted)
        }
        .secondaryGlass()
    }

    func infoRow(_ key: String, value: String) -> some View {
        HStack {
            Text(key).font(Theme.dSubheadline).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(Theme.dSubheadline.weight(.medium)).foregroundStyle(Theme.ink)
        }
    }

    func dots(_ n: Int) -> String {
        String(repeating: "●", count: n) + String(repeating: "○", count: 5 - n)
    }

    func setState(_ newState: ClothingState) async {
        do {
            let updated: ClothingItem
            switch newState {
            case .clean:   updated = try await API.shared.washedClothing(item.id)
            case .dirty, .washing: updated = try await API.shared.dirtyClothing(item.id)
            }
            item = updated
            onUpdate(updated)
        } catch {
            actionError = error.localizedDescription
        }
    }

    func deleteItem() async {
        do {
            _ = try await API.shared.deleteClothing(item.id)
            onUpdate(nil)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

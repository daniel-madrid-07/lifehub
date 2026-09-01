import SwiftUI

struct WardrobeView: View {
    @State private var tab = 0
    var body: some View {
        Screen(title: "Ropa") {
            Picker("", selection: $tab) {
                Text("Outfit del dia").tag(0)
                Text("Armario").tag(1)
            }
            .pickerStyle(.segmented)
            .onChange(of: tab) { _, _ in Haptics.selection() }

            switch tab {
            case 0: OutfitDaySection()
            default: CatalogSection()
            }
        }
    }
}

// ── Outfit del dia ───────────────────────────────────────────────────────────

struct OutfitDaySection: View {
    @State private var suggestion: OutfitSuggestion?
    @State private var loading = true
    @State private var error: String?
    @State private var confirmed = false
    @State private var selectedAlt: OutfitSlot?

    var slot: OutfitSlot? { selectedAlt ?? suggestion?.main }

    var body: some View {
        Group {
            if loading {
                SkeletonList(rows: 3)
            } else if let err = error {
                ErrorCard(detail: err) { await load() }
            } else if let s = suggestion, let sl = slot {
                outfitContent(s, slot: sl)
            } else {
                EmptyState(text: "Añade ropa al armario para recibir sugerencias de outfit")
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    func outfitContent(_ s: OutfitSuggestion, slot: OutfitSlot) -> some View {
        HStack {
            Text(s.formality_context)
                .font(Theme.dSubheadline)
                .foregroundStyle(Theme.muted)
            Spacer()
            Text("\(Int(slot.score * 100))%")
                .font(Theme.dSubheadline.weight(.semibold))
                .foregroundStyle(scoreColor(slot.score))
        }

        OutfitSlotCard(slot: slot)

        if !s.stock_alerts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(s.stock_alerts, id: \.self) { alert in
                    Label(alert, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.dCaption)
                        .foregroundStyle(Theme.accent2)
                }
            }
            .card(padding: 12)
        }

        CoachCard { try await API.shared.aiOutfit() }

        if confirmed {
            Label("Outfit confirmado para hoy", systemImage: "checkmark.circle.fill")
                .font(Theme.dSubheadline.weight(.medium))
                .foregroundStyle(Theme.good)
                .frame(maxWidth: .infinity, alignment: .center)
                .card()
        } else {
            HStack(spacing: 12) {
                HButton(haptic: Haptics.success) {
                    Task { await confirmOutfit(slot) }
                } label: {
                    Text("Confirmar")
                        .font(Theme.dHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .actionGlass()

                HButton(haptic: Haptics.medium) {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(Theme.dHeadline)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                }
                .secondaryGlass()
            }
        }

        if !s.alternatives.isEmpty {
            SectionHeader(title: "Alternativas")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(s.alternatives.enumerated()), id: \.offset) { _, alt in
                        AlternativeCard(slot: alt, selected: selectedAlt == alt) {
                            Haptics.selection()
                            selectedAlt = (selectedAlt == alt) ? nil : alt
                        }
                    }
                }
            }
        }

        if let afternoon = s.afternoon, let label = s.afternoon_label {
            SectionHeader(title: label)
            OutfitSlotCard(slot: afternoon)
        }
    }

    func load() async {
        loading = true; error = nil; confirmed = false; selectedAlt = nil
        do { suggestion = try await API.shared.outfitToday() }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    func confirmOutfit(_ slot: OutfitSlot) async {
        let ids = slot.displayItems.map(\.id)
            + [slot.socks?.id, slot.underwear?.id].compactMap { $0 }
        for id in ids { _ = try? await API.shared.wearClothing(id) }
        confirmed = true
    }

    func scoreColor(_ s: Double) -> Color {
        s >= 0.80 ? Theme.good : s >= 0.65 ? Theme.accent2 : Theme.bad
    }
}

struct OutfitSlotCard: View {
    let slot: OutfitSlot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(slot.displayItems) { item in
                        ClothingThumb(item: item, size: 82)
                    }
                }
            }
            let invisible = [slot.socks?.name, slot.underwear?.name].compactMap { $0 }
            if !invisible.isEmpty {
                Text(invisible.joined(separator: " · "))
                    .font(Theme.dCaption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .card()
    }
}

struct AlternativeCard: View {
    let slot: OutfitSlot
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(slot.displayItems.prefix(3)) { item in
                        ClothingThumb(item: item, size: 50)
                    }
                }
                Text("\(Int(slot.score * 100))%")
                    .font(Theme.dCaption.weight(.semibold))
                    .foregroundStyle(selected ? Theme.accent : Theme.muted)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surface.opacity(selected ? 1 : 0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ClothingThumb: View {
    let item: ClothingItem
    let size: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            photoView
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.15, style: .continuous))

            if size >= 70 {
                Text(item.name)
                    .font(Theme.dCaption2)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .frame(width: size)
            }
        }
    }

    @ViewBuilder
    var photoView: some View {
        if let url = item.photo_url.flatMap({ API.shared.imageURL($0) }) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    var placeholderView: some View {
        ZStack {
            Theme.surface2
            Image(systemName: item.category.icon)
                .font(.system(size: size * 0.35))
                .foregroundStyle(Theme.muted)
        }
    }
}

// ── Catalogo ─────────────────────────────────────────────────────────────────

struct CatalogSection: View {
    @State private var items: [ClothingItem] = []
    @State private var loading = true
    @State private var filter: ClothingCategory? = nil
    @State private var showAdd = false

    var filtered: [ClothingItem] {
        filter == nil ? items : items.filter { $0.category == filter }
    }

    var body: some View {
        Group {
            if loading {
                SkeletonList(rows: 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CatChip(label: "Todo", selected: filter == nil) { filter = nil }
                        ForEach(ClothingCategory.allCases) { cat in
                            CatChip(label: cat.label, selected: filter == cat) { filter = cat }
                        }
                    }
                }

                if filtered.isEmpty {
                    EmptyState(text: "No hay prendas en esta categoria")
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        ForEach(filtered) { item in
                            NavigationLink {
                                ClothingDetailView(item: item) { updated in
                                    if let u = updated {
                                        if let i = items.firstIndex(where: { $0.id == u.id }) {
                                            items[i] = u
                                        }
                                    } else {
                                        items.removeAll { $0.id == item.id }
                                    }
                                }
                            } label: {
                                ClothingGridCell(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HButton(haptic: Haptics.medium) { showAdd = true } label: {
                    Label("Añadir prenda", systemImage: "plus")
                        .font(Theme.dHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .actionGlass()
            }
        }
        .task { await loadItems() }
        .sheet(isPresented: $showAdd) {
            AddClothingView { newItem in items.append(newItem) }
        }
    }

    func loadItems() async {
        loading = true
        items = (try? await API.shared.wardrobe()) ?? []
        loading = false
    }
}

// ── Componentes de catalogo ───────────────────────────────────────────────────

struct CatChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            Text(label)
                .font(Theme.dCaption.weight(.medium))
                .foregroundStyle(selected ? Theme.accentInk : Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Theme.accent : Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ClothingGridCell: View {
    let item: ClothingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                photoView
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Circle()
                    .fill(item.state.uiColor)
                    .frame(width: 10, height: 10)
                    .padding(8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(Theme.dCaption.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(item.subcategory.isEmpty ? item.category.label : item.subcategory)
                    .font(Theme.dCaption2)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    var photoView: some View {
        if let url = item.photo_url.flatMap({ API.shared.imageURL($0) }) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { placeholderView }
            }
        } else {
            placeholderView
        }
    }

    var placeholderView: some View {
        ZStack {
            Theme.surface2
            Image(systemName: item.category.icon)
                .font(.title2)
                .foregroundStyle(Theme.muted)
        }
    }
}

// ── Shared extensions ─────────────────────────────────────────────────────────

extension ClothingState {
    var uiColor: Color {
        switch self {
        case .clean:   return Theme.good
        case .dirty:   return Theme.bad
        case .washing: return Theme.accent2
        }
    }
}

// Simple flow layout for tags (used by AddClothingView and ClothingDetailView)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

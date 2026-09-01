import SwiftUI
import PhotosUI

struct AddClothingView: View {
    let onSave: (ClothingItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: ClothingCategory = .tops
    @State private var subcategory = ""
    @State private var selectedColors: [ColorCode] = []
    @State private var formality: Double = 3
    @State private var warmth: Double = 3
    @State private var reuseDays: Int = 1
    @State private var tagsInput = ""
    @State private var tags: [String] = []
    @State private var notes = ""

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var saving = false
    @State private var error: String?

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedColors.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    photoPicker
                    nameField
                    categoryPicker
                    subcategoryField
                    colorPicker
                    sliderRow("Formalidad", value: $formality, lo: "Deportivo", hi: "Formal")
                    sliderRow("Calor", value: $warmth, lo: "Fresco", hi: "Abrigado")
                    reuseStepper
                    tagsField
                    notesField

                    if let err = error {
                        Text(err).font(Theme.dCaption).foregroundStyle(Theme.bad)
                    }

                    HButton(haptic: Haptics.medium) { Task { await save() } } label: {
                        Group {
                            if saving { ProgressView().tint(Theme.accentInk) }
                            else { Text("Guardar prenda").font(Theme.dHeadline) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .actionGlass()
                    .disabled(!canSave || saving)
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Nueva prenda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.foregroundStyle(Theme.muted)
                }
            }
        }
    }

    // ── Secciones ─────────────────────────────────────────────────────────────

    var photoPicker: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            ZStack {
                if let data = imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    Theme.surface
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill").font(.title).foregroundStyle(Theme.muted)
                        Text("Foto de la prenda").font(Theme.dCaption).foregroundStyle(Theme.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .onChange(of: selectedPhoto) { _, item in
            Task { imageData = try? await item?.loadTransferable(type: Data.self) }
        }
    }

    var nameField: some View {
        fieldSection("Nombre") {
            TextField("Ej. Camisa oxford azul", text: $name)
                .textFieldStyle(.plain).font(Theme.dBody).foregroundStyle(Theme.ink)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    var categoryPicker: some View {
        fieldSection("Categoria") {
            LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 4), spacing: 8) {
                ForEach(ClothingCategory.allCases) { cat in
                    CatOption(cat: cat, selected: category == cat) {
                        category = cat
                        reuseDays = cat.defaultReuseDays
                    }
                }
            }
        }
    }

    var subcategoryField: some View {
        let opts = category.subcategoryOptions
        return fieldSection("Subcategoria") {
            Menu {
                ForEach(opts, id: \.self) { opt in
                    Button(opt) { subcategory = opt }
                }
            } label: {
                HStack {
                    Text(subcategory.isEmpty ? "Seleccionar..." : subcategory)
                        .font(Theme.dBody)
                        .foregroundStyle(subcategory.isEmpty ? Theme.muted : Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Theme.dCaption).foregroundStyle(Theme.muted)
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            .onChange(of: category) { _, _ in subcategory = "" }
        }
    }

    var colorPicker: some View {
        fieldSection("Colores (1 = dominante, hasta 4)") {
            LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 5), spacing: 10) {
                ForEach(ColorCode.allCases) { code in
                    ColorChipOption(
                        code: code,
                        selectionIndex: selectedColors.firstIndex(of: code)
                    ) {
                        if selectedColors.contains(code) {
                            selectedColors.removeAll { $0 == code }
                        } else if selectedColors.count < 4 {
                            selectedColors.append(code)
                        }
                    }
                }
            }
        }
    }

    var reuseStepper: some View {
        fieldSection("Dias de reutilizacion") {
            HStack {
                Text(reuseDays == 0
                     ? "Se cambia cada dia"
                     : "Puede repetirse \(reuseDays) dia\(reuseDays > 1 ? "s" : "") seguido\(reuseDays > 1 ? "s" : "")")
                    .font(Theme.dSubheadline).foregroundStyle(Theme.muted)
                Spacer()
                Stepper("", value: $reuseDays, in: 0...14).labelsHidden()
            }
            .card()
        }
    }

    var tagsField: some View {
        fieldSection("Etiquetas") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("lluvia, universidad, formal...", text: $tagsInput)
                        .textFieldStyle(.plain).font(Theme.dBody).foregroundStyle(Theme.ink)
                        .onSubmit { addTag() }
                    Button("Añadir", action: addTag)
                        .font(Theme.dCaption.weight(.medium)).foregroundStyle(Theme.accent)
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))

                if !tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            TagPill(text: tag) { tags.removeAll { $0 == tag } }
                        }
                    }
                }
            }
        }
    }

    var notesField: some View {
        fieldSection("Notas (opcional)") {
            TextField("Ej. solo para invierno, talla M...", text: $notes, axis: .vertical)
                .lineLimit(3...)
                .textFieldStyle(.plain).font(Theme.dBody).foregroundStyle(Theme.ink)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    func sliderRow(_ title: String, value: Binding<Double>, lo: String, hi: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                fieldLabel(title)
                Spacer()
                Text(lo).font(Theme.dCaption).foregroundStyle(Theme.muted)
                Text("·").font(Theme.dCaption).foregroundStyle(Theme.muted)
                Text(hi).font(Theme.dCaption).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { v in
                    Button {
                        Haptics.selection()
                        value.wrappedValue = Double(v)
                    } label: {
                        Text("\(v)")
                            .font(Theme.dSubheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(Int(value.wrappedValue) == v ? Theme.accentInk : Theme.ink)
                            .background(
                                Int(value.wrappedValue) == v ? Theme.accent : Theme.surface,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    @ViewBuilder
    func fieldSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(title)
            content()
        }
    }

    func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.dCaption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(Theme.muted)
    }

    func addTag() {
        let t = tagsInput.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !tags.contains(t) else { return }
        tags.append(t); tagsInput = ""
    }

    func save() async {
        saving = true; error = nil
        do {
            let n = selectedColors.count
            let colorData: [JSONValue] = selectedColors.enumerated().map { i, code in
                let pct = n == 1 ? 1.0 : (i == 0 ? 0.6 : 0.4 / Double(n - 1))
                return .object(["code": .string(code.rawValue), "pct": .double(pct)])
            }
            let body: [String: JSONValue] = [
                "name":       .string(name.trimmingCharacters(in: .whitespaces)),
                "category":   .string(category.rawValue),
                "subcategory":.string(subcategory.trimmingCharacters(in: .whitespaces)),
                "colors":     .array(colorData),
                "formality":  .int(Int(formality)),
                "warmth":     .int(Int(warmth)),
                "reuse_days": .int(reuseDays),
                "tags":       .array(tags.map { .string($0) }),
                "notes":      notes.isEmpty ? .null : .string(notes)
            ]
            var item = try await API.shared.createClothing(body)
            if let data = imageData {
                item = (try? await API.shared.uploadClothingPhoto(item.id, imageData: data)) ?? item
            }
            onSave(item)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}

// ── Sub-componentes de formulario ─────────────────────────────────────────────

struct CatOption: View {
    let cat: ClothingCategory
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            VStack(spacing: 4) {
                Image(systemName: cat.icon).font(.system(size: 17))
                Text(cat.label).font(Theme.dCaption2).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? Theme.accentInk : Theme.ink)
            .background(selected ? Theme.accent : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct ColorChipOption: View {
    let code: ColorCode
    let selectionIndex: Int?   // nil = no seleccionado; 0 = primario, 1 = secundario…
    let action: () -> Void

    private var selected: Bool { selectionIndex != nil }

    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color(hex: code.hex))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                    if let idx = selectionIndex {
                        Text("\(idx + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(code.hex > 0x888888 ? Color.black : Color.white)
                    }
                }
                .overlay(
                    Circle()
                        .strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 2)
                        .padding(-3)
                )
                Text(code.label)
                    .font(.system(size: 8))
                    .foregroundStyle(selected ? Theme.ink : Theme.muted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct TagPill: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(Theme.dCaption).foregroundStyle(Theme.ink)
            Button(action: { Haptics.light(); onRemove() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}

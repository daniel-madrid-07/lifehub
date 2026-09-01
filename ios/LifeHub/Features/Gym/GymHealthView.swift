import SwiftUI
import Charts
import PhotosUI

/// Salud: peso corporal, perímetros, fotos de progreso y datos de Apple Health
/// que llegan al backend (pasos, sueño, pulso).
struct GymHealthView: View {
    @State private var bodyweight: [BodyWeightEntry] = []
    @State private var measures: Measures = [:]
    @State private var photos: [ProgressPhotoItem] = []
    @State private var healthDays: [HealthDay] = []
    @State private var loaded = false

    @State private var newWeight = ""
    @State private var photoPick: PhotosPickerItem?

    var body: some View {
        Screen(title: "Salud", refresh: { await load() }) {
            if !loaded {
                SkeletonList()
            } else {
                // ── Peso corporal ──
                SectionHeader(title: "Peso corporal")
                HStack {
                    TextField("Peso (kg)", text: $newWeight)
                        .keyboardType(.decimalPad)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.ink)
                    Button {
                        Task { await addWeight() }
                    } label: {
                        Text("Apuntar")
                            .font(Theme.dSubheadline.weight(.bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.black)
                    }
                    .disabled(Double(newWeight.replacingOccurrences(of: ",", with: ".")) == nil)
                }

                if bodyweight.count > 1 {
                    let vals = bodyweight.map(\.weight)
                    let lo = vals.min() ?? 0, hi = vals.max() ?? 1
                    let pad = max((hi - lo) * 0.2, 0.5)
                    Chart(bodyweight.reversed(), id: \.id) { entry in
                        LineMark(
                            x: .value("Fecha", Fmt.date(entry.at) ?? .now),
                            y: .value("Peso", entry.weight)
                        )
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.monotone)
                        PointMark(
                            x: .value("Fecha", Fmt.date(entry.at) ?? .now),
                            y: .value("Peso", entry.weight)
                        )
                        .foregroundStyle(Theme.accent)
                    }
                    .chartYScale(domain: (lo - pad)...(hi + pad))
                    .frame(height: 160)
                    .clipped()
                    .card()
                }

                // Historial: cada pesada con su fecha (deslizar para borrar).
                if !bodyweight.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(bodyweight) { entry in
                            HStack {
                                Text("\(entry.weight.clean) kg")
                                    .font(Theme.dHeadline)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text(Fmt.short(entry.at))
                                    .font(Theme.dCaption)
                                    .foregroundStyle(Theme.muted)
                                Button {
                                    Task {
                                        _ = try? await API.shared.gymDeleteBodyweight(entry.id)
                                        Haptics.warning()
                                        await load()
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundStyle(Theme.muted)
                                }
                                .padding(.leading, 8)
                            }
                            .padding(.vertical, 10)
                            if entry.id != bodyweight.last?.id {
                                Divider().overlay(Theme.line)
                            }
                        }
                    }
                    .card()
                }

                // ── Perímetros ──
                SectionHeader(title: "Perímetros")
                ForEach(["brazo", "pecho", "cintura", "pierna"], id: \.self) { site in
                    MeasureRow(site: site, entries: measures[site] ?? []) {
                        await load()
                    }
                }

                // ── Fotos de progreso ──
                SectionHeader(title: "Fotos de progreso")
                PhotosPicker(selection: $photoPick, matching: .images) {
                    Label("Subir foto", systemImage: "camera.fill")
                        .font(Theme.dSubheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Theme.accent)
                }
                .onChange(of: photoPick) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            _ = try? await API.shared.gymUploadPhoto(data)
                            await load()
                        }
                        photoPick = nil
                    }
                }

                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photos) { photo in
                                VStack(spacing: 4) {
                                    AsyncImage(url: API.shared.imageURL(photo.url)) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Theme.surface2
                                    }
                                    .frame(width: 110, height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text(Fmt.short(photo.at))
                                        .font(Theme.dCaption2)
                                        .foregroundStyle(Theme.muted)
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task {
                                            _ = try? await API.shared.gymDeletePhoto(photo.id)
                                            await load()
                                        }
                                    } label: {
                                        Label("Borrar", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Apple Health (vía Atajo → backend) ──
                if !healthDays.isEmpty {
                    SectionHeader(title: "Salud diaria")
                    ForEach(healthDays.prefix(7), id: \.day) { d in
                        HStack {
                            Text(Fmt.short(d.day))
                                .font(Theme.dSubheadline)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text([
                                d.steps.map { "\($0) pasos" },
                                d.sleep_hours.map { "\($0.clean) h sueño" },
                                d.resting_hr.map { "\($0) ppm" },
                            ].compactMap { $0 }.joined(separator: " · "))
                                .font(Theme.dCaption)
                                .foregroundStyle(Theme.muted)
                        }
                        .card(padding: 12)
                    }
                }
            }
        }
        .task { await load() }
    }

    func addWeight() async {
        guard let w = Double(newWeight.replacingOccurrences(of: ",", with: ".")) else { return }
        newWeight = ""
        _ = try? await API.shared.gymAddBodyweight(w)
        Haptics.success()
        await load()
    }

    func load() async {
        async let bw = try? API.shared.gymBodyweight()
        async let m = try? API.shared.gymMeasures()
        async let p = try? API.shared.gymPhotos()
        async let h = try? API.shared.health()
        bodyweight = await bw ?? []
        measures = await m ?? [:]
        photos = await p ?? []
        healthDays = await h ?? []
        loaded = true
    }
}

struct MeasureRow: View {
    let site: String
    let entries: [MeasureEntry]
    let onChange: () async -> Void

    @State private var value = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(site.capitalized)
                    .font(Theme.dSubheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let last = entries.first {
                    Text("\(last.value.clean) cm · \(Fmt.short(last.at))")
                        .font(Theme.dCaption)
                        .foregroundStyle(Theme.muted)
                } else {
                    Text("Sin datos")
                        .font(Theme.dCaption)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            TextField("cm", text: $value)
                .keyboardType(.decimalPad)
                .frame(width: 60)
                .padding(8)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Theme.ink)
            Button {
                Task {
                    guard let v = Double(value.replacingOccurrences(of: ",", with: ".")) else { return }
                    value = ""
                    _ = try? await API.shared.gymAddMeasure(site: site, value: v)
                    await onChange()
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
            .disabled(Double(value.replacingOccurrences(of: ",", with: ".")) == nil)
        }
        .card(padding: 13)
    }
}

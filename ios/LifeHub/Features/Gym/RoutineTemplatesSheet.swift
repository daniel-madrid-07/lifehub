import SwiftUI

/// Plantillas de rutina: en vez de crear cinco rutinas a mano, eliges un
/// esquema de entrenamiento y luego lo editas a tu gusto.
struct RoutineTemplatesSheet: View {
    var onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var templates: [RoutineTemplate] = []
    @State private var loaded = false
    @State private var applying: String?
    @State private var sets = 3
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ErrorCard(detail: error) { await load() }
                } else if !loaded {
                    SkeletonList()
                } else {
                    List {
                        Section {
                            Stepper("Series por ejercicio: \(sets)", value: $sets, in: 1...6)
                        } footer: {
                            Text("Puedes cambiarlo después en cada rutina.")
                        }

                        ForEach(templates) { template in
                            Section {
                                Button {
                                    Task { await apply(template) }
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(template.name)
                                                .font(Theme.dHeadline)
                                                .foregroundStyle(Theme.ink)
                                            Text(template.description)
                                                .font(Theme.dCaption)
                                                .foregroundStyle(Theme.muted)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text(template.routines.joined(separator: " · "))
                                                .font(Theme.dCaption)
                                                .foregroundStyle(Theme.muted.opacity(0.7))
                                                .padding(.top, 2)
                                        }
                                        Spacer()
                                        if applying == template.id {
                                            ProgressView()
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .disabled(applying != nil)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plantillas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            templates = try await API.shared.routineTemplates()
            error = nil
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func apply(_ template: RoutineTemplate) async {
        applying = template.id
        defer { applying = nil }
        do {
            _ = try await API.shared.applyRoutineTemplate(template.id, sets: sets)
            Haptics.success()
            await onDone()
            dismiss()
        } catch {
            self.error = "No se pudo aplicar la plantilla."
        }
    }
}

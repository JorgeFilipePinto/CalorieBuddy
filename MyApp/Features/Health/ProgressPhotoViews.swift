import SwiftUI

// MARK: - Saúde section

/// "Evolução Física" in the Saúde tab: the latest photo session, a button to log a new one and
/// the link to the full history with side-by-side comparison.
struct ProgressPhotosSection: View {
    @Environment(DataStore.self) private var store
    /// Owned by the screen: a sheet attached to a section inside a `List` gets dismissed as soon
    /// as the list re-renders that section.
    @Binding var showingLog: Bool

    var body: some View {
        let sessions = ProgressSession.group(store.progressPhotos)
        Section {
            if let latest = sessions.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Última sessão · " + latest.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressSessionStrip(session: latest, size: 96)
                }
                .padding(.vertical, 4)
            }

            Button {
                showingLog = true
            } label: {
                Label("Registar Fotos", systemImage: "camera.fill")
            }

            if !sessions.isEmpty {
                NavigationLink {
                    ProgressPhotosView()
                } label: {
                    Label("Comparar e Ver Histórico", systemImage: "rectangle.split.2x1")
                }
            }
        } header: {
            Text("Evolução Física")
        } footer: {
            Text("Tira as fotos sempre nas mesmas condições — de manhã, mesma luz, mesma distância e roupa — para que a comparação seja justa. As fotos ficam só no telemóvel.")
        }
    }
}

/// The photos of one day, in pose order.
struct ProgressSession: Identifiable {
    let date: Date
    let photos: [ProgressPhoto]
    var id: Date { date }

    func photo(_ pose: ProgressPose) -> ProgressPhoto? {
        photos.first { $0.pose == pose }
    }

    /// Photos grouped per calendar day, most recent day first.
    static func group(_ photos: [ProgressPhoto]) -> [ProgressSession] {
        let calendar = Calendar.current
        return Dictionary(grouping: photos) { calendar.startOfDay(for: $0.date) }
            .map { day, photos in
                ProgressSession(date: day, photos: photos.sorted {
                    (ProgressPose.allCases.firstIndex(of: $0.pose) ?? 0) < (ProgressPose.allCases.firstIndex(of: $1.pose) ?? 0)
                })
            }
            .sorted { $0.date > $1.date }
    }
}

/// A row of thumbnails, one per pose of a session; tapping one opens it full screen.
struct ProgressSessionStrip: View {
    let session: ProgressSession
    var size: CGFloat = 72

    #if canImport(UIKit)
    @State private var fullScreen: ProgressPhoto?
    #endif

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ProgressPose.allCases) { pose in
                VStack(spacing: 4) {
                    if let photo = session.photo(pose) {
                        Button {
                            #if canImport(UIKit)
                            fullScreen = photo
                            #endif
                        } label: {
                            PhotoThumbnail(photoID: photo.photoID, size: size)
                        }
                        .buttonStyle(.plain)
                    } else {
                        PhotoThumbnail(photoID: nil, size: size, placeholder: pose.symbolName)
                            .opacity(0.5)
                    }
                    Text(pose.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        #if canImport(UIKit)
        .fullScreenCover(item: $fullScreen) { photo in
            if let image = PhotoStore.image(photo.photoID) {
                PhotoFullScreenView(image: image, caption: "\(photo.pose.displayName) · \(photo.date.formatted(date: .abbreviated, time: .omitted))")
            }
        }
        #endif
    }
}

// MARK: - Logging a session

/// One sheet per photo session: a date, one slot per pose (all optional) and a note.
struct LogProgressPhotosView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var photoIDs: [ProgressPose: UUID] = [:]
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Data", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                #if canImport(UIKit)
                ForEach(ProgressPose.allCases) { pose in
                    Section {
                        PhotoPickerField(photoID: Binding(
                            get: { photoIDs[pose] },
                            set: { photoIDs[pose] = $0 }
                        ))
                    } header: {
                        Label(pose.displayName, systemImage: pose.symbolName)
                    }
                }
                #endif
                Section("Notas (opcional)") {
                    TextField("Ex.: fim do bloco de base", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("Registar Fotos")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(photoIDs.isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let photos = ProgressPose.allCases.compactMap { pose in
            photoIDs[pose].map {
                ProgressPhoto(date: date, pose: pose, photoID: $0, notes: trimmed.isEmpty ? nil : trimmed)
            }
        }
        store.addProgressPhotos(photos)
        dismiss()
    }
}

// MARK: - History and comparison

/// Side-by-side comparison of two sessions for one pose (oldest vs newest by default), then
/// every session, most recent first.
struct ProgressPhotosView: View {
    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit

    @State private var pose: ProgressPose = .front
    @State private var beforeDate: Date?
    @State private var afterDate: Date?
    @State private var showingLog = false

    private var sessions: [ProgressSession] { ProgressSession.group(store.progressPhotos) }

    /// Sessions that have a photo for the chosen pose, oldest first.
    private var poseSessions: [ProgressSession] {
        sessions.filter { $0.photo(pose) != nil }.reversed()
    }

    var body: some View {
        List {
            Section {
                Picker("Pose", selection: $pose) {
                    ForEach(ProgressPose.allCases) { pose in
                        Text(pose.displayName).tag(pose)
                    }
                }
                .pickerStyle(.segmented)

                if poseSessions.count < 2 {
                    Text("Precisas de pelo menos duas sessões com foto de \(pose.displayName.lowercased()) para comparar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    let before = session(for: beforeDate) ?? poseSessions.first!
                    let after = session(for: afterDate) ?? poseSessions.last!
                    HStack(alignment: .top, spacing: 12) {
                        comparisonColumn(before, selection: $beforeDate)
                        comparisonColumn(after, selection: $afterDate)
                    }
                    .padding(.vertical, 4)
                    comparisonSummary(before: before, after: after)
                }
            } header: {
                Text("Comparar")
            }

            Section {
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(session.date.formatted(date: .complete, time: .omitted))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if let weight = healthKit.weightKG(on: session.date) {
                                Text(weight.formatted(.number.precision(.fractionLength(1))) + " kg")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ProgressSessionStrip(session: session)
                        if let notes = session.photos.compactMap(\.notes).first {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            session.photos.forEach(store.deleteProgressPhoto)
                        } label: {
                            Label("Eliminar Sessão", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Histórico")
            } footer: {
                Text("Desliza uma sessão para a eliminar.")
            }
        }
        .navigationTitle("Evolução Física")
        .trackScreen("Evolução Física")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLog = true
                } label: {
                    Image(systemName: "camera")
                }
                .accessibilityLabel("Registar Fotos")
            }
        }
        .sheet(isPresented: $showingLog) {
            LogProgressPhotosView()
        }
        .onChange(of: pose) {
            beforeDate = nil
            afterDate = nil
        }
    }

    private func session(for date: Date?) -> ProgressSession? {
        guard let date else { return nil }
        return poseSessions.first { $0.date == date }
    }

    /// The photo, with a menu on its date to pick another session.
    private func comparisonColumn(_ session: ProgressSession, selection: Binding<Date?>) -> some View {
        VStack(spacing: 6) {
            #if canImport(UIKit)
            if let photo = session.photo(pose), let image = PhotoStore.image(photo.photoID) {
                // A fixed-size frame with the photo as an overlay: `scaledToFill` on its own would
                // size the column to the photo and push the other one off screen.
                Color.clear
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            #endif
            Menu {
                ForEach(poseSessions) { option in
                    Button(option.date.formatted(date: .abbreviated, time: .omitted)) {
                        selection.wrappedValue = option.date
                    }
                }
            } label: {
                Label(session.date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "47 dias · −2,3 kg" between the two compared sessions.
    private func comparisonSummary(before: ProgressSession, after: ProgressSession) -> some View {
        let days = Calendar.current.dateComponents([.day], from: before.date, to: after.date).day ?? 0
        var parts = ["\(abs(days)) \(abs(days) == 1 ? "dia" : "dias")"]
        if let w1 = healthKit.weightKG(on: before.date), let w2 = healthKit.weightKG(on: after.date) {
            parts.append((w2 - w1).formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false))) + " kg")
        }
        return Text(parts.joined(separator: " · "))
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
    }
}

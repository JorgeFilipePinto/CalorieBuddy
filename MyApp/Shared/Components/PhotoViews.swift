import SwiftUI
#if canImport(UIKit)
import PhotosUI
import UIKit
#endif

/// A square, rounded thumbnail of a stored photo — or `placeholder` (an SF Symbol) when there's
/// none, so list rows keep the same alignment with or without a photo.
struct PhotoThumbnail: View {
    let photoID: UUID?
    var size: CGFloat = 44
    var placeholder: String?

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let photoID, let image = PhotoStore.thumbnail(photoID) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderView
            }
            #else
            placeholderView
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    @ViewBuilder
    private var placeholderView: some View {
        if let placeholder {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(.quaternary)
                .overlay(
                    Image(systemName: placeholder)
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.secondary)
                )
        } else {
            Color.clear
        }
    }
}

#if canImport(UIKit)
/// Lets a photo be taken or picked for something, then shows it with "Trocar" / "Remover". New
/// photos are saved to `PhotoStore` straight away; the caller just keeps the id (an editor that's
/// cancelled leaves an unused file behind, which `DataStore` clears at the next launch).
struct PhotoPickerField: View {
    @Binding var photoID: UUID?

    @State private var item: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingFullScreen = false

    var body: some View {
        if let photoID, let image = PhotoStore.image(photoID) {
            Button {
                showingFullScreen = true
            } label: {
                Color.clear
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .fullScreenCover(isPresented: $showingFullScreen) {
                PhotoFullScreenView(image: image)
            }
        }

        HStack(spacing: 12) {
            if CameraPicker.isAvailable {
                Button {
                    showingCamera = true
                } label: {
                    Label(photoID == nil ? "Tirar Foto" : "Câmara", systemImage: "camera")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            PhotosPicker(selection: $item, matching: .images) {
                Label("Galeria", systemImage: "photo")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if photoID != nil {
                Button(role: .destructive) {
                    photoID = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Remover foto")
            }
        }
        .onChange(of: item) {
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photoID = PhotoStore.save(image)
                }
                self.item = nil
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in photoID = PhotoStore.save(image) }
                .ignoresSafeArea()
        }
    }
}

/// The photos of a nutrition label (front, back…): a row of thumbnails — tap one to see it full
/// screen, long-press to remove it — plus camera / gallery buttons to add more (several at once
/// from the gallery). Like `PhotoPickerField`, new photos are saved to `PhotoStore` straight away.
struct NutritionLabelPhotosSection: View {
    @Binding var photoIDs: [UUID]

    @State private var items: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var shownPhoto: ShownPhoto?

    private struct ShownPhoto: Identifiable {
        let id: UUID
        let image: UIImage
    }

    var body: some View {
        Section {
            if !photoIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photoIDs, id: \.self) { id in
                            Button {
                                if let image = PhotoStore.image(id) { shownPhoto = ShownPhoto(id: id, image: image) }
                            } label: {
                                PhotoThumbnail(photoID: id, size: 88, placeholder: "doc.text.image")
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Remover Foto", systemImage: "trash", role: .destructive) {
                                    photoIDs.removeAll { $0 == id }
                                }
                            }
                            .accessibilityLabel("Foto da tabela nutricional")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack(spacing: 12) {
                if CameraPicker.isAvailable {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Fotografar", systemImage: "camera")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                PhotosPicker(selection: $items, maxSelectionCount: 6, matching: .images) {
                    Label("Galeria", systemImage: "photo.on.rectangle")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            // On this one row (always there), not on the Section: a Section hands its modifiers
            // to every row, which would present twice and add the picked photos twice.
            .onChange(of: items) {
                guard !items.isEmpty else { return }
                let picked = items
                Task {
                    for item in picked {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data),
                           let id = PhotoStore.save(image) {
                            photoIDs.append(id)
                        }
                    }
                    items = []
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    if let id = PhotoStore.save(image) { photoIDs.append(id) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $shownPhoto) { photo in
                PhotoFullScreenView(image: photo.image, caption: "Tabela Nutricional")
            }
        } header: {
            Text("Tabela Nutricional")
        } footer: {
            Text(photoIDs.isEmpty
                 ? "Fotografa o rótulo para teres sempre os valores à mão."
                 : "Toca numa foto para a ver em grande; mantém o dedo para a remover.")
        }
    }
}

/// A photo on black, pinch-to-zoom, tap "OK" to close.
struct PhotoFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    var caption: String?

    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { scale = max(1, $0.magnification) }
                            .onEnded { _ in withAnimation { scale = 1 } }
                    )
            }
            .navigationTitle(caption ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}
#endif

//
//  ContentView.swift
//  iOSApp5
//
//  Media Moments
//  A SwiftUI application that allows users to select,
//  display, and manage photos and videos.
//

import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

struct ContentView: View {
    
    var body: some View {
        TabView {
            MediaGalleryView()
                .tabItem {
                    Label("Gallery", systemImage: "photo.on.rectangle")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
    }
}

// MARK: - Media Model

/// Represents one photo or video selected by the user.
struct MediaMoment: Identifiable {
    let id = UUID()
    let title: String
    let caption: String
    let dateCreated: Date
    let mediaType: MediaType
    let imageData: Data?
    let videoURL: URL?
}

/// Identifies whether a saved media item is a photo or video.
enum MediaType {
    case photo
    case video
}

// MARK: - Gallery Screen

struct MediaGalleryView: View {
    
    /// Stores all media moments added during the current app session.
    @State private var moments: [MediaMoment] = []
    
    /// Controls whether the add-media sheet is displayed.
    @State private var showingAddMedia = false
    
    /// Controls the delete confirmation alert.
    @State private var showingDeleteAlert = false
    
    /// Stores the media item waiting to be deleted.
    @State private var momentToDelete: MediaMoment?
    
    var body: some View {
        NavigationStack {
            Group {
                if moments.isEmpty {
                    EmptyGalleryView()
                } else {
                    List {
                        ForEach(moments) { moment in
                            NavigationLink {
                                MediaDetailView(moment: moment)
                            } label: {
                                MediaRowView(moment: moment)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    momentToDelete = moment
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Media Moments")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddMedia = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Media")
                }
            }
            .sheet(isPresented: $showingAddMedia) {
                AddMediaView { newMoment in
                    moments.append(newMoment)
                }
            }
            .alert("Delete Media?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    momentToDelete = nil
                }
                
                Button("Delete", role: .destructive) {
                    deleteSelectedMoment()
                }
            } message: {
                Text("This media moment will be removed from the gallery.")
            }
        }
    }
    
    /// Deletes the selected media item from the array.
    private func deleteSelectedMoment() {
        guard let momentToDelete else {
            return
        }
        
        moments.removeAll { moment in
            moment.id == momentToDelete.id
        }
        
        self.momentToDelete = nil
    }
}

// MARK: - Empty Gallery Screen

struct EmptyGalleryView: View {
    
    var body: some View {
        ContentUnavailableView {
            Label("No Media Yet", systemImage: "photo.badge.plus")
        } description: {
            Text("Tap the plus button to add a photo or video.")
        }
    }
}

// MARK: - Gallery Row

struct MediaRowView: View {
    
    let moment: MediaMoment
    
    var body: some View {
        HStack(spacing: 14) {
            mediaThumbnail
            
            VStack(alignment: .leading, spacing: 5) {
                Text(moment.title)
                    .font(.headline)
                
                Text(moment.caption.isEmpty ? "No caption" : moment.caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                Text(moment.dateCreated, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
    
    @ViewBuilder
    private var mediaThumbnail: some View {
        if moment.mediaType == .photo,
           let imageData = moment.imageData,
           let uiImage = UIImage(data: imageData) {
            
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 75, height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.secondary.opacity(0.2))
                
                Image(systemName: "play.rectangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
            }
            .frame(width: 75, height: 75)
        }
    }
}

// MARK: - Add Media Screen

struct AddMediaView: View {
    
    /// Allows the sheet to close after saving.
    @Environment(\.dismiss) private var dismiss
    
    /// Sends the completed media moment back to the gallery.
    let onSave: (MediaMoment) -> Void
    
    @State private var title = ""
    @State private var caption = ""
    
    /// Stores the selection returned by PhotosPicker.
    @State private var selectedItem: PhotosPickerItem?
    
    @State private var selectedImageData: Data?
    @State private var selectedVideoURL: URL?
    @State private var selectedMediaType: MediaType?
    
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingError = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Media") {
                    mediaPreview
                    
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("Choose Photo or Video",
                              systemImage: "photo.on.rectangle.angled")
                    }
                    
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading media...")
                        }
                    }
                }
                
                Section("Information") {
                    TextField("Title", text: $title)
                    
                    TextField(
                        "Write a caption",
                        text: $caption,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMoment()
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: selectedItem) {
                loadSelectedMedia()
            }
            .alert("Unable to Load Media", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    /// Determines whether the Save button should be enabled.
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedMediaType != nil &&
        !isLoading
    }
    
    @ViewBuilder
    private var mediaPreview: some View {
        if let selectedImageData,
           let uiImage = UIImage(data: selectedImageData) {
            
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 15))
            
        } else if let selectedVideoURL {
            VideoPlayer(player: AVPlayer(url: selectedVideoURL))
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 15))
            
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(.secondary.opacity(0.12))
                
                VStack(spacing: 12) {
                    Image(systemName: "photo.and.video")
                        .font(.system(size: 48))
                    
                    Text("No media selected")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 220)
        }
    }
    
    /// Loads either image or video data from PhotosPicker.
    private func loadSelectedMedia() {
        guard let selectedItem else {
            return
        }
        
        isLoading = true
        selectedImageData = nil
        selectedVideoURL = nil
        selectedMediaType = nil
        
        Task {
            do {
                if selectedItem.supportedContentTypes.contains(
                    where: { $0.conforms(to: .image) }
                ) {
                    try await loadImage(from: selectedItem)
                } else if selectedItem.supportedContentTypes.contains(
                    where: { $0.conforms(to: .movie) }
                ) {
                    try await loadVideo(from: selectedItem)
                } else {
                    throw MediaLoadingError.unsupportedMedia
                }
                
                await MainActor.run {
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    /// Loads a selected image as Data.
    private func loadImage(from item: PhotosPickerItem) async throws {
        guard let imageData = try await item.loadTransferable(type: Data.self) else {
            throw MediaLoadingError.imageCouldNotLoad
        }
        
        await MainActor.run {
            selectedImageData = imageData
            selectedMediaType = .photo
        }
    }
    
    /// Loads selected video data and saves it temporarily on the device.
    private func loadVideo(from item: PhotosPickerItem) async throws {
        guard let videoData = try await item.loadTransferable(type: Data.self) else {
            throw MediaLoadingError.videoCouldNotLoad
        }
        
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        
        try videoData.write(to: temporaryURL)
        
        await MainActor.run {
            selectedVideoURL = temporaryURL
            selectedMediaType = .video
        }
    }
    
    /// Creates a new MediaMoment and returns it to the gallery.
    private func saveMoment() {
        guard let selectedMediaType else {
            return
        }
        
        let newMoment = MediaMoment(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
            dateCreated: Date(),
            mediaType: selectedMediaType,
            imageData: selectedImageData,
            videoURL: selectedVideoURL
        )
        
        onSave(newMoment)
        dismiss()
    }
}

// MARK: - Media Loading Errors

enum MediaLoadingError: LocalizedError {
    case imageCouldNotLoad
    case videoCouldNotLoad
    case unsupportedMedia
    
    var errorDescription: String? {
        switch self {
        case .imageCouldNotLoad:
            return "The selected image could not be loaded."
        case .videoCouldNotLoad:
            return "The selected video could not be loaded."
        case .unsupportedMedia:
            return "This type of media is not supported."
        }
    }
}

// MARK: - Detail Screen

struct MediaDetailView: View {
    
    let moment: MediaMoment
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                mediaDisplay
                
                VStack(alignment: .leading, spacing: 10) {
                    Text(moment.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Label(
                        moment.dateCreated.formatted(
                            date: .long,
                            time: .shortened
                        ),
                        systemImage: "calendar"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    
                    Divider()
                    
                    Text("Caption")
                        .font(.headline)
                    
                    Text(
                        moment.caption.isEmpty
                        ? "No caption was added."
                        : moment.caption
                    )
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle("Media Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private var mediaDisplay: some View {
        if moment.mediaType == .photo,
           let imageData = moment.imageData,
           let uiImage = UIImage(data: imageData) {
            
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
            
        } else if let videoURL = moment.videoURL {
            VideoPlayer(player: AVPlayer(url: videoURL))
                .frame(height: 300)
        }
    }
}

// MARK: - About Screen

struct AboutView: View {
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 70))
                            .foregroundStyle(.blue)
                        
                        Text("Media Moments")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Save and enjoy your favourite photos and videos.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                
                Section("App Features") {
                    Label("Photo selection", systemImage: "photo")
                    Label("Video selection and playback", systemImage: "video")
                    Label("Media gallery", systemImage: "square.grid.2x2")
                    Label("Swipe to delete", systemImage: "trash")
                    Label("Navigation and tabs", systemImage: "rectangle.split.2x1")
                }
                
                Section("Student Project") {
                    LabeledContent("Project", value: "iOSApp5")
                    LabeledContent("Framework", value: "SwiftUI")
                    LabeledContent("Platform", value: "iOS")
                }
            }
            .navigationTitle("About")
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}

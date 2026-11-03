import PhotosUI
import QuickLook
import SwiftUI

/// The attachments section of the task detail screen.
struct AttachmentsSection: View {
    @Bindable var model: AttachmentsViewModel
    let attachments: [TaskAttachment]
    let canEdit: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var isImportingFile = false

    var body: some View {
        Section("Attachments") {
            ForEach(attachments) { attachment in
                Button {
                    Task { await model.preview(attachment) }
                } label: {
                    AttachmentRow(name: attachment.name, size: attachment.size, isImage: attachment.isImage)
                }
                .swipeActions {
                    if canEdit {
                        Button("Delete", role: .destructive) { Task { await model.delete(attachment) } }
                    }
                }
                .accessibilityHint(Text("Opens a preview"))
            }
            ForEach(model.uploads) { upload in
                UploadStatusRow(
                    name: upload.name, size: upload.size, isImage: upload.isImage,
                    progress: { if case .uploading(let value) = upload.state { value } else { nil } }(),
                    failure: { if case .failed(let message) = upload.state { message } else { nil } }(),
                    onRetry: { Task { await model.retry(upload) } },
                    onRemove: { model.discard(upload) }
                )
            }
            ForEach(model.backgroundUploads) { upload in
                UploadStatusRow(
                    name: upload.fileName, size: upload.size, isImage: upload.contentType.hasPrefix("image/"),
                    progress: nil,
                    failure: upload.state == .failed ? (upload.lastError ?? String(localized: "Upload failed")) : nil,
                    onRetry: { Task { await model.retryBackground(upload) } },
                    onRemove: { Task { await model.discardBackground(upload) } }
                )
            }
            if attachments.isEmpty && model.uploads.isEmpty && model.backgroundUploads.isEmpty {
                Text("No attachments").foregroundStyle(Palette.secondaryText)
            }
            if canEdit {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Add Photo", systemImage: "photo.badge.plus")
                }
                Button("Add File", systemImage: "doc.badge.plus") { isImportingFile = true }
            }
        }
        .quickLookPreview($model.previewURL)
        .task { await model.observeBackgroundUploads() }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url): Task { await model.addFile(at: url) }
            case .failure: model.reportImportFailure()
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.addImage(data)
                }
            }
        }
        .alert("Attachment Problem", isPresented: isShowingError) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.dismissError() } })
    }
}

/// Icon, name and size of one attachment.
struct AttachmentRow: View {
    let name: String
    let size: Int64
    let isImage: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(name).lineLimit(2)
                Text(size, format: .byteCount(style: .file))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
            }
        } icon: {
            Image(systemName: isImage ? "photo" : "doc")
                .foregroundStyle(Palette.accent)
        }
        .accessibilityElement(children: .combine)
    }
}

/// An attachment that is still uploading (with progress if known) or failed (with Retry/Remove).
struct UploadStatusRow: View {
    let name: String
    let size: Int64
    let isImage: Bool
    /// `nil` while waiting with no measurable progress (background uploads).
    let progress: Double?
    /// Set when the upload failed; shown next to Retry and Remove.
    let failure: String?
    let onRetry: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            AttachmentRow(name: name, size: size, isImage: isImage)
            if let failure {
                HStack {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.danger)
                        .font(.footnote)
                    Spacer()
                    Button("Retry", action: onRetry)
                    Button("Remove", role: .destructive, action: onRemove)
                }
                .buttonStyle(.borderless)
            } else if let progress {
                ProgressView(value: progress).accessibilityLabel(Text("Uploading"))
            } else {
                ProgressView().accessibilityLabel(Text("Uploading in the background"))
            }
        }
    }
}

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
                uploadRow(upload)
            }
            if attachments.isEmpty && model.uploads.isEmpty {
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

    @ViewBuilder
    private func uploadRow(_ upload: AttachmentsViewModel.Upload) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            AttachmentRow(name: upload.name, size: upload.size, isImage: upload.isImage)
            switch upload.state {
            case .uploading(let fraction):
                ProgressView(value: fraction)
                    .accessibilityLabel(Text("Uploading"))
            case .failed(let message):
                HStack {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.danger)
                        .font(.footnote)
                    Spacer()
                    Button("Retry") { Task { await model.retry(upload) } }
                    Button("Remove", role: .destructive) { model.discard(upload) }
                }
                .buttonStyle(.borderless)
            }
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

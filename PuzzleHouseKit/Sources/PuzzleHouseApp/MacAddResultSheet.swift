#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PuzzleCore
import PuzzleParsers
import PuzzleVision

/// Mac-tailored "Add a result" sheet: paste text, drag/drop or choose a
/// screenshot (OCR), paste an image, or log an Emoji Game — in a roomy, native
/// layout instead of the iOS `Form`. Reuses the exact same parsing (`ParserRegistry`)
/// and OCR (`OCRPipeline`) as iOS so behavior stays in sync.
struct MacAddResultSheet: View {
    let onSubmit: @MainActor (ParsedResult, String) async throws -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var parsed: ParsedResult?
    @State private var error: String?
    @State private var isSubmitting = false
    @State private var isScanning = false
    @State private var showingEmojiEntry = false
    @State private var isDropTargeted = false

    init(onSubmit: @escaping @MainActor (ParsedResult, String) async throws -> Void) {
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pasteSection
                    if let parsed { detected(parsed) }
                    screenshotSection
                    emojiGameSection
                    if let error { errorBanner(error) }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 540, height: 680)
        .background(.windowBackground)
        .onChange(of: text) { _, new in reparse(new) }
        .sheet(isPresented: $showingEmojiEntry) {
            EmojiGameEntryView { parsed, raw in
                try await onSubmit(parsed, raw)
                dismiss()
            }
        }
    }

    // MARK: Sections

    private var titleBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add a result").font(.title3.bold())
                Text("Paste, drop a screenshot, or log an Emoji Game")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Paste a puzzle result", systemImage: "doc.on.clipboard")
                .font(.headline)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150)
                .padding(8)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                .disabled(isSubmitting)
            Text("Copy the share text from Wordle, Connections, or Strands and paste it here.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Or use a screenshot", systemImage: "photo.on.rectangle.angled")
                .font(.headline)
            dropWell
            HStack(spacing: 10) {
                Button { chooseImage() } label: { Label("Choose Image\u{2026}", systemImage: "folder") }
                Button { pasteImage() } label: { Label("Paste Image", systemImage: "doc.on.clipboard.fill") }
                if isScanning {
                    ProgressView().controlSize(.small)
                    Text("Reading\u{2026}").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .disabled(isSubmitting || isScanning)
        }
    }

    private var dropWell: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isDropTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.quinary))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            )
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc").font(.title2).foregroundStyle(.secondary)
                    Text("Drag a screenshot here").font(.callout).foregroundStyle(.secondary)
                }
            )
            .frame(height: 90)
            .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
    }

    private var emojiGameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Emoji Game", systemImage: "face.smiling").font(.headline)
            Button { showingEmojiEntry = true } label: {
                Label("Log Emoji Game\u{2026}", systemImage: "slider.horizontal.3")
            }
            .disabled(isSubmitting || isScanning)
            Text("Apple News only shares a link, so enter how many moves you took. 6 = Perfect.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func detected(_ p: ParsedResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(ParserRegistry.displayName(for: p.gameID) ?? p.gameID).font(.headline)
                Text("Puzzle #\(p.puzzleNumber) \u{00B7} \(p.rawScore.solved ? "Solved" : "Did not solve")")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(.callout).foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if isSubmitting { ProgressView().controlSize(.small) }
            Button("Save Result") { Task { await submit() } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(parsed == nil || isSubmitting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Logic

    private func reparse(_ new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { parsed = nil; error = nil; return }
        parsed = ParserRegistry.parse(trimmed)
        error = parsed == nil ? "We don't recognize this puzzle yet." : nil
    }

    private func submit() async {
        guard let parsed else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await onSubmit(parsed, text)
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func scan(data: Data) async {
        isScanning = true
        defer { isScanning = false }
        guard let cg = ImageDownsampler.cgImage(from: data)
            ?? ImageDownsampler.downsample(data: data, maxPixelDimension: 2200) else {
            error = "Couldn't decode that image."
            return
        }
        do {
            let recognized = try await OCRPipeline.recognizeText(in: cg)
            if ParserRegistry.parse(recognized) != nil {
                text = recognized
            } else if let synth = OCRPipeline.synthesizeEmojiGame(from: recognized) {
                text = synth
            } else {
                text = recognized
                error = "Couldn't find a puzzle there — try cropping closer to the score."
            }
        } catch {
            self.error = "OCR failed: \(error.localizedDescription)"
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a puzzle screenshot"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        Task { await scan(data: data) }
    }

    private func pasteImage() {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            Task { await scan(data: data) }
        } else if let string = pasteboard.string(forType: .string), !string.isEmpty {
            text = string
        } else {
            error = "No image or text found on the clipboard."
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let imageType = UTType.image.identifier
        guard provider.hasItemConformingToTypeIdentifier(imageType) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: imageType) { data, _ in
            guard let data else { return }
            Task { @MainActor in await scan(data: data) }
        }
        return true
    }
}
#endif

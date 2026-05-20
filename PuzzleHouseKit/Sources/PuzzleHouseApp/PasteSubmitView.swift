import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif
import PuzzleCore
import PuzzleParsers
import PuzzleVision

public struct PasteSubmitView: View {
    @State private var text: String = ""
    @State private var parsed: ParsedResult?
    @State private var error: String?
    @State private var isSubmitting = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var isScanning = false

    let onSubmit: @MainActor (ParsedResult, String) async throws -> Void
    @Environment(\.dismiss) private var dismiss

    public init(onSubmit: @escaping @MainActor (ParsedResult, String) async throws -> Void) {
        self.onSubmit = onSubmit
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Paste a puzzle result") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: text) { _, new in reparse(new) }
                        .disabled(isSubmitting || isScanning)
                }
                Section("Or scan a screenshot") {
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(isScanning ? "Reading screenshot…" : "Pick from Photos",
                              systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(isSubmitting || isScanning)
                    .onChange(of: pickerItem) { _, new in
                        guard let new else { return }
                        Task { await scan(item: new) }
                    }
                    Text("Best for Apple News' Emoji Game — it has no Share Sheet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let parsed {
                    Section("Detected") {
                        LabeledContent("Game", value: ParserRegistry.displayName(for: parsed.gameID) ?? parsed.gameID)
                        LabeledContent("Puzzle", value: "#\(parsed.puzzleNumber)")
                        LabeledContent("Solved", value: parsed.rawScore.solved ? "Yes" : "No")
                    }
                }
                if isSubmitting {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Saving to iCloud\u{2026}").foregroundStyle(.secondary)
                        }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .interactiveDismissDisabled(isSubmitting || isScanning)
            .navigationTitle("Add Result")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting || isScanning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await submit() } }
                        .disabled(parsed == nil || isSubmitting)
                }
            }
        }
    }

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

    private func scan(item: PhotosPickerItem) async {
        isScanning = true
        defer { isScanning = false; pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                error = "Couldn't load the image."
                return
            }
            #if canImport(UIKit)
            guard let cgImage = UIImage(data: data)?.cgImage else {
                error = "Couldn't decode the image."
                return
            }
            let recognized = try await OCRPipeline.recognizeText(in: cgImage)
            // Prefer a directly-parseable payload; otherwise try Emoji Game synth.
            if ParserRegistry.parse(recognized) != nil {
                text = recognized
            } else if let synth = OCRPipeline.synthesizeEmojiGame(from: recognized) {
                text = synth
            } else {
                text = recognized
                error = "We couldn't find a puzzle in that screenshot. Try cropping closer to the score."
            }
            #else
            error = "Screenshot scanning isn't available on this platform yet."
            #endif
        } catch {
            self.error = "OCR failed: \(error.localizedDescription)"
        }
    }
}

import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
#endif
import PuzzleCore
import PuzzleParsers
import PuzzleVision

/// Pulls the user's most recent screenshots from the Photos library, runs OCR
/// + parser on each, and shows the ones that look like puzzle results so the
/// user can confirm-and-import in one tap.
public struct ScanRecentScreenshotsSheet: View {
    let onSelect: @MainActor (ParsedResult, String) async throws -> Void
    @State private var authStatus: PHAuthorizationStatus = .notDetermined
    @State private var scanning = true
    @State private var candidates: [Candidate] = []
    @State private var error: String?
    @State private var submittingID: String?
    @Environment(\.dismiss) private var dismiss

    public init(onSelect: @escaping @MainActor (ParsedResult, String) async throws -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Recent screenshots")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task { await prepare() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch authStatus {
        case .notDetermined:
            ProgressView("Asking permission\u{2026}")
        case .denied, .restricted:
            ContentUnavailableView(
                "Photos access denied",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Enable in Settings → Privacy → Photos → Puzzle House (Limited or Full).")
            )
        case .authorized, .limited:
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if scanning {
                        HStack { ProgressView(); Text("Scanning your recent screenshots\u{2026}") }
                            .padding()
                    } else if candidates.isEmpty {
                        ContentUnavailableView(
                            "No puzzle screenshots found",
                            systemImage: "puzzlepiece",
                            description: Text("We looked at your last 20 screenshots and couldn't parse any. Try taking a fresh one.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(candidates) { c in candidateCard(c) }
                    }
                    if let error {
                        Text(error).foregroundStyle(.red).font(.caption).padding(.horizontal)
                    }
                }
                .padding()
            }
        @unknown default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func candidateCard(_ c: Candidate) -> some View {
        let game = Game.known(by: c.parsed.gameID)
        HStack(alignment: .top, spacing: 12) {
            #if canImport(UIKit)
            if let thumb = c.thumbnail {
                Image(uiImage: thumb)
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            #endif
            VStack(alignment: .leading, spacing: 6) {
                Text("\(game?.emoji ?? "🧩") \(game?.displayName ?? c.parsed.gameID) #\(c.parsed.puzzleNumber)")
                    .font(.headline)
                Text(c.parsed.rawScore.solved ? "Solved" : "Not solved")
                    .font(.caption).foregroundStyle(.secondary)
                Text(c.dateText)
                    .font(.caption2).foregroundStyle(.tertiary)
                Button {
                    Task { await submit(c) }
                } label: {
                    if submittingID == c.id {
                        HStack { ProgressView().controlSize(.small); Text("Importing\u{2026}") }
                    } else {
                        Label("Import", systemImage: "tray.and.arrow.down")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(submittingID != nil)
                .padding(.top, 2)
            }
            Spacer()
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func submit(_ c: Candidate) async {
        submittingID = c.id
        defer { submittingID = nil }
        do {
            try await onSelect(c.parsed, c.rawText)
            candidates.removeAll { $0.id == c.id }
            if candidates.isEmpty { dismiss() }
        } catch {
            self.error = String(describing: error)
        }
    }

    // MARK: - Photos pipeline

    private func prepare() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            authStatus = await withCheckedContinuation { cont in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    cont.resume(returning: newStatus)
                }
            }
        } else {
            authStatus = status
        }
        guard authStatus == .authorized || authStatus == .limited else {
            scanning = false
            return
        }
        await scan()
    }

    private func scan() async {
        scanning = true
        defer { scanning = false }
        #if canImport(UIKit)
        let assets = ScanRecentScreenshotsSheet.recentScreenshots(limit: 20)
        var found: [Candidate] = []
        for asset in assets {
            guard let image = await loadImage(asset, targetSize: CGSize(width: 1200, height: 1600)),
                  let cg = image.cgImage else { continue }
            do {
                let parsed = try await OCRPipeline.parseResult(from: cg)
                let thumb = await loadImage(asset, targetSize: CGSize(width: 240, height: 320))
                let rawText = (try? await OCRPipeline.recognizeText(in: cg)) ?? ""
                let dateText = ScanRecentScreenshotsSheet.formatter.string(from: asset.creationDate ?? Date())
                found.append(Candidate(
                    id: asset.localIdentifier,
                    parsed: parsed,
                    rawText: rawText,
                    thumbnail: thumb,
                    dateText: dateText
                ))
            } catch {
                continue
            }
        }
        candidates = found
        #else
        candidates = []
        #endif
    }

    static func recentScreenshots(limit: Int) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    #if canImport(UIKit)
    private func loadImage(_ asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                cont.resume(returning: image)
            }
        }
    }
    #endif

    struct Candidate: Identifiable {
        let id: String
        let parsed: ParsedResult
        let rawText: String
        #if canImport(UIKit)
        let thumbnail: UIImage?
        #endif
        let dateText: String
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

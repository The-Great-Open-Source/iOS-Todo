import Foundation
import ImageIO

/// Photos attached to tasks, stored as small JPEG files next to the task data.
/// Photos are downscaled when saved so a few of them never weigh down the app or its backups.
nonisolated struct TaskImageStorage {
    let directory: URL

    static var local: Self {
        Self(directory: URL.applicationSupportDirectory.appendingPathComponent("Todos", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true))
    }

    /// The longest side of a stored photo, in pixels.
    static let maxStoredPixels = 1600

    /// Downscales, re-encodes as JPEG, and saves the photo. Returns the file name to keep on the task.
    func save(_ data: Data) throws -> String {
        guard let image = Self.cgImage(from: data, maxPixels: Self.maxStoredPixels) else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).jpg"
        guard let destination = CGImageDestinationCreateWithURL(url(for: name) as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return name
    }

    func url(for name: String) -> URL { directory.appendingPathComponent(name) }

    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: url(for: name).path) }

    func delete(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: url(for: name))
    }

    /// Removes any file that no task refers to, such as a photo whose undo window passed while the app was closed.
    func removeUnreferenced(keeping names: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where !names.contains(file) { delete(file) }
    }

    /// A stored photo, no larger than `maxPixels` on its longest side, with its orientation applied.
    func image(_ name: String, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url(for: name) as CFURL, nil) else { return nil }
        return Self.thumbnail(from: source, maxPixels: maxPixels)
    }

    static func cgImage(from data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(from: source, maxPixels: maxPixels)
    }

    private static func thumbnail(from source: CGImageSource, maxPixels: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary)
    }
}

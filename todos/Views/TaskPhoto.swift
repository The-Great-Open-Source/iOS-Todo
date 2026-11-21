import SwiftUI

private enum PhotoCache {
    static let images = NSCache<NSString, CGImage>()
}

/// A task's photo, loaded off the main thread and cached. Missing files (for example after a
/// reinstall, which keeps tasks but not photos) simply show a quiet placeholder.
struct TaskPhotoView: View {
    let filename: String
    var maxPixels = 900
    var fill = true
    @Environment(TaskStore.self) private var store
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                let picture = Image(decorative: image, scale: 1).resizable()
                if fill { picture.scaledToFill() } else { picture.scaledToFit() }
            } else {
                Rectangle().fill(.primary.opacity(0.06))
                    .overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
            }
        }
        .task(id: filename) {
            let key = "\(filename)-\(maxPixels)" as NSString
            if let cached = PhotoCache.images.object(forKey: key) { image = cached; return }
            let storage = store.images, name = filename, pixels = maxPixels
            let loaded = await Task.detached { storage.image(name, maxPixels: pixels) }.value
            if let loaded { PhotoCache.images.setObject(loaded, forKey: key) }
            image = loaded
        }
    }
}

/// The photo at full size, over black. Tap anywhere or use the close button to leave.
struct PhotoViewer: View {
    let task: TaskItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let filename = task.imageFilename {
                TaskPhotoView(filename: filename, maxPixels: 2000, fill: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Photo for \(task.title)")
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .padding(16).accessibilityLabel("Close photo")
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .preferredColorScheme(.dark)
    }
}

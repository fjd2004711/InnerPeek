import AppKit

// Renders the real Quick Look preview view controller offscreen and writes a PNG.
// Used by scripts/render-screenshots.sh to produce README images from fictional demo data.
// Usage: RenderPreview <file-or-folder> <output.png> [width height] [light|dark]

final class RenderApp: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        guard args.count >= 3 else { FileHandle.standardError.write(Data("usage: RenderPreview <path> <out.png> [w h] [light|dark]\n".utf8)); exit(2) }
        let source = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
        let width = args.count > 4 ? Double(args[3]) ?? 880 : 880
        let height = args.count > 4 ? Double(args[4]) ?? 640 : 640
        let dark = args.last == "dark"

        let controller = PreviewViewController()
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentViewController = controller
        // The Quick Look host paints the panel background; reproduce it so the PNG is opaque
        // and readable on both light and dark README themes.
        window.appearance?.performAsCurrentDrawingAppearance {
            controller.view.wantsLayer = true
            controller.view.layer?.backgroundColor = (dark ? NSColor.windowBackgroundColor : NSColor.white).cgColor
        }
        window.setContentSize(NSSize(width: width, height: height))
        window.orderBack(nil)

        _ = Task { @MainActor in
            do { try await controller.preparePreviewOfFile(at: source) } catch { print("prepare failed: \(error)"); exit(1) }
            // Analysis, metadata and icons arrive asynchronously; give them time to settle.
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            let view = window.contentView!
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
            do { try png.write(to: output) } catch { print("write failed: \(error)"); exit(1) }
            exit(0)
        }
    }
}

@main
enum RenderMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = RenderApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

import AppKit
import ImageIO
import QuartzCore
import SwiftUI
import WebKit

/// Displays remote GIF/APNG assets without flattening them to their first frame.
struct AnimatedRemoteImage: View {
    let url: URL
    var isLooping = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var imageData: Data?

    var body: some View {
        Group {
            if let imageData {
                AnimatedImageRepresentable(
                    imageData: imageData,
                    animates: !reduceMotion,
                    isLooping: isLooping
                )
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            imageData = nil
            for attempt in 0..<3 {
                do {
                    let data: Data
                    if url.isFileURL {
                        data = try Data(contentsOf: url)
                    } else {
                        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
                        let result = try await URLSession.shared.data(for: request)
                        if let response = result.1 as? HTTPURLResponse {
                            guard 200..<300 ~= response.statusCode else {
                                throw URLError(.badServerResponse)
                            }
                        }
                        data = result.0
                    }
                    guard !Task.isCancelled else { return }
                    imageData = data
                    return
                } catch is CancellationError {
                    return
                } catch {
                    guard attempt < 2 else {
                        imageData = nil
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200 * (attempt + 1)))
                }
            }
        }
    }
}

private struct AnimatedImageRepresentable: NSViewRepresentable {
    let imageData: Data
    let animates: Bool
    let isLooping: Bool

    func makeNSView(context: Context) -> AnimatedImageCanvas {
        AnimatedImageCanvas()
    }

    func updateNSView(_ view: AnimatedImageCanvas, context: Context) {
        view.display(imageData, animates: animates, isLooping: isLooping)
    }
}

private final class AnimatedImageCanvas: NSView {
    private var displayedData: Data?
    private var displayedAnimationPreference: (animates: Bool, isLooping: Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func display(_ data: Data, animates: Bool, isLooping: Bool) {
        let preference = (animates: animates, isLooping: isLooping)
        guard displayedData != data
            || displayedAnimationPreference?.animates != preference.animates
            || displayedAnimationPreference?.isLooping != preference.isLooping else { return }
        displayedData = data
        displayedAnimationPreference = preference
        layer?.removeAnimation(forKey: "remoteAnimatedImage")

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            layer?.contents = nil
            return
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            layer?.contents = nil
            return
        }

        var frames: [CGImage] = []
        var frameDurations: [TimeInterval] = []
        for index in 0..<frameCount {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(image)
            frameDurations.append(Self.frameDuration(source: source, index: index))
        }
        guard let firstFrame = frames.first else { return }
        layer?.contents = firstFrame

        guard animates, frames.count > 1 else { return }
        let totalDuration = max(frameDurations.reduce(0, +), 0.05)
        var elapsed: TimeInterval = 0
        let keyTimes = frameDurations.map { duration -> NSNumber in
            defer { elapsed += duration }
            return NSNumber(value: elapsed / totalDuration)
        }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.keyTimes = keyTimes
        animation.duration = totalDuration
        animation.calculationMode = .discrete
        animation.repeatCount = isLooping ? .infinity : 1
        animation.isRemovedOnCompletion = !isLooping
        animation.fillMode = .forwards
        layer?.add(animation, forKey: "remoteAnimatedImage")
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }
        if let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            if let value = png[kCGImagePropertyAPNGUnclampedDelayTime] as? NSNumber { return max(0.02, value.doubleValue) }
            if let value = png[kCGImagePropertyAPNGDelayTime] as? NSNumber { return max(0.02, value.doubleValue) }
        }
        if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let value = gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber { return max(0.02, value.doubleValue) }
            if let value = gif[kCGImagePropertyGIFDelayTime] as? NSNumber { return max(0.02, value.doubleValue) }
        }
        return 0.1
    }
}

struct LoopingRemoteWebMedia: NSViewRepresentable {
    let url: URL
    let backgroundURL: URL?

    private static let mediaDataStore = WKWebsiteDataStore.nonPersistent()

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PassthroughWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.websiteDataStore = Self.mediaDataStore
        let webView = PassthroughWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        load(url: url, in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: PassthroughWebView, context: Context) {
        load(url: url, in: webView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ webView: PassthroughWebView, coordinator: Coordinator) {
        webView.stopLoading()
        coordinator.mediaTask?.cancel()
        coordinator.mediaTask = nil
        coordinator.currentKey = nil
    }

    private func load(url: URL, in webView: WKWebView, coordinator: Coordinator) {
        let key = "\(url.absoluteString)|\(backgroundURL?.absoluteString ?? "")"
        guard coordinator.currentKey != key else { return }
        coordinator.mediaTask?.cancel()
        coordinator.currentKey = key
        coordinator.mediaTask = Task { @MainActor [weak webView] in
            async let videoSource = Self.dataSource(for: url, fallbackMimeType: "video/webm")
            async let stillSource = Self.optionalDataSource(for: backgroundURL, fallbackMimeType: "image/png")
            let sources = await (videoSource, stillSource)
            guard !Task.isCancelled,
                  coordinator.currentKey == key,
                  let webView else { return }
            webView.loadHTMLString(
                html(
                    source: sources.0 ?? escaped(url),
                    backgroundSource: sources.1 ?? nil,
                    canReadVideoPixels: sources.0 != nil
                ),
                baseURL: nil
            )
        }
    }

    private static func dataSource(for url: URL, fallbackMimeType: String) async -> String? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let mimeType = (response as? HTTPURLResponse)?.mimeType ?? fallbackMimeType
            return "data:\(mimeType);base64,\(data.base64EncodedString())"
        } catch {
            return nil
        }
    }

    private static func optionalDataSource(for url: URL?, fallbackMimeType: String) async -> String? {
        guard let url else { return nil }
        return await dataSource(for: url, fallbackMimeType: fallbackMimeType)
    }

    private func html(source: String, backgroundSource: String?, canReadVideoPixels: Bool) -> String {
        let background = backgroundSource.map {
            #"<img id="background" src="\#($0)" alt="">"#
        } ?? ""
        return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>
            html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}
            body{position:relative}
            canvas{position:absolute;inset:0;width:100%;height:100%}
            img{position:absolute;left:-9999px;width:1px;height:1px;opacity:0}
            video{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;opacity:.001;pointer-events:none}
            </style>
            </head><body>\(background)<video id="animation" src="\(source)" autoplay loop muted playsinline></video><canvas id="composite"></canvas>
            <script>
            const canvas = document.getElementById('composite');
            const context = canvas.getContext('2d', { alpha: true });
            const videoCanvas = document.createElement('canvas');
            const videoContext = videoCanvas.getContext('2d', { alpha: true, willReadFrequently: true });
            const background = document.getElementById('background');
            const animation = document.getElementById('animation');
            const canReadVideoPixels = \(canReadVideoPixels ? "true" : "false");

            function resizeCanvas() {
              const scale = window.devicePixelRatio || 1;
              const width = Math.max(1, Math.round(window.innerWidth * scale));
              const height = Math.max(1, Math.round(window.innerHeight * scale));
              if (canvas.width !== width || canvas.height !== height) {
                canvas.width = width;
                canvas.height = height;
                videoCanvas.width = width;
                videoCanvas.height = height;
              }
            }

            function draw() {
              resizeCanvas();
              const width = canvas.width;
              const height = canvas.height;
              context.clearRect(0, 0, width, height);
              context.globalCompositeOperation = 'source-over';
              if (background && background.complete && background.naturalWidth > 0) {
                context.drawImage(background, 0, 0, width, height);
              }
              if (animation.readyState >= 2) {
                if (canReadVideoPixels) {
                  videoContext.clearRect(0, 0, width, height);
                  videoContext.drawImage(animation, 0, 0, width, height);
                  const frame = videoContext.getImageData(0, 0, width, height);
                  const pixels = frame.data;
                  for (let index = 0; index < pixels.length; index += 4) {
                    const brightness = Math.max(pixels[index], pixels[index + 1], pixels[index + 2]);
                    const keyedAlpha = Math.max(0, Math.min(1, (brightness - 3) / 30));
                    pixels[index + 3] = Math.round(pixels[index + 3] * keyedAlpha);
                  }
                  videoContext.putImageData(frame, 0, 0);
                  context.drawImage(videoCanvas, 0, 0);
                } else {
                  context.globalCompositeOperation = 'screen';
                  context.drawImage(animation, 0, 0, width, height);
                }
              }
              context.globalCompositeOperation = 'source-over';
            }

            let lastDrawTime = 0;
            function tick(timestamp) {
              if (timestamp - lastDrawTime >= (1000 / 24)) {
                draw();
                lastDrawTime = timestamp;
              }
              requestAnimationFrame(tick);
            }

            animation.play().catch(() => {});
            requestAnimationFrame(tick);
            </script></body></html>
            """
    }

    private func escaped(_ url: URL) -> String {
        url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    final class Coordinator {
        var currentKey: String?
        var mediaTask: Task<Void, Never>?
    }
}

final class PassthroughWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

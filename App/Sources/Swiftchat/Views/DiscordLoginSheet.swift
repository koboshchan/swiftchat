import DiscordProtocol
import AppKit
import SwiftUI
import WebKit

struct DiscordLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConnected: @MainActor (CredentialHandle) async -> String?
    @State private var isConnecting = false
    @State private var status = "Complete sign-in in the Discord page. Swiftchat will continue automatically."
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Discord Sign-In").font(.headline)
                    Text("This isolated web session is discarded when the window closes.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isConnecting { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }
            }
            .padding(14)
            Divider()
            DiscordWebLoginView { token in authenticate(token) }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Label(status, systemImage: isConnecting ? "arrow.triangle.2.circlepath" : "lock.shield")
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 84, alignment: .leading)
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
    }

    private func authenticate(_ token: String) {
        guard !isConnecting else { return }
        isConnecting = true
        status = "Validating the Discord session and opening the native client…"
        errorMessage = nil
        Task {
            do {
                let handle = try await DiscordSessionAuthenticator().validateAndStore(token: token)
                if let bootstrapError = await onConnected(handle) {
                    errorMessage = bootstrapError
                    status = "Sign-in needs attention."
                    isConnecting = false
                } else {
                    status = "Connected."
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
                status = "Sign-in needs attention."
                isConnecting = false
            }
        }
    }

    private var sheetSize: CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1_200, height: 800)
        return CGSize(
            width: min(780, max(620, visible.width - 140)),
            height: min(650, max(480, visible.height - 120))
        )
    }
}

private struct DiscordWebLoginView: NSViewRepresentable {
    let onCredentialDetected: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCredentialDetected: onCredentialDetected) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "swiftchatSession")
        configuration.userContentController.addUserScript(
            WKUserScript(source: Coordinator.webSocketCaptureScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: URL(string: "https://discord.com/login")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "swiftchatSession")
        nsView.configuration.userContentController.removeAllUserScripts()
        nsView.stopLoading()
        nsView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let onCredentialDetected: @MainActor (String) -> Void
        private var extractionTask: Task<Void, Never>?
        private var didExtract = false

        init(onCredentialDetected: @escaping @MainActor (String) -> Void) {
            self.onCredentialDetected = onCredentialDetected
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            beginExtraction(from: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "swiftchatSession", let token = message.body as? String else { return }
            finish(with: token)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url, let host = url.host?.lowercased() else { return .cancel }
            let allowedSuffixes = ["discord.com", "discordapp.com", "hcaptcha.com", "stripe.com", "paypal.com"]
            if allowedSuffixes.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) { return .allow }
            NSWorkspace.shared.open(url)
            return .cancel
        }

        func stop() {
            extractionTask?.cancel()
            extractionTask = nil
        }

        private func beginExtraction(from webView: WKWebView) {
            guard extractionTask == nil, !didExtract else { return }
            extractionTask = Task { [weak self, weak webView] in
                for _ in 0..<120 {
                    guard let self, let webView, !Task.isCancelled, !self.didExtract else { return }
                    if let token = try? await webView.evaluateJavaScript(Self.extractionScript) as? String,
                       token.count > 20 {
                        self.finish(with: token)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                self?.extractionTask = nil
            }
        }

        private func finish(with token: String) {
            guard !didExtract, token.count > 20 else { return }
            didExtract = true
            extractionTask?.cancel()
            onCredentialDetected(token)
        }

        static let webSocketCaptureScript = #"""
        (() => {
          if (window.__swiftchatSocketCaptureInstalled) return;
          window.__swiftchatSocketCaptureInstalled = true;
          const originalSend = WebSocket.prototype.send;
          WebSocket.prototype.send = function(data) {
            try {
              const payload = JSON.parse(data);
              if (payload && payload.op === 2 && payload.d && typeof payload.d.token === 'string') {
                window.webkit.messageHandlers.swiftchatSession.postMessage(payload.d.token);
              }
            } catch (_) {}
            return originalSend.apply(this, arguments);
          };
        })();
        """#

        private static let extractionScript = #"""
        (() => {
          try {
            const stored = window.localStorage && window.localStorage.getItem('token');
            if (stored && stored.length > 20) return stored.replaceAll('"', '');
          } catch (_) {}
          let found = null;
          try {
            const chunk = window.webpackChunkdiscord_app;
            if (!chunk) return null;
            chunk.push([[Math.random()], {}, require => {
              for (const module of Object.values(require.c || {})) {
                try {
                  const value = module && module.exports;
                  const candidates = [value, value && value.default, value && value.Z, value && value.ZP];
                  for (const candidate of candidates) {
                    if (candidate && typeof candidate.getToken === 'function') {
                      const token = candidate.getToken();
                      if (typeof token === 'string' && token.length > 20) found = token;
                    }
                  }
                } catch (_) {}
              }
            }]);
          } catch (_) {}
          return found;
        })();
        """#
    }
}

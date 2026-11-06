import Cocoa
import WebKit

let appName = "魔兽插件管家"

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var overlay: NSView!
    private var statusLabel: NSTextField!
    private var serverProcess: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var outputBuffer = ""
    private var errorBuffer = ""
    private var readyURL: URL?
    private var didFinishLoading = false
    private var logHandle: FileHandle?
    private var readyTimer: Timer?

    private let dataDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("WowAddonButler", isDirectory: true)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        prepareLog()
        startServer()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        readyTimer?.invalidate()
        stopServer()
        try? logHandle?.close()
    }

    // MARK: - Window

    private func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: 1180, height: 780)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = appName
        window.minSize = NSSize(width: 860, height: 560)
        window.center()
        window.setFrameAutosaveName("WowAddonButlerMainWindow")
        window.backgroundColor = NSColor(calibratedRed: 0.949, green: 0.949, blue: 0.933, alpha: 1)

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "openExternal")
        config.userContentController.add(self, name: "uiReady")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        webView.translatesAutoresizingMaskIntoConstraints = false

        let content = window.contentView!
        content.addSubview(webView)

        overlay = NSView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor(calibratedRed: 0.949, green: 0.949, blue: 0.933, alpha: 1).cgColor
        content.addSubview(overlay)

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        statusLabel = NSTextField(labelWithString: "正在启动本地服务…")
        statusLabel.font = NSFont.systemFont(ofSize: 12.5)
        statusLabel.textColor = NSColor(calibratedWhite: 0.42, alpha: 1)
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3

        let stack = NSStackView(views: [spinner, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.topAnchor.constraint(equalTo: content.topAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: content.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
        ])

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于\(appName)", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏\(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出\(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "显示")
        viewMenu.addItem(withTitle: "重新载入", action: #selector(reloadPage), keyEquivalent: "r")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "进入全屏幕", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appName,
            .applicationVersion: "2.1.9",
            .version: "macOS",
            .credits: NSAttributedString(
                string: "本地运行的魔兽世界插件管理器\n数据保存在 \(dataDir.path)",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ),
        ])
    }

    @objc private func reloadPage() {
        webView.reload()
    }

    // MARK: - Server

    private func prepareLog() {
        let logs = dataDir.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let logURL = logs.appendingPathComponent("launcher.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        logHandle = try? FileHandle(forWritingTo: logURL)
        logHandle?.seekToEndOfFile()
        appendLog("\n=== \(Date()) \(appName) launch ===\n")
    }

    private func appendLog(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        logHandle?.write(data)
    }

    private func resourceURL() -> URL {
        if let url = Bundle.main.resourceURL {
            return url
        }
        return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    }

    private func startServer() {
        let resources = resourceURL()
        let nodeURL = resources.appendingPathComponent("runtime/node")
        let appDir = resources.appendingPathComponent("app", isDirectory: true)
        let serverURL = appDir.appendingPathComponent("server/index.js")

        guard FileManager.default.isExecutableFile(atPath: nodeURL.path) else {
            showError("找不到内置的 Node 运行环境。\n请重新安装软件，或查看 \(dataDir.path)/logs/launcher.log")
            return
        }

        appendLog("node: \(nodeURL.path)\nserver: \(serverURL.path)\n")

        let process = Process()
        process.executableURL = nodeURL
        process.arguments = [serverURL.path]
        process.currentDirectoryURL = appDir
        var env = ProcessInfo.processInfo.environment
        env["PORT"] = "0"
        env["WOW_BUTLER_NO_OPEN"] = "1"
        env["WOW_BUTLER_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        stdoutPipe = outPipe
        stderrPipe = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            if let text = String(data: data, encoding: .utf8) {
                self.appendLog(text)
                self.consumeStdout(text)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            if let text = String(data: data, encoding: .utf8) {
                self.appendLog("ERR \(text)")
                DispatchQueue.main.async {
                    self.errorBuffer += text
                    if self.errorBuffer.count > 4000 {
                        self.errorBuffer = String(self.errorBuffer.suffix(4000))
                    }
                }
            }
        }
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.appendLog("server exited with status \(proc.terminationStatus)\n")
                if self?.readyURL == nil {
                    self?.showError("本地服务启动失败（退出码 \(proc.terminationStatus)）。\n\(self?.errorBuffer ?? "")")
                }
            }
        }

        do {
            try process.run()
            serverProcess = process
            appendLog("server pid \(process.processIdentifier)\n")
        } catch {
            showError("无法启动本地服务：\(error.localizedDescription)\n请查看 \(dataDir.path)/logs/launcher.log")
            return
        }

        readyTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            guard let self, self.readyURL == nil else { return }
            self.showError("本地服务在 25 秒内没有就绪。\n请查看 \(self.dataDir.path)/logs/launcher.log")
        }
    }

    private func consumeStdout(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.outputBuffer += text
            while let range = self.outputBuffer.range(of: "\n") {
                let line = String(self.outputBuffer[..<range.lowerBound])
                self.outputBuffer = String(self.outputBuffer[range.upperBound...])
                if line.hasPrefix("WOW_BUTLER_READY ") {
                    let urlText = String(line.dropFirst("WOW_BUTLER_READY ".count)).trimmingCharacters(in: .whitespaces)
                    if let url = URL(string: urlText) {
                        self.serverReady(url)
                    }
                }
            }
        }
    }

    private func serverReady(_ url: URL) {
        guard readyURL == nil else { return }
        readyURL = url
        readyTimer?.invalidate()
        appendLog("server ready: \(url.absoluteString)\n")
        statusLabel.stringValue = "正在载入界面…"
        var target = url
        if let route = ProcessInfo.processInfo.environment["WOW_BUTLER_ROUTE"],
           !route.isEmpty,
           let routed = URL(string: "\(url.absoluteString)/#/\(route)") {
            target = routed
        }
        webView.load(URLRequest(url: target))
    }

    private func stopServer() {
        guard let process = serverProcess, process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(1.5)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.overlay.isHidden = false
            self.statusLabel.stringValue = message
            self.statusLabel.textColor = NSColor(calibratedRed: 0.64, green: 0.24, blue: 0.22, alpha: 1)
        }
    }

    // MARK: - WebView

    private func captureSnapshot() {
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        webView.takeSnapshot(with: config) { [weak self] image, error in
            guard let self else { return }
            if let error {
                self.appendLog("snapshot failed: \(error.localizedDescription)\n")
                return
            }
            guard let image,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            let url = URL(fileURLWithPath: "/tmp/wow-butler-ui.png")
            try? png.write(to: url)
            self.appendLog("snapshot saved: \(url.path)\n")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishLoading = true
        overlay.isHidden = true
        appendLog("page loaded: \(webView.url?.absoluteString ?? "")\n")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError("界面载入失败：\(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        showError("界面载入失败：\(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.scheme == "http" || url.scheme == "https" {
            let host = url.host ?? ""
            if host == "127.0.0.1" || host == "localhost" || host == "::1" {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.cancel)
            return
        }
        if url.scheme == "mailto" || url.scheme == "tel" {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        appendLog("page loading\n")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let readyURL {
            webView.load(URLRequest(url: readyURL))
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "uiReady" {
            appendLog("ui ready: \(message.body)\n")
            if ProcessInfo.processInfo.environment["WOW_BUTLER_SNAPSHOT"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.captureSnapshot()
                }
            }
            return
        }
        guard message.name == "openExternal" else { return }
        guard let text = message.body as? String, let url = URL(string: text) else { return }
        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

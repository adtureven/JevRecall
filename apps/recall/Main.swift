import AppKit
import SwiftUI
import Carbon

final class SuggestionPanel: NSPanel {
    // The reminder stays non-activating, but becomes key when its editable fields are used.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class QuickSearchPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var model: RecallModel!
    var previousApp: NSRunningApplication?
    var hotkeys: [EventHotKeyRef] = []
    var eventHandler: EventHandlerRef?
    var suggestionPanel: NSPanel?
    var suggestionTimer: Timer?
    var quickSearchPanel: NSPanel?
    let workspace: URL
    let renderPath: String?

    init(workspace: URL, renderPath: String?) { self.workspace = workspace; self.renderPath = renderPath }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let initialFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let cardPreview = renderPath != nil && CommandLine.arguments.contains("--suggestion-card")
        NSApp.appearance = NSAppearance(named: .aqua)
        model = RecallModel(workspace: workspace, preview: renderPath != nil)
        model.copyAndReturn = { [weak self] in
            self?.closeQuickSearch()
            self?.window.orderOut(nil)
            if let target = self?.previousApp, !target.isTerminated { target.activate(options: []) }
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "随手贴 · Recall"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 840, height: 610)
        window.delegate = self
        let hosting = NSHostingView(rootView: RecallView(model: model).padding(.top, 20).background(Color(red: 0.93, green: 0.95, blue: 0.95)))
        window.contentView = hosting
        window.center()
        setupMenus()
        model.discovery.onSuggestionChanged = { [weak self] in self?.updateSuggestion() }
        if renderPath == nil { registerHotkeys() }
        if !cardPreview { showWindow() }
        if cardPreview {
            let example = SaveSuggestion(clip: Clip.examples[0], judgement: SaveJudgement(worthKeeping: 0.96, kind: .command, confidence: 0.95, elapsedMs: 700, cost: nil))
            displaySuggestion(example, preview: true)
        }
        if let path = renderPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, let view = self.suggestionPanel?.contentView ?? self.window.contentView else { NSApp.terminate(nil); return }
                view.layoutSubtreeIfNeeded()
                if cardPreview {
                    print("Reminder focus check: frontmostUnchanged=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == initialFrontPID), panelCanBecomeKey=\(self.suggestionPanel?.canBecomeKey ?? true)")
                }
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        do { try png.write(to: URL(fileURLWithPath: path)); print("UI preview saved: \(path)") }
                        catch { fputs("Unable to save preview.\n", stderr) }
                    }
                }
                NSApp.terminate(nil)
            }
        }
    }

    func setupMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "退出随手贴", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "随手贴")
        statusItem.button?.toolTip = "随手贴 · Ctrl+Option+Space 快速搜索"
        let menu = NSMenu()
        let quick = menu.addItem(withTitle: "快速搜索    ⌃⌥Space", action: #selector(showQuickSearch), keyEquivalent: ""); quick.target = self
        let open = menu.addItem(withTitle: "打开完整窗口", action: #selector(showWindow), keyEquivalent: ""); open.target = self
        let capture = menu.addItem(withTitle: "收下剪贴板    ⌃⌥C", action: #selector(captureClipboard), keyEquivalent: ""); capture.target = self
        menu.addItem(.separator())
        let reveal = menu.addItem(withTitle: "打开数据文件夹", action: #selector(revealData), keyEquivalent: ""); reveal.target = self
        menu.addItem(withTitle: "退出随手贴", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func showWindow() {
        if let current = NSWorkspace.shared.frontmostApplication, current.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = current }
        closeQuickSearch(cancelSearch: false)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        model.focusSearch?()
    }

    @objc func showQuickSearch() {
        if quickSearchPanel != nil { closeQuickSearch(); return }
        if let current = NSWorkspace.shared.frontmostApplication, current.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = current }
        closeQuickSearch()
        model.invalidateSearch()
        model.query = ""
        let panel = QuickSearchPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.hasShadow = true; panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        let controller = QuickSearchController()
        panel.keyHandler = { event in controller.handle(event) }
        let hosting = NSHostingView(rootView: QuickSearchView(model: model, controller: controller, close: { [weak self] in self?.closeQuickSearch() }, openLibrary: { [weak self] in self?.showWindow() }))
        panel.contentView = hosting
        quickSearchPanel = panel
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.midX - 320, y: screen.visibleFrame.maxY - 110))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func closeQuickSearch(cancelSearch: Bool = true) {
        quickSearchPanel?.orderOut(nil); quickSearchPanel = nil
        if cancelSearch { model.invalidateSearch() }
    }
    @objc func captureClipboard() {
        let sourceApp = NSWorkspace.shared.frontmostApplication
        showWindow()
        model.addClipboard(sourceApp: sourceApp)
    }
    func updateSuggestion() {
        suggestionTimer?.invalidate(); suggestionTimer = nil
        suggestionPanel?.orderOut(nil); suggestionPanel = nil
        if let suggestion = model.discovery.suggestion { displaySuggestion(suggestion) }
    }

    func finishSavedSuggestion() {
        guard model.discovery.suggestion == nil else { return }
        suggestionTimer?.invalidate(); suggestionTimer = nil
        suggestionPanel?.orderOut(nil); suggestionPanel = nil
    }

    func displaySuggestion(_ suggestion: SaveSuggestion, preview: Bool = false) {
        let panel = SuggestionPanel(contentRect: NSRect(x: 0, y: 0, width: 370, height: 220), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.hasShadow = true; panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let hosting = FirstMouseHostingView(rootView: SuggestionCard(suggestion: suggestion, save: { [weak self] title, hint in
            self?.model.discovery.accept(title: title, hint: hint, notify: false) ?? false
        }, dismiss: { [weak self] in self?.model.discovery.dismiss() }, pause: { [weak self] in self?.model.discovery.pause() }, quiet: { [weak self] in self?.model.discovery.quietCurrentKind() }, finish: { [weak self] in self?.finishSavedSuggestion() }))
        panel.contentView = hosting
        let size = hosting.fittingSize
        panel.setContentSize(NSSize(width: 370, height: max(205, size.height)))
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - 390, y: screen.visibleFrame.maxY - 20))
        }
        suggestionPanel = panel
        panel.orderFrontRegardless()
        if !preview {
            suggestionTimer = Timer.scheduledTimer(withTimeInterval: 18, repeats: false) { [weak self] _ in Task { @MainActor in
                guard self?.model.discovery.suggestion?.id == suggestion.id else { return }
                self?.model.discovery.dismiss()
            } }
        }
    }
    @objc func revealData() {
        let dataFolder = workspace.appendingPathComponent(".local/recall")
        if FileManager.default.fileExists(atPath: dataFolder.path) { NSWorkspace.shared.open(dataFolder) }
        else { model.notice = "保存第一条收藏后会创建数据文件夹。"; showWindow() }
    }

    func registerHotkeys() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            let hotkeyID = id.id
            Task { @MainActor in
                if hotkeyID == 1 { delegate.showQuickSearch() }
                if hotkeyID == 2 { delegate.captureClipboard() }
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard installed == noErr else { model.hotkeyAvailable = false; return }
        for (key, id) in [(UInt32(kVK_Space), UInt32(1)), (UInt32(kVK_ANSI_C), UInt32(2))] {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(key, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x52434C50, id: id), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            if status == noErr, let reference { hotkeys.append(reference) }
            else { model.hotkeyAvailable = false; model.notice = "快捷键被其他应用占用，可通过菜单栏「随手贴」打开或收藏。" }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.discovery.setEnabled(false, persist: false)
        suggestionTimer?.invalidate()
        closeQuickSearch()
        hotkeys.forEach { UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct RecallMain {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        let renderPath = arguments.firstIndex(of: "--render-preview").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let bundled = Bundle.main.url(forResource: "workspace", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = URL(fileURLWithPath: bundled ?? FileManager.default.currentDirectoryPath)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate(workspace: workspace, renderPath: renderPath)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

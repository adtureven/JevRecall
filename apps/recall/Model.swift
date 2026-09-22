import SwiftUI
import AppKit

@MainActor
final class RecallModel: ObservableObject {
    @Published var clips: [Clip] = []
    @Published var query = "" { didSet { if query != oldValue { invalidateSearch(); scheduleLiveSearch() } } }
    @Published var localSearch = false { didSet { if localSearch != oldValue { invalidateSearch(); scheduleLiveSearch() } } }
    @Published var selectedID: String?
    @Published var result: SearchResult?
    @Published var busy = false
    @Published var error: String?
    @Published var notice: String?
    @Published var duplicateMatch: Clip?
    @Published var settings: JevSettings
    @Published var settingsError: String?
    @Published var editing: Clip?
    @Published var filter = "全部"
    @Published var hotkeyAvailable = true
    var copyAndReturn: (() -> Void)?
    var focusSearch: (() -> Void)?
    private var searchTask: Task<Void, Never>?
    private var generation = UUID()
    private var searchCache: [String: SearchResult] = [:]
    private var writeBlocked = false
    private let preview: Bool
    let repository: ClipRepository
    var client: JevClient
    let workspace: URL
    let discovery: ClipboardDiscovery
    private let settingsStore: JevSettingsStore
    private var debounceTask: Task<Void, Never>?

    init(workspace: URL, preview: Bool = false) {
        self.workspace = workspace
        self.preview = preview
        repository = ClipRepository(url: workspace.appendingPathComponent(".local/recall/library.json"))
        let env = readEnvironment(at: workspace.appendingPathComponent(".env"))
        let store = JevSettingsStore(url: workspace.appendingPathComponent(".local/recall/settings.json"))
        let environmentKey = env["OPENROUTER_API_KEY"] ?? ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
        let environmentModel = env["JEV_MODEL"] ?? "~typesafe/jev-latest"
        let storedSettings = store.load() ?? JevSettings(apiKey: "", endpoint: JevClient.defaultEndpoint.absoluteString, model: environmentModel)
        settingsStore = store
        settings = storedSettings
        let endpoint = URL(string: storedSettings.endpoint) ?? JevClient.defaultEndpoint
        client = JevClient(apiKey: storedSettings.apiKey.isEmpty ? environmentKey : storedSettings.apiKey, model: storedSettings.model.isEmpty ? environmentModel : storedSettings.model, endpoint: endpoint)
        discovery = ClipboardDiscovery(client: client, rememberPreferences: !preview)
        if preview { clips = Clip.examples }
        else {
            do { clips = try repository.load() }
            catch { self.error = "无法读取收藏，已暂停写入以保留原文件：\(error.localizedDescription)"; writeBlocked = true }
        }
        selectedID = clips.first?.id
        discovery.savedClips = { [weak self] in self?.clips ?? [] }
        discovery.onSave = { [weak self] clip in
            guard let self else { return false }
            self.save(clip)
            return self.clips.contains { $0.text == clip.text }
        }
        if discovery.rememberedEnabled { discovery.setEnabled(true) }
    }

    var visible: [Clip] {
        var items = clips
        if filter == "置顶" { items = items.filter(\.pinned) }
        else if filter == "仅本地" { items = items.filter(\.localOnly) }
        else if filter != "全部" { items = items.filter { $0.category == filter } }
        if localSearch && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
            return items.filter { clip in terms.allSatisfy { clip.searchText.localizedCaseInsensitiveContains($0) } }
        }
        if let result {
            if result.noMatch { return [] }
            return result.ranked.filter { $0.probability > 0 }.compactMap { entry in items.first { $0.id == entry.id } }
        }
        return items.sorted { a, b in a.pinned == b.pinned ? a.createdAt > b.createdAt : a.pinned }
    }
    var selected: Clip? { visible.first { $0.id == selectedID } ?? visible.first }
    var configured: Bool { !client.apiKey.isEmpty && client.apiKey != "your_openrouter_api_key" }

    @discardableResult
    func saveSettings(apiKey: String, endpoint: String, model: String) -> Bool {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEndpoint.isEmpty, let url = URL(string: cleanEndpoint), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            settingsError = "接口 URL 需要是完整的 http:// 或 https:// 地址。"; return false
        }
        guard !cleanModel.isEmpty, cleanModel.count <= 200 else {
            settingsError = "模型名称不能为空，且最多 200 个字符。"; return false
        }
        let next = JevSettings(apiKey: cleanKey, endpoint: url.absoluteString, model: cleanModel)
        do { try settingsStore.save(next) }
        catch { settingsError = "设置保存失败：\(error.localizedDescription)"; return false }
        let env = readEnvironment(at: workspace.appendingPathComponent(".env"))
        let environmentKey = env["OPENROUTER_API_KEY"] ?? ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
        client = JevClient(apiKey: cleanKey.isEmpty ? environmentKey : cleanKey, model: cleanModel, endpoint: url)
        settings = next
        settingsError = nil
        searchCache.removeAll()
        discovery.updateClient(client)
        invalidateSearch()
        notice = "JEV 设置已保存并应用。"
        return true
    }

    func invalidateSearch() {
        generation = UUID(); searchTask?.cancel(); searchTask = nil
        debounceTask?.cancel(); debounceTask = nil
        busy = false; result = nil; notice = nil
    }

    private func scheduleLiveSearch() {
        debounceTask?.cancel(); debounceTask = nil
        guard !preview, !localSearch, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.search()
        }
    }

    func search() {
        if localSearch { return }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "描述一下你想找的内容。"; return }
        guard !preview else { notice = "界面预览模式不会发起网络请求。"; return }
        invalidateSearch()
        error = nil; busy = true; filter = "全部"
        let revision = generation, capturedQuery = query, capturedClips = clips
        if let cached = searchCache[capturedQuery] {
            result = cached; selectedID = cached.noMatch ? nil : cached.ranked.first?.id; busy = false
            return
        }
        searchTask = Task {
            do {
                let response = try await client.search(query: capturedQuery, clips: capturedClips)
                guard !Task.isCancelled, generation == revision else { return }
                searchCache[capturedQuery] = response
                if searchCache.count > 24, let oldest = searchCache.keys.first { searchCache.removeValue(forKey: oldest) }
                result = response; selectedID = response.noMatch ? nil : response.ranked.first?.id
                busy = false
            } catch is CancellationError {
                if generation == revision { busy = false }
            } catch {
                guard generation == revision else { return }
                self.error = error.localizedDescription; busy = false
            }
        }
    }

    func persist(_ next: [Clip]) -> Bool {
        guard !writeBlocked else { error = "收藏文件读取失败，请先修复 .local/recall/library.json 再重新打开应用。"; return false }
        do {
            if !preview { try repository.save(next) } else { try ClipRepository.validate(next) }
            clips = next; searchCache.removeAll(); invalidateSearch(); error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func save(_ clip: Clip) {
        var next = clips
        var updated = clip
        updated.title = clip.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = next.firstIndex(where: { $0.id == clip.id }) { next[index] = updated }
        else if let duplicate = next.first(where: { $0.text == clip.text }) {
            query = ""; filter = "全部"; selectedID = duplicate.id; editing = nil; duplicateMatch = nil; notice = "这段原文已经收藏过了。"; return
        } else { next.insert(updated, at: 0) }
        if persist(next) { selectedID = updated.id; editing = nil; duplicateMatch = nil; query = ""; filter = "全部"; notice = "已保存到本地。" }
    }

    func addClipboard(from pasteboard: NSPasteboard = .general, sourceApp: NSRunningApplication? = nil) {
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "剪贴板里没有文本。先复制一段文字，再点「收下剪贴板」。"; return }
        guard text.count <= 8000 else { error = "这段文本超过 8000 字，请先选取需要保存的部分。"; return }
        var clip = Clip.fromText(text)
        let source = sourceApp ?? NSWorkspace.shared.frontmostApplication
        clip.sourceApp = source?.localizedName
        clip.sourceBundleID = source?.bundleIdentifier
        clip.copiedAt = Date()
        duplicateMatch = clips.map { ($0, Clip.similarity($0.text, text)) }
            .filter { $0.1 >= 0.82 }
            .max(by: { $0.1 < $1.1 })?.0
        editing = clip
    }

    func loadExamples() {
        let additions = Clip.examples.filter { sample in !clips.contains { $0.id == sample.id || $0.text == sample.text } }
        if persist(clips + additions) { query = ""; filter = "全部"; selectedID = additions.first?.id ?? clips.first?.id; notice = "已加入 \(additions.count) 条示例。示例服务器和会议地址需要替换后才能使用。" }
    }

    func delete(_ clip: Clip) {
        if persist(clips.filter { $0.id != clip.id }) { selectedID = visible.first?.id; notice = "已删除「\(clip.title)」。" }
    }
    func togglePin(_ clip: Clip) {
        var item = clip; item.pinned.toggle(); save(item)
    }
    func copy(_ clip: Clip, returnToApp: Bool = false, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard pasteboard.setString(clip.text, forType: .string) else { error = "复制失败，请重试。"; return }
        notice = "已复制完整原文。"
        if returnToApp { copyAndReturn?() }
    }
    func chooseNext(_ delta: Int) {
        let items = visible
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = items[max(0, min(items.count - 1, index + delta))].id
    }
}

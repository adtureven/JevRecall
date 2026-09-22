import SwiftUI
import AppKit

private let ink = Color(red: 0.09, green: 0.29, blue: 0.24)
private let backdrop = Color(red: 0.93, green: 0.95, blue: 0.95)
private let muted = Color(red: 0.40, green: 0.49, blue: 0.46)

func symbol(for category: String) -> String {
    ["命令": "terminal", "链接": "link", "回复": "bubble.left.and.text.bubble.right", "任务": "checklist", "文本": "doc.text"][category] ?? "doc.text"
}

struct RecallView: View {
    @ObservedObject var model: RecallModel
    @ObservedObject var discovery: ClipboardDiscovery
    @FocusState private var searchFocused: Bool
    @State private var deleting: Clip?
    @State private var showDetails = false
    @State private var showHelp = false
    @State private var showDiscovery = false
    @State private var showSettings = false

    init(model: RecallModel) { self.model = model; self.discovery = model.discovery }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBox
            if let error = model.error { banner(error, icon: "exclamationmark.circle", warning: true) }
            else if let notice = model.notice { banner(notice, icon: "checkmark.circle", warning: false) }
            if let result = model.result { resultBar(result) }
            HStack(spacing: 0) {
                library.frame(minWidth: 270, idealWidth: 310, maxWidth: 360)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .foregroundStyle(ink).background(backdrop)
        .frame(minWidth: 820, minHeight: 580)
        .tint(ink)
        .onAppear { searchFocused = true; model.focusSearch = { searchFocused = true } }
        .sheet(item: $model.editing) { clip in EditorView(clip: clip, model: model) }
        .sheet(isPresented: $showDetails) { decisionSheet }
        .sheet(isPresented: $showHelp) { helpSheet }
        .sheet(isPresented: $showDiscovery) { discoverySheet }
        .sheet(isPresented: $showSettings) { SettingsView(model: model, dismiss: { showSettings = false }) }
        .alert("删除这条收藏？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) { if let clip = deleting { model.delete(clip) }; deleting = nil }
        } message: { Text("\(deleting?.title ?? "") 的完整原文将从本地收藏中删除。") }
        .onExitCommand { if model.busy { model.invalidateSearch() } else { NSApp.keyWindow?.orderOut(nil) } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.on.square.fill").font(.system(size: 26)).rotationEffect(.degrees(-8))
                .frame(width: 45, height: 45).background(ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("随手贴").font(.system(size: 23, weight: .bold, design: .rounded))
                Text("记得用途，就能找回。").font(.system(size: 12)).foregroundStyle(muted)
            }
            Spacer()
            Button { showSettings = true } label: { Image(systemName: "gearshape").font(.system(size: 17)) }.buttonStyle(.plain).help("JEV 设置")
            Button { showHelp = true } label: { Image(systemName: "questionmark.circle").font(.system(size: 17)) }.buttonStyle(.plain).help("使用说明与快捷键")
            Button { showDiscovery = true } label: {
                Label(discovery.enabled ? (discovery.pausedUntil == nil ? "发现中" : "已暂停") : "自动发现", systemImage: discovery.enabled ? "sparkle.magnifyingglass" : "sparkles")
            }.buttonStyle(.bordered).controlSize(.large).help("判断新复制的内容是否值得收藏")
            Button { model.addClipboard() } label: { Label("收下剪贴板", systemImage: "clipboard") }.buttonStyle(.bordered).controlSize(.large)
            Button { model.duplicateMatch = nil; model.editing = Clip(title: "", text: "") } label: { Label("新片段", systemImage: "plus") }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut("n")
        }.padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 20)
    }

    private var searchBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: model.localSearch ? "magnifyingglass" : "sparkle").font(.system(size: 20)).foregroundStyle(muted)
                TextField(model.localSearch ? "搜索原文、标题或用途提示…" : "比如：婉拒一个临时会议，但愿意看纪要", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 16)).focused($searchFocused)
                    .onSubmit { model.search() }
                    .accessibilityIdentifier("search-query")
                if !model.query.isEmpty {
                    Button { model.query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(muted) }.buttonStyle(.plain).help("清空查找")
                }
                if model.busy {
                    ProgressView().controlSize(.small)
                    Button("取消") { model.invalidateSearch() }.buttonStyle(.borderless)
                } else if !model.localSearch {
                    Button("语义查找 ↵") { model.search() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("semantic-search")
                }
            }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ink.opacity(searchFocused ? 0.3 : 0.1)))
            HStack(spacing: 12) {
                Picker("查找方式", selection: $model.localSearch) { Text("按意思找 · JEV").tag(false); Text("关键词 · 离线").tag(true) }.pickerStyle(.segmented).frame(width: 270)
                Spacer()
                Text(model.localSearch ? "本地搜索完整原文，包含「仅本地」片段。" : "点击查找时，发送检索词及可检索片段摘要。")
                    .font(.system(size: 11)).foregroundStyle(muted)
            }
        }.padding(.horizontal, 26).padding(.bottom, 20)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.result == nil ? "我的收藏" : "查找结果").font(.system(size: 12, weight: .semibold))
                Text("\(model.visible.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                Spacer()
                Picker("分类", selection: $model.filter) {
                    ForEach(["全部", "置顶", "任务", "命令", "链接", "回复", "文本", "仅本地"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 100)
            }.padding(.horizontal, 20).padding(.top, 17)
            if model.visible.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: model.result?.noMatch == true ? "magnifyingglass" : "tray").font(.system(size: 26)).foregroundStyle(muted)
                    Text(model.result?.noMatch == true ? "收藏里没有合适的内容" : "这里还没有片段").font(.headline)
                    Text(model.clips.isEmpty ? "先收下一段常用文字，或载入示例试一试。" : "换一种描述，或清空查找、切换分类。")
                        .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4)
                    if model.clips.isEmpty { Button("载入 10 条示例") { model.loadExamples() }.buttonStyle(.bordered) }
                    else { Button("查看全部收藏") { model.query = ""; model.filter = "全部" }.buttonStyle(.bordered) }
                }.padding(24)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(model.visible) { clip in
                                Button { model.selectedID = clip.id } label: { row(clip) }.buttonStyle(.plain).id(clip.id)
                            }
                        }.padding(.horizontal, 10).padding(.bottom, 18)
                    }.onChange(of: model.selectedID) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }.background(ink.opacity(0.025))
    }

    private func row(_ clip: Clip) -> some View {
        let selected = model.selected?.id == clip.id
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(for: clip.category)).font(.system(size: 16)).frame(width: 30, height: 32)
                .background(selected ? ink.opacity(0.09) : Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(clip.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if clip.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(muted) }
                }
                Text(clip.hint.isEmpty ? clip.text : clip.hint).font(.system(size: 11)).foregroundStyle(muted).lineLimit(2).lineSpacing(3)
                HStack(spacing: 6) {
                    Text(clip.category)
                    if clip.isExample { Text("· 示例") }
                    if clip.localOnly { Label("仅本地", systemImage: "lock") }
                    if let source = clip.sourceDescription { Text("· \(source)").lineLimit(1) }
                    if let probability = model.result?.ranked.first(where: { $0.id == clip.id })?.probability {
                        Spacer(); Text("\(Int((probability * 100).rounded()))%").monospacedDigit()
                    }
                }.font(.system(size: 10)).foregroundStyle(muted)
            }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? ink.opacity(0.16) : Color.clear))
            .contentShape(Rectangle())
    }

    @ViewBuilder private var detail: some View {
        if let clip = model.selected {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(clip.category, systemImage: symbol(for: clip.category)).font(.system(size: 12)).foregroundStyle(muted)
                    if clip.isExample { Text("示例内容").font(.system(size: 10)).padding(.horizontal, 7).padding(.vertical, 3).background(backdrop, in: Capsule()) }
                    if let capture = clip.captureDescription { Text(capture).font(.system(size: 10)).foregroundStyle(muted) }
                    Spacer()
                    Button { model.togglePin(clip) } label: { Image(systemName: clip.pinned ? "pin.fill" : "pin") }.buttonStyle(.plain).help(clip.pinned ? "取消置顶" : "置顶")
                    Button { model.editing = clip } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.plain).padding(.leading, 8).help("编辑片段")
                    Button { deleting = clip } label: { Image(systemName: "trash") }.buttonStyle(.plain).padding(.leading, 8).help("删除片段")
                }
                Text(clip.title).font(.system(size: 24, weight: .semibold, design: .rounded)).textSelection(.enabled)
                if !clip.hint.isEmpty { Text(clip.hint).font(.system(size: 13)).foregroundStyle(muted).lineSpacing(4).textSelection(.enabled) }
                ScrollView {
                    Text(clip.text).font(clip.category == "命令" ? .system(size: 14, design: .monospaced) : .system(size: 16))
                        .lineSpacing(7).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(20)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(backdrop.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Label(clip.localOnly ? "仅保存在本地检索" : "完整原文 · \(clip.text.count) 字", systemImage: clip.localOnly ? "lock" : "checkmark.seal")
                        .font(.system(size: 11)).foregroundStyle(muted)
                    Spacer()
                    Button("复制原文") { model.copy(clip) }.buttonStyle(.bordered).controlSize(.large).keyboardShortcut("c", modifiers: [.command, .shift])
                    Button("复制并返回 ↵") { model.copy(clip, returnToApp: true) }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return, modifiers: .command)
                }
            }.padding(26).background(.white)
        } else {
            VStack(spacing: 15) {
                Image(systemName: "square.on.square").font(.system(size: 45, weight: .ultraLight)).foregroundStyle(muted)
                Text(model.result?.noMatch == true ? "没存过，就不硬凑。" : "那些总要再找一次的文字。")
                    .font(.system(size: 23, weight: .medium, design: .rounded))
                Text(model.result?.noMatch == true ? "试着补充一条收藏，或用别的用途描述再找一次。" : "常用命令、会议链接、恰到好处的回复。\n存下来，下次只要记得它的用途。")
                    .font(.system(size: 13)).foregroundStyle(muted).multilineTextAlignment(.center).lineSpacing(6)
                if model.clips.isEmpty { Button("从示例开始") { model.loadExamples() }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 5) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
        }
    }

    private func banner(_ message: String, icon: String, warning: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(message).font(.system(size: 12)).textSelection(.enabled)
            Spacer()
            Button { model.error = nil; model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭提示")
        }.foregroundStyle(warning ? Color(red: 0.62, green: 0.27, blue: 0.17) : ink)
            .padding(.horizontal, 26).padding(.vertical, 11).background(warning ? Color.orange.opacity(0.08) : ink.opacity(0.05))
    }

    private func resultBar(_ result: SearchResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.noMatch ? "minus.circle" : result.uncertain ? "questionmark.circle" : "sparkle")
            Text(result.noMatch ? "没有足够匹配的收藏" : result.uncertain ? "几个候选都可能符合，复制前看一眼原文。" : "找到了可能用得上的原文")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(String(format: "%.2f s", Double(result.elapsedMs) / 1000)).monospacedDigit().font(.system(size: 11)).foregroundStyle(muted)
            Button("查看决策") { showDetails = true }.buttonStyle(.borderless).font(.system(size: 11))
        }.padding(.horizontal, 26).padding(.vertical, 11).background(ink.opacity(0.04))
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(model.hotkeyAvailable ? "⌃ ⌥ Space  快速搜索" : "快捷键冲突 · 可点菜单栏图标打开")
            Text("⌃ ⌥ C  收藏剪贴板")
            Spacer()
            Text("\(model.clips.count)/64 条 · 本地保存")
            Circle().fill(model.configured ? ink.opacity(0.7) : Color.orange).frame(width: 6, height: 6)
            Text(model.configured ? "JEV 已配置" : "JEV 未配置")
        }.font(.system(size: 10)).foregroundStyle(muted).padding(.horizontal, 23).padding(.vertical, 12)
            .background(backdrop).overlay(alignment: .top) { Divider() }
    }

    private var decisionSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("这次查找的决策").font(.title2.bold()); Spacer(); Button("完成") { showDetails = false }.keyboardShortcut(.cancelAction) }
            if let result = model.result {
                Text("\(result.model) · \(result.submittedCount) 个候选 · \(result.elapsedMs) ms").font(.system(size: 12, design: .monospaced))
                Text(String(format: "Choice confidence %.2f   ·   Noul 有匹配 %.2f", result.confidence, result.matchProbability)).font(.system(size: 12, design: .monospaced))
                if let cost = result.cost { Text(String(format: "本次 API 费用 $%.7f", cost)).font(.system(size: 12, design: .monospaced)) }
                Text("列表百分比是候选之间的选择概率，不是独立相关度或正确率。语义查找只发送标题、用途提示和前 240 字；长片段可补充用途提示，或用本地关键词搜索完整原文。")
                    .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4)
                ScrollView { Text(result.raw).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.padding(12).background(backdrop, in: RoundedRectangle(cornerRadius: 8))
            }
        }.padding(26).frame(width: 640, height: 480)
    }

    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("让文字随手可得。").font(.title2.bold()); Spacer(); Button("完成") { showHelp = false }.keyboardShortcut(.cancelAction) }
            Text("1. 在任意应用复制文字，按 ⌃⌥C，补充标题与用途后保存。\n2. 按 ⌃⌥Space 呼出快速搜索；再次按可关闭，用一句话描述你需要什么，按回车查找，结果可用 ↑↓ 选择并再次回车复制。需要完整管理收藏时点右上角按钮。\n3. 点「复制并返回」或按 ⌘↵，回到原应用后按 ⌘V 粘贴。")
                .font(.system(size: 14)).lineSpacing(10)
            Divider()
            Text("保存始终由你点击决定。自动发现首次默认关闭；开启后会读取新复制的文本，符合本地筛选条件的内容将发给 JEV 判断。你的开关选择会在下次启动时保留。点「语义查找」后，会发送检索词和可检索片段的标题、用途提示、前 240 字。标记「仅本地」的已存片段不会发送。")
                .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(5)
            Text("数据：.local/recall/library.json\nJEV 设置：.local/recall/settings.json（也可继续使用项目根目录 .env）\n不会自动粘贴、发送消息或执行命令。关闭窗口后仍在菜单栏，⌘Q 完全退出。")
                .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(5)
            Button("加入示例收藏") { model.loadExamples(); showHelp = false }.buttonStyle(.bordered)
        }.padding(28).frame(width: 600)
    }

    private var discoverySheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("让值得留下的内容浮出来。").font(.system(size: 22, weight: .semibold, design: .rounded)); Spacer(); Button("完成") { showDiscovery = false }.keyboardShortcut(.cancelAction) }
            Text("你复制一段内容，JEV 判断它是否值得记录。有明确行动或时间安排时，卡片会显示「加入待办」；其他内容显示「记下来」。")
                .font(.system(size: 14)).lineSpacing(5)
            Toggle("开启剪贴板自动发现", isOn: Binding(get: { discovery.enabled }, set: { discovery.setEnabled($0) }))
                .toggleStyle(.switch).disabled(!model.configured)
            Text("开启后，符合条件的新复制文本（12–4000 字）会自动发送至 OpenRouter / TypeSafe。不会发送现有收藏库。关闭后立即停止读取；已发出的请求无法撤回。首次默认关闭，之后会记住你的开关选择。")
                .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4)
            Divider()
            Text("提醒保持克制").font(.system(size: 13, weight: .semibold))
            Text("• 跳过短句、重复内容、已有收藏，以及能识别的凭据和验证码。\n• 点「少提醒这类」后，该类别 24 小时内不再弹出自动提醒。\n• 尊重应用标记的私密、临时或自动生成内容；敏感识别并不完备。\n• 最多每 90 秒提醒一次，10 分钟内最多 3 次。\n• 提醒约 18 秒后消失。未点保存的原文不写入本地文件。")
                .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(6)
            HStack {
                Circle().fill(discovery.enabled ? ink : muted).frame(width: 7, height: 7)
                Text(discovery.activity).font(.system(size: 12))
                Spacer()
            }
            HStack {
                Text("本次运行已判断 \(discovery.evaluated) 条 · 提醒 \(discovery.suggested) 次").font(.system(size: 11)).foregroundStyle(muted)
                Spacer()
                if discovery.enabled {
                    Button(discovery.pausedUntil == nil ? "暂停 1 小时" : "恢复发现") { if discovery.pausedUntil == nil { discovery.pause() } else { discovery.resume() } }.buttonStyle(.bordered)
                }
            }
            if let suggestion = discovery.suggestion {
                Divider()
                Text(suggestion.clip.title).font(.headline).lineLimit(2)
                HStack { Button("忽略") { discovery.dismiss() }; Button(suggestion.judgement.kind == .action_item ? "加入待办" : "记下来") { discovery.accept() }.buttonStyle(.borderedProminent) }
            }
        }.padding(28).frame(width: 620).tint(ink)
    }
}

@MainActor
final class QuickSearchController: ObservableObject {
    @Published private(set) var selectedIndex = 0
    private var itemCount = 0
    var onSubmit: (() -> Void)?
    var onClose: (() -> Void)?

    func setItemCount(_ count: Int) {
        itemCount = count
        if count == 0 || selectedIndex >= count { selectedIndex = 0 }
    }

    func select(_ index: Int) { if itemCount > 0 { selectedIndex = max(0, min(index, itemCount - 1)) } }

    func move(_ delta: Int) {
        guard itemCount > 0 else { return }
        selectedIndex = max(0, min(itemCount - 1, selectedIndex + delta))
    }

    func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125: move(1); return itemCount > 0
        case 126: move(-1); return itemCount > 0
        case 36, 76: onSubmit?(); return true
        case 53: onClose?(); return true
        default: return false
        }
    }
}

struct QuickSearchView: View {
    @ObservedObject var model: RecallModel
    @ObservedObject var controller: QuickSearchController
    let close: () -> Void
    let openLibrary: () -> Void
    @FocusState private var focused: Bool

    private var candidates: [Clip] {
        guard model.result != nil || (model.localSearch && !model.query.isEmpty) else { return [] }
        return Array(model.visible.prefix(4))
    }

    private func submit() {
        if !candidates.isEmpty { copySelected() }
        else if model.result == nil && !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.search() }
    }

    private func copySelected() {
        guard !candidates.isEmpty else { return }
        model.copy(candidates[controller.selectedIndex], returnToApp: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: model.localSearch ? "magnifyingglass" : "sparkle").foregroundStyle(ink)
                TextField(model.localSearch ? "搜索标题、原文或来源…" : "描述你想找的收藏…", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 18)).focused($focused)
                    .onSubmit { submit() }
                    .accessibilityIdentifier("quick-search-query")
                if model.busy { ProgressView().controlSize(.small) }
                Button(model.localSearch ? "离线" : "JEV") { model.localSearch.toggle(); focused = true }
                    .buttonStyle(.borderless).font(.system(size: 11, weight: .semibold)).foregroundStyle(muted)
                Button(action: openLibrary) { Image(systemName: "rectangle.expand.vertical").font(.system(size: 14)) }
                    .buttonStyle(.plain).help("打开完整窗口")
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 12)) }
                    .buttonStyle(.plain).help("关闭快速搜索")
            }
            Divider()
            if let error = model.error {
                Text(error).font(.system(size: 12)).foregroundStyle(.red).lineLimit(2)
            } else if model.busy {
                Text("正在找回可复用的原文…").font(.system(size: 12)).foregroundStyle(muted)
            } else if let result = model.result, result.noMatch {
                Text("没有找到合适的收藏").font(.system(size: 13)).foregroundStyle(muted)
            } else if model.result != nil || model.localSearch && !model.query.isEmpty {
                let items = candidates
                if items.isEmpty {
                    Text("没有匹配的收藏").font(.system(size: 13)).foregroundStyle(muted)
                } else {
                    VStack(spacing: 5) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, clip in
                            Button {
                                controller.select(index); copySelected()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: symbol(for: clip.category)).frame(width: 22).foregroundStyle(muted)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(clip.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        Text(clip.hint.isEmpty ? clip.text : clip.hint).font(.system(size: 11)).foregroundStyle(muted).lineLimit(1)
                                    }
                                    Spacer()
                                    Text("复制").font(.system(size: 11, weight: .semibold)).foregroundStyle(ink)
                                }.padding(.horizontal, 9).padding(.vertical, 6)
                            }.buttonStyle(.plain)
                                .background(index == controller.selectedIndex ? ink.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            } else {
                Text("按回车查找；选中结果后会复制并回到刚才的应用。\n⌃⌥Space 随时呼出，Esc 关闭。")
                    .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4)
            }
        }.padding(18).frame(width: 640, height: 300, alignment: .topLeading)
            .foregroundStyle(ink).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).tint(ink)
            .onAppear {
                focused = true
                controller.onSubmit = submit
                controller.onClose = close
                controller.setItemCount(candidates.count)
            }
            .onChange(of: model.query) { _, _ in controller.setItemCount(candidates.count) }
            .onChange(of: model.result != nil) { _, _ in controller.setItemCount(candidates.count) }
            .onChange(of: model.localSearch) { _, _ in controller.setItemCount(candidates.count) }
            .onDisappear { controller.onSubmit = nil; controller.onClose = nil }
            .onExitCommand { close() }
    }
}

struct SuggestionCard: View {
    let suggestion: SaveSuggestion
    let save: (String, String) -> Bool
    let dismiss: () -> Void
    let pause: () -> Void
    let quiet: () -> Void
    let finish: () -> Void
    @State private var title: String
    @State private var hint: String
    @State private var saved = false
    @State private var saveError: String?

    init(suggestion: SaveSuggestion, save: @escaping (String, String) -> Bool, dismiss: @escaping () -> Void, pause: @escaping () -> Void, quiet: @escaping () -> Void, finish: @escaping () -> Void) {
        self.suggestion = suggestion; self.save = save; self.dismiss = dismiss; self.pause = pause; self.quiet = quiet; self.finish = finish
        _title = State(initialValue: suggestion.clip.title)
        _hint = State(initialValue: suggestion.clip.hint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(ink)
                Text("这段内容，值得留下吗？").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 11)) }.buttonStyle(.plain).help("忽略这段内容")
            }
            Text(suggestion.clip.text).font(.system(size: 12, design: suggestion.clip.category == "命令" ? .monospaced : .default)).lineSpacing(4).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading).padding(11).background(backdrop, in: RoundedRectangle(cornerRadius: 9))
            TextField("标题", text: $title).textFieldStyle(.roundedBorder)
            TextField("说明：什么时候会想起它？", text: $hint).textFieldStyle(.roundedBorder)
            if let saveError { Text(saveError).font(.system(size: 10)).foregroundStyle(.red) }
            if saved {
                HStack {
                    Spacer()
                    Label("已保存到随手贴", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                }
            } else {
                HStack {
                    Button("少提醒这类", action: quiet).buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(muted)
                    Button("暂停 1 小时", action: pause).buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(muted)
                    Spacer()
                    Button("忽略", action: dismiss).buttonStyle(.bordered)
                    Button(suggestion.judgement.kind == .action_item ? "加入待办" : "记下来") {
                        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanTitle.isEmpty else { saveError = "请填写一个标题。"; return }
                        guard cleanTitle.count <= 60, cleanHint.count <= 120 else { saveError = "标题最多 60 字，说明最多 120 字。"; return }
                        guard save(cleanTitle, cleanHint) else { saveError = "保存没有完成，请检查收藏文件。"; return }
                        withAnimation(.easeOut(duration: 0.15)) { saved = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { finish() }
                    }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7).background(ink, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(.white)
                }
            }
        }.padding(18).frame(width: 370).foregroundStyle(ink)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .tint(ink)
    }
}

struct EditorView: View {
    @State var clip: Clip
    @ObservedObject var model: RecallModel
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(model.clips.contains(where: { $0.id == clip.id }) ? "编辑片段" : "收下一段文字").font(.title2.bold()); Spacer(); Button("取消") { model.duplicateMatch = nil; model.editing = nil }.keyboardShortcut(.cancelAction) }
            if let duplicate = model.duplicateMatch, duplicate.id != clip.id {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(ink)
                    Text("这段内容和「\(duplicate.title)」很相似").font(.system(size: 12)).foregroundStyle(ink)
                    Spacer()
                    Button("查看旧收藏") {
                        model.query = ""; model.filter = "全部"; model.selectedID = duplicate.id; model.duplicateMatch = nil; model.editing = nil
                    }.buttonStyle(.borderless).font(.system(size: 12, weight: .semibold))
                }.padding(11).background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            }
            TextField("标题，比如「连接实验室 GPU」", text: $clip.title).textFieldStyle(.roundedBorder)
            HStack {
                Picker("分类", selection: $clip.category) { ForEach(["文本", "任务", "命令", "链接", "回复"], id: \.self) { Text($0).tag($0) } }.frame(width: 190)
                Spacer(); Toggle("置顶", isOn: $clip.pinned).toggleStyle(.checkbox)
            }
            TextField("用途提示：你会在什么情况下想起它？", text: $clip.hint).textFieldStyle(.roundedBorder)
            Text("完整原文").font(.system(size: 12, weight: .semibold))
            TextEditor(text: $clip.text).font(.system(size: 13, design: .monospaced)).scrollContentBackground(.hidden).padding(10)
                .background(backdrop, in: RoundedRectangle(cornerRadius: 10)).frame(minHeight: 180)
            Toggle("仅本地 · 不发送给模型，只参与关键词查找", isOn: $clip.localOnly).toggleStyle(.checkbox).font(.system(size: 12))
            if Clip.containsSecret(clip.text) { Text("检测到疑似凭据，建议保留「仅本地」。").font(.system(size: 11)).foregroundStyle(.orange) }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Text("\(clip.text.count)/8000 字 · 按原样保存").font(.system(size: 11)).foregroundStyle(muted)
                Spacer()
                Button("保存片段") {
                    do { try ClipRepository.validate([clip]); model.save(clip); error = model.error }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return, modifiers: .command)
            }
        }.padding(26).frame(width: 590, height: 520).tint(ink)
    }
}

struct SettingsView: View {
    @ObservedObject var model: RecallModel
    let dismiss: () -> Void
    @State private var apiKey: String
    @State private var endpoint: String
    @State private var modelName: String

    init(model: RecallModel, dismiss: @escaping () -> Void) {
        self.model = model; self.dismiss = dismiss
        _apiKey = State(initialValue: model.settings.apiKey)
        _endpoint = State(initialValue: model.settings.endpoint)
        _modelName = State(initialValue: model.settings.model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("JEV 设置").font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                Button("完成", action: dismiss).keyboardShortcut(.cancelAction)
            }
            Text("手动配置后，语义查找和自动发现都会使用这里的 API。API Key 只保存在本机 .local/recall/settings.json；API Key 留空时继续使用项目 .env 或环境变量。")
                .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4)
            VStack(alignment: .leading, spacing: 7) {
                Text("API Key").font(.system(size: 12, weight: .semibold))
                SecureField("留空则使用 .env", text: $apiKey).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Decisions API URL").font(.system(size: 12, weight: .semibold))
                TextField("https://openrouter.ai/api/alpha/decisions", text: $endpoint).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("模型").font(.system(size: 12, weight: .semibold))
                TextField("~typesafe/jev-latest", text: $modelName).textFieldStyle(.roundedBorder)
            }
            if let error = model.settingsError {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
            }
            HStack {
                Button("恢复默认") {
                    apiKey = ""; endpoint = JevClient.defaultEndpoint.absoluteString; modelName = "~typesafe/jev-latest"
                }.buttonStyle(.borderless)
                Spacer()
                Button("取消", action: dismiss).buttonStyle(.bordered)
                Button("保存并应用") {
                    if model.saveSettings(apiKey: apiKey, endpoint: endpoint, model: modelName) { dismiss() }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 600).tint(ink)
    }
}

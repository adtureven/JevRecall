import Foundation
import AppKit

@main
struct ModelTests {
    @MainActor static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("recall-model-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = RecallModel(workspace: folder)
        var failures = 0, passes = 0
        func check(_ name: String, _ condition: Bool) {
            if condition { passes += 1; print("PASS \(name)") }
            else { failures += 1; print("FAIL \(name)") }
        }
        model.loadExamples()
        check("examples are explicitly added and persisted", model.clips.count == 10 && FileManager.default.fileExists(atPath: model.repository.url.path))
        let text = "  中文原文\n\n第二行🙂\t\n"
        let clip = Clip(title: "往返保真", text: text, localOnly: true)
        model.save(clip)
        model.save(Clip(title: "重复文本", text: text))
        check("duplicate text selects existing clip", model.clips.count == 11 && model.selected?.id == clip.id)
        model.localSearch = true; model.query = "第二行"
        check("offline search includes local-only full text", model.visible.count == 1 && model.visible.first?.id == clip.id)
        model.filter = "仅本地"
        check("local-only filter preserves matching selection", model.selected?.id == clip.id)
        let reopened = RecallModel(workspace: folder)
        check("library survives reopening", reopened.clips.first?.text == text)
        // A private pasteboard isolates this smoke test from the user's real clipboard.
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var returned = false
        model.copyAndReturn = { returned = true }
        model.copy(clip, returnToApp: true, to: pasteboard)
        check("copy writes exact original, then requests return", pasteboard.string(forType: .string) == text && returned)
        model.addClipboard(from: pasteboard)
        check("capture stages an editable clip before saving", model.editing?.text == text && model.clips.count == 11)
        model.editing = nil
        model.query = ""; model.filter = "全部"
        model.delete(clip)
        check("delete affects only requested clip", model.clips.count == 10 && !model.clips.contains { $0.id == clip.id })
        model.busy = true; model.query = "a new query"
        check("editing query invalidates pending UI state", !model.busy && model.result == nil)
        print("Model/clipboard: \(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}

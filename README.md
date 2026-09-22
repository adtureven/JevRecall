# JevRecall

**A small, native macOS clipboard shelf that helps you save useful text and find it again by describing what you need.**

JevRecall is the first practical experiment in this JEV playground. It watches for deliberate clipboard events, lets you keep the text that is worth reusing, and uses a typed JEV decision to select the best saved snippet for a natural-language request. The original text always stays intact and local; JEV chooses among candidates but never rewrites, executes, or sends them.

The project is intentionally small and inspectable: native SwiftUI/AppKit, local JSON storage, no third-party runtime dependencies, and one Decisions API request when semantic search or optional clipboard discovery is used.

## What it does

- **Save once, reuse later.** Capture a clipboard item with `Ctrl + Option + C`, add a title and a reason to keep it, and copy the original text back unchanged.
- **Search by intent.** Press `Ctrl + Option + Space`, describe the situation in your own words, then use `↑` / `↓` and `Return` to select and copy a result. Press the same shortcut again to close the quick search panel.
- **Discover useful copies.** Optional clipboard discovery asks JEV whether a newly copied text looks worth revisiting. The reminder stays out of the way and never saves anything without a click.
- **Stay local when needed.** Mark a snippet as local-only to include it in offline keyword search while excluding it from semantic requests. Credential-like clipboard content is marked local-only by default.
- **Keep context.** Saved items can include the source application, copy time, category, an editable title, and a short usage hint. Similar content is flagged before it creates a duplicate.
- **Configure JEV from the app.** The gear button accepts an API key, Decisions API URL, and model name. Saving applies the new configuration to search and discovery immediately.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools with a working Swift compiler
- Node.js 22 or later for the convenience scripts
- A JEV-compatible Decisions API endpoint and API key for semantic features

The project has no npm dependencies. You do not need to run `npm install`.

## Build and run

```bash
git clone <your-repository-url>
cd jev-recall

cp .env.example .env
# Edit .env and add OPENROUTER_API_KEY if you want to configure it before launch.

npm run build
npm start
```

The build creates `build/Recall.app` and signs it locally with an ad-hoc signature. The app records the project directory at build time so it can find the local data and `.env` file. If the project moves, build it again.

You can also run the scripts without npm:

```bash
bash scripts/build-recall.sh
open build/Recall.app
```

## Configuration

The default endpoint is:

```text
https://openrouter.ai/api/alpha/decisions
```

For a first launch, `.env` can contain:

```dotenv
OPENROUTER_API_KEY=your_openrouter_api_key
JEV_MODEL=~typesafe/jev-latest
```

For normal use, open the gear button in the main window and edit the API key, endpoint, or model directly. The app stores those values in `.local/recall/settings.json` with owner-only permissions (`0600`). An empty API key in the settings file falls back to `.env` or the `OPENROUTER_API_KEY` environment variable. The settings file, `.env`, local library, build output, and test artifacts are ignored by Git.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `Ctrl + Option + Space` | Toggle the independent quick search panel |
| `Ctrl + Option + C` | Capture the current clipboard text |
| `↑` / `↓` | Move through quick search results |
| `Return` | Copy the selected quick search result and return to the previous app |
| `Cmd + Return` | Copy the selected item and return from the main window |
| `Cmd + Shift + C` | Copy the original text without returning |
| `Cmd + N` | Create a new snippet |
| `Esc` | Cancel the current search or hide the window |
| `Cmd + Q` | Quit JevRecall |

## Privacy and data flow

JevRecall is a local-first utility:

- Saved snippets remain in `.local/recall/library.json` and are copied exactly as entered.
- Offline keyword search scans the complete local text, title, and hint without a network request.
- Semantic search sends the query plus the title, hint, category, and first 240 characters of snippets that are not marked local-only.
- Clipboard discovery, when enabled, sends the newly copied candidate text to the configured endpoint. Existing saved snippets are not sent for that decision.
- The app does not monitor keystrokes, read documents from other applications, execute copied commands, or send messages on your behalf.
- Pending discovery text is held briefly in memory. The app keeps only a bounded in-memory hash set to avoid repeatedly judging the same copy; it is not a clipboard history database.

Clipboard discovery is deliberately conservative but cannot identify every secret or private message. Only enable it when sending copied text to an external model is acceptable. The local-only switch remains the final control.

## Verification

```bash
npm test             # Offline core checks: persistence, privacy filters, and response validation
npm run test:app     # Native capture, edit, save, copy, and isolated clipboard checks
npm run test:discovery
                     # Clipboard discovery state machine and rate-limit checks
npm run test:live    # Real JEV requests; may incur API charges
npm run test:discovery:live
                     # Real discovery examples; may incur API charges
```

The offline and native suites do not require a live API key. The native suites use macOS clipboard and GUI access. Live results are development smoke tests, not accuracy or latency guarantees.

## Project layout

| Path | Purpose |
| --- | --- |
| `apps/recall/Core.swift` | Clip models, local persistence, JEV client, payloads, and response validation |
| `apps/recall/Model.swift` | Application state, search cancellation, settings application, and persistence actions |
| `apps/recall/Views.swift` | SwiftUI main window, quick search, editor, reminder card, and settings view |
| `apps/recall/Main.swift` | Menu bar item, global shortcuts, panels, and returning to the previous app |
| `apps/recall/ClipboardDiscovery.swift` | Clipboard polling, local filters, cooldowns, and discovery decisions |
| `apps/recall/*Tests.swift` | Offline and native validation scripts |
| `scripts/build-recall.sh` | Compiles and signs the local macOS app |
| `experiments/orbit-rescue/` | An earlier paused experiment, unrelated to the Recall app |

## Design principles

1. **The original text is the source of truth.** Models select; they do not rewrite.
2. **Local search always remains available.** Network errors should not prevent finding or copying saved text.
3. **Every network boundary is explicit.** Semantic search is initiated by the user; discovery is optional and visible.
4. **Small typed decisions beat open-ended generation.** The app asks JEV for a constrained choice or classification and validates the response before using it.

## Status

JevRecall is an experimental local utility rather than a polished distribution build. The current implementation focuses on a reliable clipboard workflow and a practical JEV integration. See [`apps/recall/VALIDATION.md`](apps/recall/VALIDATION.md) for the latest local validation record and [`apps/recall/DESIGN.md`](apps/recall/DESIGN.md) for the interaction design notes.

## References

- [TypeSafe System One](https://docs.typesafe.ai/concepts/system-one)
- [TypeSafe Choice](https://docs.typesafe.ai/primitives/choice)
- [OpenRouter Decisions API](https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-questions-and-answers-request)
- [Apple NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)
- [JEV application ideas](https://linux.do/t/topic/2919004)

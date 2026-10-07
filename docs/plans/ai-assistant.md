# Plan: Ember AI Assistant (bring your own AI provider)

Status: draft, not started. Written 2026-10-06.

## Goal

An assistant built into the editor that knows the engine. It can answer questions, write and fix
Ember Script, explain errors, and change the scene ("add a wooden tower with 3 imps on top").
Users connect the AI account they already pay for. Ember Engine itself bills nothing and runs
no server.

## 1. How users connect a provider

### What oh-my-pi does, and why we shouldn't copy all of it
[oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT, a fork of Mario Zechner's Pi) is a
terminal coding agent that talks to many providers. Besides API keys, it offers OAuth
"subscription" logins for Anthropic, OpenAI Codex, Google (Antigravity / Cloud Code Assist),
GitHub Copilot and others. It can also reuse credentials from other tools' config folders
(`.claude`, `.cursor`, ...).

The providers' own rules (checked 2026-10-06; check again before building):

| Subscription | Can a third-party app use it? | Evidence |
|---|---|---|
| **Claude Pro / Max** | **No.** Subscription OAuth tokens are for Claude Code and Claude.ai only. Using them anywhere else, including the Agent SDK, breaks the Consumer Terms. Anthropic has blocked such tokens server-side since January 2026. | Anthropic legal & compliance page, Feb 2026 ([report](https://alternativeto.net/news/2026/2/anthropic-officially-bans-using-subscription-authentication-for-third-party-claude-use)); OpenCode, Cline and others had to switch to API keys. |
| **Google Antigravity / AI Pro / Ultra** | **No.** Antigravity's terms forbid accessing it through third-party tools. In Feb 2026 Google disabled accounts that used Antigravity OAuth through tools like OpenClaw, then auto-restored them. | [Google AI forum threads](https://discuss.ai.google.dev/t/antigravity-gemini-code-assist-disabled-403-tos-violation-appeal-assistance-needed/124025), [news](https://gigazine.net/gsc_news/en/20260224-google-gemini-openclaw-accounts-banned) |
| **ChatGPT Plus / Pro** | **Yes, officially.** "Sign in with ChatGPT" plus the "Use your ChatGPT plan" permission (DevDay, 2026-09-29) lets an app spend the user's plan usage. Open-source, locally run tools can self-register; paid or hosted apps need OpenAI's interest form. | [Overview](https://flaviocopes.com/sign-in-with-chatgpt.md), [Codex auth docs](https://developers.openai.com/codex/auth) |
| GitHub Copilot | Unclear. Check GitHub's terms before offering it. | — |

So Ember should **not** copy oh-my-pi's Claude and Antigravity logins, or its reuse of other
tools' credentials. That would put users' accounts at risk of suspension. Ember can still give
subscribers a legitimate way in, through Route B below.

### Route A: built-in assistant (Ember calls the model)
| Provider | How users connect |
|---|---|
| OpenAI / ChatGPT | **Sign in with ChatGPT** (uses their Plus/Pro plan), or an API key |
| Anthropic (Claude) | API key from the Claude Console |
| Google (Gemini) | Gemini API key (Google AI Studio), or Vertex AI with Google Cloud sign-in |
| OpenRouter | One API key, many models |
| Local (Ollama, LM Studio) | Nothing; runs on the user's PC (free, offline, weaker at tools) |

Settings flow: pick a provider, then sign in or paste a key, then pick a model. Ember tests the
connection with a tiny request and shows the result.

### Route B: use the agent you already pay for (the legitimate way for Claude and Antigravity)
Ember runs a local **MCP server** that exposes its engine tools (section 2): read the scene,
write scripts, play-test, and so on. The user points their own agent at it: Claude Code (with
their Pro/Max plan), Codex CLI, Antigravity CLI, or oh-my-pi itself. The subscription login
stays inside the vendor's own tool, so it stays within each provider's terms.
- Ember shows a "Connect your AI agent" dialog with copy-paste setup for each CLI.
- Same tools, same diff review and undo as Route A. Edits arrive as proposals in the editor.
- Optional later step: launch the user's installed CLI from inside Ember (a terminal panel, or
  the Agent Client Protocol that some editors use) so it feels built in. Check each vendor's
  terms for that step too.

### Key storage
- Desktop and Android: `flutter_secure_storage` (Windows Credential Manager, Android Keystore).
  Never store keys in project files, exports or `SaveData`.
- Web editor: keep the key for the session only, with a clear warning. Some providers block
  direct browser calls (CORS). Anthropic needs an explicit opt-in header for browser access.
- Exported games never include the assistant or any key.

## 2. Architecture

```
lib/ai/
  provider.dart          AiProvider interface: streamChat(messages, tools) -> events
  providers/anthropic.dart   raw HTTP to POST /v1/messages (no official Dart SDK)
  providers/openai.dart      Responses / Chat Completions
  providers/gemini.dart
  providers/openai_compatible.dart  OpenRouter, Ollama, LM Studio (configurable base URL)
  credentials.dart       secure storage, per-provider config
  context_builder.dart   what the assistant can see (below)
  tools.dart             engine tools the model may call (below)
  assistant_session.dart conversation state, streaming, tool loop, cost meter
lib/editor/panels/assistant_panel.dart   chat dock (third workspace tab or side panel)
```

Each adapter converts to and from one internal message and tool format, so the panel and tools
never see provider differences. Everything streams (token-by-token UI, no timeouts on long
answers).

### What the assistant sees (context)
- The Ember Script language guide plus the API reference, generated from `ScriptApi.entries`,
  so it's always in sync with the engine. This is large and never changes, so put it first and
  mark it cacheable (Anthropic prompt caching, OpenAI automatic caching) to cut cost on every
  message.
- A compact summary of the scene: entity tree, components, key properties. The full JSON is
  fetched only through a tool.
- The selected entity, the open script, and current `ScriptProblem`s and console errors.

### Tools the model can call (function calling)
| Tool | Effect |
|---|---|
| `get_scene`, `get_entity(name)`, `list_scripts`, `read_script(file)` | read-only |
| `check_script(file, source)` | compile check via `EmberScripts.check`, no side effects |
| `write_script(file, source)`, `set_property(entity, component, prop, value)`, `add_entity(json)`, `delete_entity(name)` | edits (see safety) |
| `play_for(seconds)` then `get_console()` | runs the scene, reports errors and prints, restores on stop |
| `screenshot_viewport()` | image of the viewport for vision models (later phase) |

### Safety and trust
- Every edit is shown as a proposed change (script diff, entity list) with Apply / Reject. An
  "auto-apply" toggle is available for confident users.
- Applied changes go through `EditorHistory`, so Ctrl+Z undoes AI edits like any other.
- Tool calls are limited to the open project. No file system, shell or network tools.
- Show per-conversation token use and an estimated cost. Optional monthly cap per provider.
- First-run notice saying what gets sent (scene, scripts) to which provider.

## 3. Phases

1. **Foundation.** Provider interface, Anthropic and OpenAI-compatible adapters, secure key
   storage, settings screen, chat panel with streaming. Q&A only, with API-reference context.
   Also the **Ember MCP server** with read-only tools (Route B), because it's small and lets
   Claude Code / Codex / Antigravity subscribers start using their own plans right away.
2. **Tools.** Read tools plus `check_script` and `write_script` with diff review and undo.
   Buttons on errors: "Explain this error" and "Fix it".
3. **Scene editing.** Entity and property tools, "build this for me" requests, `play_for`
   self-testing loop.
4. **More providers and polish.** Sign in with ChatGPT (register Ember as an open-source local
   tool), Gemini, Ollama/LM Studio, per-route model choice (fast model
   for autocomplete, strong model for building), cost meter, conversation history per project.
5. **Later.** Inline code completion in the script editor, viewport screenshots for vision,
   generating pixel art and sounds through providers that offer them.

## 4. Testing
- A fake provider that replays recorded responses, so tests run offline and cost nothing.
- Tool-call tests: given a recorded tool call, the editor ends up in the expected state, and
  undo restores the previous one.
- A small eval set of real tasks ("add a coin that spins", "fix this script") run manually
  against each provider before a release.

## 5. Open questions
- Which provider first? Recommendation: the MCP server (Route B) plus Anthropic and
  OpenAI-compatible adapters (covers OpenRouter and local models) in phase 1.
- Reuse oh-my-pi or Pi code? Both are TypeScript/Bun and Ember is Dart, so not directly. Their
  provider and model registry design, and their model routing per task, are worth studying.
- Re-check every provider's terms right before each release. This area changed several times
  in 2026.
- Panel placement: a third workspace tab next to Scene and Script, or a dock that stays visible
  while editing?
- Should exported games ever get AI features (NPC dialogue)? That needs a server to hide keys,
  so it's a separate project.

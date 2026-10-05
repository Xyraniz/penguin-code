# Penguin Code

Penguin Code is a native desktop interface concept for a coding agent. It uses Flutter's desktop targets and a sky-blue visual system built around an illustrated penguin chat background.

<p align="center">
  <img src="assets/penguin-chat-wallpaper.png" alt="Penguin Code illustrated chat wallpaper" width="820">
</p>

## Current scope

Penguin Code is an early native desktop prototype with a working text chat for OpenAI-compatible Chat Completions providers:

- Collapsible conversation history and chat actions
- Project folders selected through the operating system's folder picker
- Project selection every time a new chat is created
- Recent project switching and chat-to-project association
- Lucide outline icons throughout the application
- Searchable model selection grouped by provider
- Model discovery and refresh through OpenAI-compatible `/models` endpoints
- Provider-reported context and capability metadata in the model picker
- Model-specific reasoning effort selection with provider wire-value mapping
- Streaming chat composer with stop and retry controls
- Explicit project file attachments for chat context
- Computer access selector with chat-only, per-action approval, automatic read, and full access modes
- OpenAI-compatible tool calling for listing, searching, reading, and editing files across computer folders
- Optional Plan first toggle for read-only exploration, plan feedback, approval, and cancellation
- Computer-wide file tools in every access mode, with mode-based approvals and safeguards for paths, file types, output size, and tool rounds
- Approval-gated, unique-match project file edits with inline diffs
- Full access mode for computer-wide text-file edits and shell commands
- Session change review for edits applied to computer files
- Session-only chat history and provider profiles
- Subagent task queue preview
- Change review, tool permission, appearance, and shortcut screens

Projects, chats, messages, provider profiles, API keys, computer access, and the Plan first toggle stay in memory for the current session. Messages are sent to the selected provider's `/chat/completions` endpoint as a streaming request. Model discovery uses the provider's `/models` endpoint when available; the model entered in the profile remains selectable when discovery is unavailable. Metadata such as context size and tool, image, or reasoning capabilities is shown only when the provider returns it. Reasoning effort choices appear only when a model declares supported levels; the selected level is mapped to the provider's `reasoning_effort` value, and **Provider default** leaves that field unset. Use an HTTPS URL for remote providers; unencrypted HTTP is allowed only for loopback addresses such as `localhost` and `127.0.0.1`. The API key is optional for providers that do not require authentication. Project tools require OpenAI-compatible tool calling and are not sent to a model explicitly marked as unsupported.

Computer access can be set to **Chat only**, **Ask before every action**, **Auto-approve reads**, or **Full access**. The selected project remains the default folder, and absolute paths can target any other folder on the computer. **Ask before every action** requests approval for each file listing, search, read, and edit. **Auto-approve reads** runs listings, searches, and reads without approval while edits still ask first. **Full access** also allows edits and shell commands without per-action approval. Outside Full access, file tools are limited to supported text and source files and reject traversal, symbolic links, and common credential or private-key paths. Edits require a prior read, the file to remain unchanged, and the old text to match exactly once. The chat shows the exact replacement before applying it, and the Changes page lists completed edits for the current session.

Full access requires an explicit confirmation. It lets the connected model read and edit UTF-8 text files anywhere on the computer and run shell commands without per-action approval. Commands start in the selected project by default, can use another existing working directory, run for at most 60 seconds, and return at most 16 KiB of output. Text files are limited to 64 KiB and each replacement to 16 KiB. File contents and command output are sent to the selected provider as conversation context, so only use this mode with a model you trust. Stop generation terminates the active shell process.

Plan first is an optional per-chat toggle, separate from computer access, for requests that benefit from review before implementation. Turn it on in the composer to have a tool-capable model inspect the selected project and submit a plan before it can make changes. Absolute paths outside that project remain unavailable during planning. File edits and commands are excluded from the offered tools and rejected if the model attempts them. Approve the plan to continue with the current computer access permissions, request changes with feedback, or cancel without applying changes. Plan first requires file access and a model that supports tools. Its state is kept with the conversation for the current session.

You can also attach up to four source or text files per message, with a 64 KiB limit per file and 128 KiB total. Their project-relative paths and contents are sent to the configured provider with your message. Terminal commands and parallel subagents remain future work.

## Configure a provider

Open **Settings → Models → Add provider** and enter the provider name, base URL, model identifier, and optional API key. For example, a local server can use `http://127.0.0.1:11434/v1` and a remote service should use its HTTPS base URL. Penguin Code discovers the endpoint's models after saving; use **Refresh models** in settings to update the list. The model picker in the top bar searches models by name or provider and displays provider-reported metadata. When the selected model declares reasoning levels, use the adjacent effort menu to choose one; selections are kept per model for the current session. Select a model, create a chat for a project, and send a message. If model discovery is unsupported, the manually entered model remains available.

## Run the desktop app

Install Flutter and the desktop build tools for your operating system, then run:

```powershell
flutter pub get
flutter run -d windows
```

Use `-d macos` or `-d linux` on the matching development platform. Flutter can target native Windows, macOS, and Linux apps; each operating system still needs its own desktop build toolchain.

## Run the UI tests

```powershell
flutter test tests
```

The tests cover the app shell, session-only provider setup, request formatting, streaming responses, endpoint validation, cancellation, attachment safety limits, Plan first review and permission gates, and chat interaction using fake HTTP responses. No live API key or provider is required.

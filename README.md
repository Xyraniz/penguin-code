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
- Streaming chat composer with stop and retry controls
- Explicit project file attachments for chat context
- Project access selector with chat-only, per-action approval, and automatic read modes
- OpenAI-compatible tool calling for listing, searching, and reading project files
- Project-bounded read tools with limits for paths, file types, output size, and tool rounds
- Session-only chat history and provider profiles
- Subagent task queue preview
- Change review, tool permission, appearance, and shortcut screens

Projects, chats, messages, provider profiles, API keys, and the project access mode stay in memory for the current session. Messages are sent to the selected provider's `/chat/completions` endpoint as a streaming request. Model discovery uses the provider's `/models` endpoint when available; the model entered in the profile remains selectable when discovery is unavailable. Metadata such as context size and tool, image, or reasoning capabilities is shown only when the provider returns it. Use an HTTPS URL for remote providers; unencrypted HTTP is allowed only for loopback addresses such as `localhost` and `127.0.0.1`. The API key is optional for providers that do not require authentication. Project tools require OpenAI-compatible tool calling and are not sent to a model explicitly marked as unsupported.

Project access can be set to **Chat only**, **Ask before every action**, or **Auto-approve project reads**. When enabled, the model can list folders, search text, and read supported files inside the selected project. Every action in approval mode appears in chat before it runs. Reads reject paths outside the project, symbolic links, generated folders, unsupported files, and common credential or private-key files. Tool output and search work are bounded. These tools do not edit files or run commands.

You can also attach up to four source or text files per message, with a 64 KiB limit per file and 128 KiB total. Their project-relative paths and contents are sent to the configured provider with your message. File edits, terminal commands, parallel subagents, and change review remain future work.

## Configure a provider

Open **Settings → Models → Add provider** and enter the provider name, base URL, model identifier, and optional API key. For example, a local server can use `http://127.0.0.1:11434/v1` and a remote service should use its HTTPS base URL. Penguin Code discovers the endpoint's models after saving; use **Refresh models** in settings to update the list. The model picker in the top bar searches models by name or provider and displays provider-reported metadata. Select a model, create a chat for a project, and send a message. If model discovery is unsupported, the manually entered model remains available.

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

The tests cover the app shell, session-only provider setup, request formatting, streaming responses, endpoint validation, cancellation, attachment safety limits, and chat interaction using fake HTTP responses. No live API key or provider is required.

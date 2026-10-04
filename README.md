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
- Provider and model selection
- Streaming chat composer with stop and retry controls
- Explicit project file attachments for chat context
- Session-only chat history and provider profiles
- Subagent task queue preview
- Change review, tool permission, appearance, and shortcut screens

Projects, chats, messages, provider profiles, and API keys stay in memory for the current session. Messages are sent to the selected provider's `/chat/completions` endpoint as a streaming request. Use an HTTPS URL for remote providers; unencrypted HTTP is allowed only for loopback addresses such as `localhost` and `127.0.0.1`. The API key is optional for providers that do not require authentication.

Chat reads only source or text files that you explicitly select from the active project, then sends their contents and project-relative paths to the configured provider with your message. You can attach up to four files per message, with a 64 KiB limit per file and 128 KiB total. Files outside the project, generated folders, non-text files, and common credential or private-key files are rejected. Attachments are read-only; other project files stay local. Autonomous file tools, edits, subagents, and change review remain future work.

## Configure a provider

Open **Settings → Models → Add provider** and enter the provider name, base URL, model identifier, and optional API key. For example, a local server can use `http://127.0.0.1:11434/v1` and a remote service should use its HTTPS base URL. Select the configured provider in the top bar, create a chat for a project, and send a message.

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

# Penguin Code

Penguin Code is a native desktop interface concept for a coding agent. It uses Flutter's desktop targets and a sky-blue visual system built around an illustrated penguin chat background.

<p align="center">
  <img src="assets/penguin-chat-wallpaper.png" alt="Penguin Code illustrated chat wallpaper" width="820">
</p>

## Current scope

This early prototype focuses on the application shell and its interaction design:

- Collapsible conversation history and chat actions
- Project folders selected through the operating system's folder picker
- Project selection every time a new chat is created
- Recent project switching and chat-to-project association
- Lucide outline icons throughout the application
- Provider and model selection previews
- Chat composer and task suggestions
- Subagent task queue preview
- Change review, tool permission, appearance, and shortcut screens

Projects and chats only live for the current session. Selecting a folder records it as a chat's intended working directory, but the app does not read or change its files yet. Model profiles, prompt delivery, delegated work, and tool permissions are still previews without an agent runtime. Provider profiles stay in memory for this session, and prompts are not sent anywhere.

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

The tests cover project selection for new chats, conversation history, provider setup preview, and the subagent and changes screens.

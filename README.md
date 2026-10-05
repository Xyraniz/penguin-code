# Penguin Code

Penguin Code is a native desktop interface concept for a coding agent. It uses Flutter's desktop targets and a sky-blue visual system built around an illustrated penguin chat background.

<p align="center">
  <img src="assets/penguin-chat-wallpaper.png" alt="Penguin Code illustrated chat wallpaper" width="820">
</p>

## Current scope

Penguin Code is an early native desktop prototype with a working text chat for OpenAI-compatible Chat Completions providers:

- Collapsible conversation history and chat actions
- Project folders selected through the operating system's folder picker
- Chats can start without a project, with optional project association
- Recent project switching
- Lucide outline icons throughout the application
- Searchable model selection grouped by provider
- Model discovery and refresh through OpenAI-compatible `/models` endpoints
- Provider-reported context and capability metadata in the model picker
- Model-specific reasoning effort selection with provider wire-value mapping
- Streaming chat composer with stop and retry controls
- Source and text file attachments from any folder
- Computer access selector with chat-only, per-action approval, automatic read, and full access modes
- OpenAI-compatible tool calling for listing, searching, reading, and editing files across computer folders
- Optional Plan first toggle for read-only exploration, plan feedback, approval, and cancellation
- Skills library with the bundled Material Design 3 skill and per-chat activation
- Persistent local conversations, editable agent memories, and relevant skill matching
- Local MCP servers over stdio, with tool discovery, pagination, and per-call approval
- Per-chat workspace and output folders for chats without a selected project
- Computer-wide file tools in every access mode, with mode-based approvals and safeguards for paths, file types, output size, and tool rounds
- Approval-gated, unique-match project file edits with inline diffs
- Full access mode for computer-wide text-file edits and shell commands
- Session change review for edits applied to computer files
- Session-only provider profiles and API keys
- Subagent task queue preview
- Change review, tool permission, appearance, and shortcut screens

Conversations and messages are saved as readable local JSON, while provider profiles and API keys stay in memory for the current session. The first launch creates `Documents/Penguin-code` with `Memories.md`, `Chats`, and `Skills`. Each conversation is stored under `Chats/YYYY-MM-DD/<chat-id>/chat.json`; chats without a project also get a `workspace` folder, and every chat gets an `outputs` folder. Deleting a conversation removes its saved history but keeps its workspace and outputs. Selecting a project keeps that project as the chat's working directory. If `Documents/Penguin-code` is already a Penguin Code source checkout, app data uses the operating system's application-data directory to avoid mixing source files and user data.

Open **Settings → Memories** to edit `Memories.md`, disable memory context, and control automatic preference capture and skill matching. Automatic capture only saves messages that look like explicit preferences, and skips common credential patterns. Saved memories are added to provider context only while memory is enabled. Conversation text, attachments, memories, and selected skill guidance are sent to the configured provider when used in a request.

Material Design 3 is bundled with the app and can be added from **Skills**. To add another skill, place a folder containing `SKILL.md` in `Documents/Penguin-code/Skills`, then refresh the Skills page. Penguin Code reads local skill files as guidance, never runs their scripts, and can automatically select up to three skills that match the current request and saved memories. You can also activate local skills manually for a chat. Automatic matching is a lightweight token-overlap ranker; it does not download skills or use a separate embedding service. Skills cannot grant permissions or override the current request.

Messages are sent to the selected provider's `/chat/completions` endpoint as a streaming request. Model discovery uses the provider's `/models` endpoint when available; the model entered in the profile remains selectable when discovery is unavailable. Metadata such as context size and tool, image, or reasoning capabilities is shown only when the provider returns it. Reasoning effort choices appear only when a model declares supported levels; the selected level is mapped to the provider's `reasoning_effort` value, and **Provider default** leaves that field unset. Use an HTTPS URL for remote providers; unencrypted HTTP is allowed only for loopback addresses such as `localhost` and `127.0.0.1`. The API key is optional for providers that do not require authentication. Project tools require OpenAI-compatible tool calling and are not sent to a model explicitly marked as unsupported.

The **Skills** library currently includes Material Design 3 from [hamen/material-3-skill](https://github.com/hamen/material-3-skill), bundled with its reference files and MIT license. Add it once from **Skills**, then enable or disable the **Material 3** chip for each chat. The app selects relevant bundled references and adds them to the provider's system message only while that skill is active. Skill files are available offline; adding a skill does not download or run code and does not change computer-access permissions. The bundled upstream files and source revision are recorded in `assets/skills/material-3/UPSTREAM.md`.

Computer access can be set to **Chat only**, **Ask before every action**, **Auto-approve reads**, or **Full access**. The chat workspace or selected project is the default folder, and absolute paths can target any other folder on the computer. **Ask before every action** requests approval for each file listing, search, read, and edit. **Auto-approve reads** runs listings, searches, and reads without approval while edits still ask first. **Full access** also allows edits and shell commands without per-action approval. Saving a new file to the chat's `outputs` folder follows the selected approval mode and never overwrites an existing file. Outside Full access, file tools are limited to supported text and source files and reject traversal, symbolic links, and common credential or private-key paths. Edits require a prior read, the file to remain unchanged, and the old text to match exactly once. The chat shows the exact replacement before applying it, and the Changes page lists completed edits for the current session.

Full access requires an explicit confirmation. It lets the connected model read and edit UTF-8 text files anywhere on the computer and run shell commands without per-action approval. Commands start in the chat workspace or selected project by default, can use another existing working directory, run for at most 60 seconds, and return at most 16 KiB of output. Text files are limited to 64 KiB and each replacement to 16 KiB. File contents and command output are sent to the selected provider as conversation context, so only use this mode with a model you trust. Stop generation terminates the active shell process.

Plan first is an optional per-chat toggle, separate from computer access, for requests that benefit from review before implementation. Turn it on in the composer to have a tool-capable model inspect the chat workspace or selected project and submit a plan before it can make changes. Absolute paths outside that workspace remain unavailable during planning. File edits and commands are excluded from the offered tools and rejected if the model attempts them. Approve the plan to continue with the current computer access permissions, request changes with feedback, or cancel without applying changes. Plan first requires file access and a model that supports tools. Its state is saved with the conversation.

Open **Settings → MCP servers** to configure local MCP programs. Enter the executable and its arguments separately; arguments are one per line, and Penguin Code does not assemble a shell command. Windows may still dispatch `.bat` and `.cmd` launchers through the system shell. Enable **Connect server** to start it now and again when Penguin Code launches. The app negotiates MCP over newline-delimited JSON-RPC on `stdio`, discovers tools (up to 48 per server and 48 total), and refreshes the list on server notifications or when requested. Connected tool schemas and results are sent to the selected model. Every MCP call requires a separate **Approve once** action, including while Full access is enabled. MCP calls are unavailable in Chat only and Plan first. Calls time out after 30 seconds; protocol messages are limited to 1 MiB, tool argument payloads and individual schemas to 64 KiB, exposed schemas together to 128 KiB, and model-visible results to 24,000 characters. Disconnect or remove a server to stop its process and withdraw its tools. Only connect programs you trust: they run locally as your user and inherit Penguin Code's process environment. Streamable HTTP and other remote MCP transports are not included yet.

You can also attach up to four source or text files per message, with a 64 KiB limit per file and 128 KiB total. Files are selected explicitly, and their paths and contents are sent to the configured provider with your message. Parallel subagents remain future work.

## Configure a provider

Open **Settings → Models → Add provider** and enter the provider name, base URL, model identifier, and optional API key. For example, a local server can use `http://127.0.0.1:11434/v1` and a remote service should use its HTTPS base URL. Penguin Code discovers the endpoint's models after saving; use **Refresh models** in settings to update the list. The model picker in the top bar searches models by name or provider and displays provider-reported metadata. When the selected model declares reasoning levels, use the adjacent effort menu to choose one; selections are kept per model for the current session. Select a model, start a chat with or without a project, and send a message. If model discovery is unsupported, the manually entered model remains available.

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

The tests cover the app shell, session-only provider setup, request formatting, streaming responses, endpoint validation, cancellation, attachment safety limits, Plan first review and permission gates, MCP JSON-RPC discovery and tool routing, and chat interaction using fake HTTP and MCP transports. No live API key, provider, or MCP server is required.

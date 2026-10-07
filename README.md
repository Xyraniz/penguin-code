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
- Automatic conversation-context compaction for long tasks, with the complete transcript preserved locally
- Automatic, saved task-progress checklists for multi-step chats and subagents
- Per-chat `/goal` completion conditions with automatic evaluation and bounded continuation
- `/init` project analysis that creates a reviewed `AGENTS.md` guide
- Source and text file attachments from any folder
- Computer access selector with ask-for-approval, approve-for-me, and full access modes
- OpenAI-compatible tool calling for listing, searching, reading, and editing files across computer folders
- Bounded parallel execution for independent, automatically approved file reads, with results returned in model call order
- Optional Plan first toggle for read-only exploration, plan feedback, approval, and cancellation
- Skills library with community search, preview-before-install, and per-chat activation
- Persistent local conversations, editable agent memories, and relevant skill matching
- Project and nested `AGENTS.md` / `CLAUDE.md` instruction discovery with bounded context
- MCP servers over local stdio, Streamable HTTP, and legacy SSE, with tool discovery, pagination, and per-call approval
- Per-chat workspace and output folders for chats without a selected project
- Recoverable long tool outputs saved to per-chat output files and read in pages
- Computer-wide file tools in every access mode, with mode-based approvals and safeguards for paths, file types, output size, and tool rounds
- Approval-gated, unique-match project file edits with inline diffs
- Full access mode for computer-wide text-file edits and shell commands
- Optional file checkpoints with review, selective restore, and protection for later manual edits
- User-configured before-tool, after-tool, and agent-finished hooks in Settings
- Session change review for edits applied to computer files
- Session-only provider profiles and API keys
- Persistent, resumable subagent conversations with model and UI controls
- Change review, tool permission, appearance, and shortcut screens

Conversations and messages are saved as readable local JSON, while provider profiles and API keys stay in memory for the current session. The first launch creates `Documents/Penguin-code` with `USER.md`, `MEMORY.md`, `Chats`, and `Skills`. `USER.md` stores the user profile and preferences; `MEMORY.md` stores durable agent notes about the environment, conventions, and lessons learned. Existing `Memories.md` content is migrated to `USER.md`. Each conversation is stored under `Chats/YYYY-MM-DD/<chat-id>/chat.json`; chats without a project also get a `workspace` folder, and every chat gets an `outputs` folder. Deleting a conversation removes its saved history but keeps its workspace and outputs. Selecting a project keeps that project as the chat's working directory. If `Documents/Penguin-code` is already a Penguin Code source checkout, app data uses the operating system's application-data directory to avoid mixing source files and user data.

Penguin Code automatically summarizes earlier context when the selected model's reported context window or the request-size safety limit approaches its threshold. This also works during a long coding task: completed tool rounds can be compacted while the latest round stays intact. Penguin Code keeps the full transcript in the chat, stores the latest summary with that conversation, and sends the summary together with recent context and the active user request on later calls. It never cuts through a streamed response or separates a tool call from its result. Multi-step tasks can also keep a saved checklist with pending, in-progress, and completed items. Each conversation and subagent owns its own checklist; the current state remains available after compaction and reopening the chat. If a provider explicitly reports context overflow, Penguin Code attempts one automatic compaction and retry. Summary requests use the selected provider and model and may use additional tokens. If the current message and attachments alone are too large, Penguin Code asks you to shorten them instead of silently dropping earlier context.

Open **Settings → Memories** to edit the user profile and agent notes, disable memory context, and control automatic preference capture and skill matching. Automatic capture saves only messages that look like explicit preferences and skips common credential patterns. When memory is enabled, a tool-capable model can add, replace, or remove concise entries in either file; the app validates each change and blocks credential-like values. Both files are treated as untrusted context and included in later provider requests. Past conversation search is a separate opt-in, off by default. When enabled, the agent can run a read-only search over saved user and assistant messages; only short matching excerpts are sent to the selected provider. Tool output, attachments, and credential-like messages are excluded. The conversation picker can search message text locally even while agent search is off. **Let the agent propose reusable skills** is another opt-in, off by default. When enabled, a tool-capable model may stage a reusable skill proposal after learning a durable workflow or correction. Proposals are stored locally under `Skills/Pending`, must be reviewed and explicitly approved in **Skills**, and never activate automatically. Updates are checked against the current skill file so an intervening local edit is preserved. Conversation text, attachments, memories, and selected skill guidance are sent to the configured provider when used in a request.

Material Design 3 is bundled with the app and can be added from **Skills**. The **Discover skills** catalog searches skills.sh; search queries are sent to that service. Open a result to review its `SKILL.md`, source repository, and reported license before adding it. Installation saves only the reviewed `SKILL.md` and source metadata in `Documents/Penguin-code/Skills`; it does not download or run scripts. You can also add local skill folders containing `SKILL.md` and refresh the Skills page. Penguin Code reads skill files as untrusted guidance and can automatically select up to three installed skills that match the current request and saved memories. You can also activate skills manually for a chat. Automatic matching is a lightweight token-overlap ranker; it does not use a separate embedding service. Skills cannot grant permissions or override the current request.

Messages are sent to the selected provider's `/chat/completions` endpoint as a streaming request. Model discovery uses the provider's `/models` endpoint when available; the model entered in the profile remains selectable when discovery is unavailable. Metadata such as context size and tool, image, or reasoning capabilities is shown only when the provider returns it. Reasoning effort choices appear only when a model declares supported levels; the selected level is mapped to the provider's `reasoning_effort` value, and **Provider default** leaves that field unset. Use an HTTPS URL for remote providers; unencrypted HTTP is allowed only for loopback addresses such as `localhost` and `127.0.0.1`. The API key is optional for providers that do not require authentication. Project tools require OpenAI-compatible tool calling and are not sent to a model explicitly marked as unsupported.

The **Skills** library currently includes Material Design 3 from [hamen/material-3-skill](https://github.com/hamen/material-3-skill), bundled with its reference files and MIT license. Add it once from **Skills**, then enable or disable the **Material 3** chip for each chat. The app selects relevant bundled references and adds them to the provider's system message only while that skill is active. Skill files are available offline; adding a skill does not download or run code and does not change computer-access permissions. The bundled upstream files and source revision are recorded in `assets/skills/material-3/UPSTREAM.md`. With skill learning enabled in **Settings → Memories**, the agent may also propose creating or updating a skill. These proposals stay in `Skills/Pending` until reviewed and explicitly approved in **Skills**. Approval saves the skill but does not activate it in any chat.

Computer access has three modes: **Ask for approval**, **Approve for me**, and **Full access**. The chat workspace or selected project is the default folder, and absolute paths can target any other folder on the computer. **Ask for approval** requests permission for every file action. **Approve for me** automatically approves file listings, searches, and reads; edits, saved outputs, and other actions require approval. **Full access** also allows edits and shell commands without per-action approval. Connected MCP tools always require a separate approval. Saving a new file to the chat's `outputs` folder never overwrites an existing file. Outside Full access, file tools are limited to supported text and source files and reject traversal, symbolic links, and common credential or private-key paths. Edits require a prior read, the file to remain unchanged, and the old text to match exactly once. The chat shows the exact replacement before applying it, and the Changes page lists completed edits for the current session.

Full access requires an explicit confirmation. It lets the connected model read and edit UTF-8 text files anywhere on the computer and run shell commands without per-action approval. Commands start in the chat workspace or selected project by default, can use another existing working directory, run for at most 60 seconds, and capture up to 8 MiB of command output before spilling long results to a chat output file. Text files are limited to 64 KiB and each replacement to 16 KiB. File contents and command output are sent to the selected provider as conversation context, so only use this mode with a model you trust. Stop generation terminates the active shell process.

Plan first is an optional per-chat toggle, separate from computer access, for requests that benefit from review before implementation. Turn it on in the composer to have a tool-capable model inspect the chat workspace or selected project and submit a plan before it can make changes. Absolute paths outside that workspace remain unavailable during planning. File edits and commands are excluded from the offered tools and rejected if the model attempts them. Approve the plan to continue with the current computer access permissions, request changes with feedback, or cancel without applying changes. Plan first requires file access and a model that supports tools. Its state is saved with the conversation.

For project chats, Penguin Code loads `AGENTS.md` and `CLAUDE.md` files from the selected project root through the folder being accessed. It also recognizes `.claude/CLAUDE.md`. If a file action targets a new nested folder, applicable instruction files are loaded into the next model request before that action runs. Instruction files outside the selected project are ignored. Each file contributes up to 16 KiB, the total is capped at 32 KiB, and at most 12 files are included. These files guide project work but cannot grant computer access or override the current request and approval mode. Instructions, memories, and skills are sent to the configured provider as part of the request context.

Open **Settings → MCP servers** to configure local and remote MCP servers. Choose **Local command (stdio)** to enter an executable and its arguments separately; arguments are one per line, and Penguin Code does not assemble a shell command. Choose **HTTP (Streamable HTTP)** for current remote MCP endpoints; it falls back to the legacy HTTP+SSE handshake when the endpoint requires it. Choose **SSE (legacy)** for older MCP servers. Remote URLs must use HTTPS, except HTTP loopback endpoints such as `localhost` and `127.0.0.1`. Optional custom request headers support bearer tokens and API keys; header values are stored in the operating system's secure storage and are never written to app preferences. On macOS, the app uses Keychain; on Windows, the platform secure store; on Linux, install `libsecret-1-dev` and `libjsoncpp-dev` to build, and `libsecret-1-0` and `libjsoncpp1` to run. Enable **Connect server** to start the connection now and again when Penguin Code launches. The app negotiates MCP JSON-RPC, discovers tools (up to 48 per server and 48 total), and refreshes the list when supported or when requested. Connected tool schemas and results are sent to the selected model. Every MCP call requires a separate **Approve once** action, including while Full access is enabled. MCP calls are available in all three computer access modes, but are unavailable in Plan first. Calls time out after 30 seconds; protocol messages are limited to 1 MiB, tool argument payloads and individual schemas to 64 KiB, exposed schemas together to 128 KiB. Long tool results spill to chat outputs and can be read in pages. Disconnect or remove a server to close its connection and withdraw its tools. Only connect servers you trust: their tools can access any data and services granted to that server, and their output is sent to the selected provider.

You can also attach up to four source or text files per message, with a 64 KiB limit per file and 128 KiB total. Files are selected explicitly, and their paths and contents are sent to the configured provider with your message. With **Approve for me** or **Full access** selected, independent read-only project tool calls may run in parallel, with at most three active at once. Mixed batches, actions that need approval, planning, and calls that discover new project instructions stay sequential. Tool results are returned in the original model call order.

Subagents are optional and off by default. Turn them on in **Settings → General**. The selected model can delegate up to three focused tasks at once; each new task starts with a fresh conversation and returns its result to the parent. Subagents use the current provider, working directory, installed skills, memories, and computer access mode. File actions still follow the selected approval mode, and pending approvals, progress, results, and stop controls appear in **Subagents**. Manually delegated tasks use the current project or chat workspace. Each child transcript and task state is saved with local conversation data, without provider credentials, so completed, failed, or stopped tasks can be continued later. Follow-up turns keep the child conversation and project and use the current computer-access setting. The model can list, continue, and stop tasks belonging to its own parent conversation. Turning subagents off prevents new and continued tasks; saved tasks and results remain visible.

**Settings → General** also provides **Output detail** (Model default, Low, Medium, or High) and **Reasoning summary** (Automatic, Concise, Detailed, or None). These preferences are sent as system-message guidance so they work with the app's OpenAI-compatible Chat Completions endpoint; exact behavior depends on the selected model and provider. Reasoning-summary choices request only a high-level explanation and never hidden chain-of-thought.

## Hooks and checkpoints

Open **Settings → Agent hooks** to configure local automations and recovery. Hooks are off by default; enable both the master switch and each hook you want to run. Before-tool commands receive event JSON on standard input. Exit code `2` blocks the action, and a timeout also blocks it; a hook cannot grant computer access or bypass the selected approval mode. After-tool output is returned to the model as context. Agent-finished hooks can run local notifications or other commands when a response ends. Hooks support PowerShell on Windows and the default shell on macOS and Linux, run with your account permissions, and have a configurable timeout and bounded event output. Keep secrets out of hook commands and scripts.

Automatic checkpoints are separately opt-in and default to off. Penguin Code saves a file checkpoint before built-in text edits and generated outputs, and a working-folder checkpoint before shell commands. Data is stored under `Documents/Penguin-code/Checkpoints`, outside the project `.git` directory. Shell checkpoints cover the command's working folder; they skip common build/dependency folders and symbolic links, and stop before an action if the 10,000-file or 250 MiB limit is exceeded. Individual files are limited to 50 MiB. Settings lists checkpoints for review, previews text changes, restores changed files, and keeps later edits when a file no longer matches the state the agent left behind. Pending checkpoints from an interrupted action require an explicit restore confirmation. MCP and other external side effects cannot be reversed by filesystem checkpoints.

## Goal commands

Enter `/goal <completion condition>` in a chat to start work toward a verifiable end state. Penguin Code checks each completed response with the selected provider and continues when the condition is not yet met. Automatic continuation pauses after up to six evaluated turns; `/goal resume` starts a fresh bounded run. Use `/goal` to inspect the goal, `/goal edit <condition>` to replace it, `/goal pause` to pause it, and `/goal clear` to remove it. The selected model also performs completion checks, so no evaluator model or extra provider setup is required. Goal commands are handled by the app and do not change the selected computer-access or approval mode.

## Project initialization and long outputs

Send `/init` in a chat to analyze the current project or that chat's private workspace. The model reviews the top-level files, project manifests, and existing `AGENTS.md` or `CLAUDE.md` instructions, then drafts concise project guidance with build and test commands grounded in the files it inspected. It does not run project commands or edit source code. When approval is required, the full new `AGENTS.md` contents are shown before writing. Full access writes without a per-action prompt. Existing `AGENTS.md` content is never replaced wholesale.

Tool results longer than 12,000 characters are saved under that chat's `outputs` folder and shown as a head-and-tail preview. The agent can retrieve relevant sections with `read_tool_output`, which reads up to 8 KiB per page. Command output is captured up to 8 MiB; anything beyond that limit is marked as incomplete in the preview. Saved tool output is also available in the chat's Outputs folder.

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

The tests cover the app shell, session-only provider setup, request formatting, streaming responses, endpoint validation, cancellation, attachment safety limits, Plan first review and permission gates, ordered parallel reads and their concurrency limit, file checkpoint creation, preview and restore, hook settings and execution policies, staged skill proposal review and safety checks, MCP JSON-RPC discovery and tool routing, and chat interaction using fake HTTP and MCP transports. No live API key, provider, or MCP server is required.

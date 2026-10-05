import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'models.dart';
import 'services/openai_compatible_chat_client.dart';
import 'services/project_attachment_loader.dart';
import 'services/project_tool_executor.dart';
import 'services/tool_call_loop_guard.dart';
import 'screens/app_screens.dart';
import 'screens/settings_screen.dart';
import 'widgets/app_icons.dart';
import 'widgets/model_picker_dialog.dart';
import 'widgets/penguin_mark.dart';

class PenguinCodeApp extends StatelessWidget {
  const PenguinCodeApp({
    super.key,
    this.initialProjects = const [],
    this.chatClient,
    this.attachmentPicker,
  });

  final List<Project> initialProjects;
  final OpenAiCompatibleChatClient? chatClient;
  final Future<List<ChatAttachment>> Function(
    Project project,
    List<ChatAttachment> alreadyAttached,
  )? attachmentPicker;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Penguin Code',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: PenguinHomeShell(
        initialProjects: initialProjects,
        chatClient: chatClient,
        attachmentPicker: attachmentPicker,
      ),
    );
  }
}

class PenguinHomeShell extends StatefulWidget {
  const PenguinHomeShell({
    super.key,
    this.initialProjects = const [],
    this.chatClient,
    this.attachmentPicker,
  });

  final List<Project> initialProjects;
  final OpenAiCompatibleChatClient? chatClient;
  final Future<List<ChatAttachment>> Function(
    Project project,
    List<ChatAttachment> alreadyAttached,
  )? attachmentPicker;

  @override
  State<PenguinHomeShell> createState() => _PenguinHomeShellState();
}

class _PenguinHomeShellState extends State<PenguinHomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _sidebarOpen = true;
  AppPage _page = AppPage.chat;
  SettingsTab _settingsTab = SettingsTab.general;
  final List<Project> _projects = [];
  final List<ChatConversation> _chats = [];
  final List<ProviderProfile> _providers = [];
  final Set<String> _refreshingProviderIds = {};
  final Map<String, String> _modelDiscoveryErrors = {};
  final Map<String, String> _reasoningEffortByModel = {};
  final List<AgentTask> _agentTasks = [];
  final Map<String, List<ChatMessage>> _messagesByChatId = {};
  final Map<String, Completer<void>> _generationStops = {};
  final Map<String, Completer<bool>> _pendingToolApprovals = {};
  final Map<String, Completer<PlanReviewResponse>> _pendingPlanReviews = {};
  late final OpenAiCompatibleChatClient _chatClient;
  final _attachmentLoader = const ProjectAttachmentLoader();
  int _messageId = 0;
  String? _activeChatId;
  String? _activeProjectId;
  String? _selectedProviderId;
  String? _selectedModelId;
  AgentPermissionMode _permissionMode = AgentPermissionMode.askBeforeEachAction;
  bool _draftPlanMode = false;

  @override
  void initState() {
    super.initState();
    _projects.addAll(widget.initialProjects);
    _chatClient = widget.chatClient ?? OpenAiCompatibleChatClient();
  }

  @override
  void dispose() {
    for (final stop in _generationStops.values) {
      if (!stop.isCompleted) stop.complete();
    }
    _chatClient.close();
    super.dispose();
  }

  Project? get _activeProject {
    for (final project in _projects) {
      if (project.id == _activeProjectId) return project;
    }
    return null;
  }

  ChatConversation? get _activeChat {
    for (final chat in _chats) {
      if (chat.id == _activeChatId) return chat;
    }
    return null;
  }

  List<ProjectFileChange> get _projectChanges {
    final projectById = {for (final project in _projects) project.id: project};
    final changes = <ProjectFileChange>[];
    for (final chat in _chats) {
      final projectName = projectById[chat.projectId]?.name;
      if (projectName == null) continue;
      for (final message
          in _messagesByChatId[chat.id] ?? const <ChatMessage>[]) {
        if (message.toolName != 'edit_project_file' ||
            message.toolActionStatus != ToolActionStatus.completed) {
          continue;
        }
        final path = message.toolArguments['file_path'];
        final oldText = message.toolArguments['old_string'];
        final newText = message.toolArguments['new_string'];
        if (path is! String || oldText is! String || newText is! String) {
          continue;
        }
        changes.add(
          ProjectFileChange(
            projectName: projectName,
            chatTitle: chat.title,
            relativePath: path,
            oldText: oldText,
            newText: newText,
          ),
        );
      }
    }
    return List.unmodifiable(changes.reversed);
  }

  ProviderProfile? get _selectedProvider {
    for (final provider in _providers) {
      if (provider.id == _selectedProviderId) {
        return provider.copyWith(
            model:
                _selectedModelId == null ? provider.model : _selectedModelId);
      }
    }
    return null;
  }

  ModelProfile? get _selectedModelProfile {
    final provider = _selectedProvider;
    if (provider == null) return null;
    for (final model in provider.availableModels) {
      if (model.id == provider.model) return model;
    }
    return null;
  }

  String? get _selectedReasoningEffortId {
    final model = _selectedModelProfile;
    if (model == null) return null;
    final id = _reasoningEffortByModel[_selectedModelKey];
    return id != null && model.reasoningEfforts.containsKey(id) ? id : null;
  }

  String get _selectedModelKey =>
      '$_selectedProviderId\u0000${_selectedModelId ?? ''}';

  void _selectReasoningEffort(String? id) {
    final model = _selectedModelProfile;
    if (model == null) return;
    setState(() {
      if (id == null || !model.reasoningEfforts.containsKey(id)) {
        _reasoningEffortByModel.remove(_selectedModelKey);
      } else {
        _reasoningEffortByModel[_selectedModelKey] = id;
      }
    });
  }

  void _showNotice(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _resolveToolApproval(String toolCallId, bool approved) {
    final approval = _pendingToolApprovals[toolCallId];
    if (approval != null && !approval.isCompleted) approval.complete(approved);
  }

  void _resolvePlanReview(String toolCallId, PlanReviewResponse response) {
    final review = _pendingPlanReviews[toolCallId];
    if (review != null && !review.isCompleted) review.complete(response);
  }

  void _approvePlan(String toolCallId) => _resolvePlanReview(
        toolCallId,
        const PlanReviewResponse(decision: PlanReviewDecision.approve),
      );

  void _keepPlanning(String toolCallId, String feedback) => _resolvePlanReview(
        toolCallId,
        PlanReviewResponse(
          decision: PlanReviewDecision.requestChanges,
          feedback: feedback,
        ),
      );

  void _cancelPlan(String toolCallId) => _resolvePlanReview(
        toolCallId,
        const PlanReviewResponse(decision: PlanReviewDecision.cancel),
      );

  void _setChatPlanMode(String chatId, bool enabled) {
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0 || _chats[index].planMode == enabled) return;
    setState(() => _chats[index] = _chats[index].copyWith(planMode: enabled));
  }

  void _setPlanMode(bool enabled) {
    final chatId = _activeChatId;
    if (chatId == null) {
      setState(() => _draftPlanMode = enabled);
      return;
    }
    _setChatPlanMode(chatId, enabled);
  }

  void _changePermissionMode(AgentPermissionMode mode) {
    setState(() {
      _permissionMode = mode;
      if (mode == AgentPermissionMode.chatOnly) {
        _draftPlanMode = false;
        if (_activeChatId != null) {
          final index = _chats.indexWhere((chat) => chat.id == _activeChatId);
          if (index >= 0) {
            _chats[index] = _chats[index].copyWith(planMode: false);
          }
        }
      }
    });
  }

  bool get _canUsePlanMode =>
      _activeProject != null &&
      _selectedProvider != null &&
      _selectedModelProfile?.supportsTools != false &&
      _permissionMode != AgentPermissionMode.chatOnly;

  bool _requiresToolApproval(AgentPermissionMode mode, String toolName) {
    if (mode == AgentPermissionMode.fullAccess) return false;
    if (toolName == 'run_command') return false;
    return toolName == 'edit_project_file' ||
        mode == AgentPermissionMode.askBeforeEachAction;
  }

  void _updateToolAction(
    String toolCallId, {
    required String content,
    required ToolActionStatus actionStatus,
  }) {
    for (final messages in _messagesByChatId.values) {
      final index = messages.indexWhere(
        (message) => message.toolCallId == toolCallId,
      );
      if (index < 0) continue;
      setState(() {
        messages[index] = messages[index].copyWith(
          content: content,
          status: ChatMessageStatus.complete,
          toolActionStatus: actionStatus,
        );
      });
      return;
    }
  }

  void _appendChatMessage(String chatId, ChatMessage message) {
    final messages = _messagesByChatId[chatId];
    if (messages == null) return;
    setState(() => messages.add(message));
  }

  bool _isProviderHistoryMessage(ChatMessage message) =>
      message.status != ChatMessageStatus.failed &&
      (message.role == ChatMessageRole.user ||
          message.role == ChatMessageRole.tool ||
          message.content.isNotEmpty ||
          message.toolCalls.isNotEmpty);

  String _normalizePath(String path) =>
      Platform.isWindows ? path.replaceAll('/', r'\').toLowerCase() : path;

  String _projectNameFromPath(String path) {
    final segments =
        path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).toList();
    return segments.isEmpty ? 'Root' : segments.last;
  }

  Future<Project?> _createProjectFromFolder() async {
    final path = await getDirectoryPath(
      initialDirectory: _activeProject?.path,
      confirmButtonText: 'Use this folder',
    );
    if (path == null || !mounted) return null;

    Project? existing;
    for (final project in _projects) {
      if (_normalizePath(project.path) == _normalizePath(path)) {
        existing = project;
        break;
      }
    }
    final project = existing ??
        Project(
          id: _normalizePath(path),
          name: _projectNameFromPath(path),
          path: path,
        );
    setState(() {
      if (existing == null) _projects.insert(0, project);
      _activeProjectId = project.id;
      _activeChatId = null;
      _page = AppPage.chat;
    });
    if (existing == null) {
      _showNotice('Project added for this session: ${project.name}.');
    }
    return project;
  }

  Future<Project?> _showProjectPicker() {
    return showDialog<Project>(
      context: context,
      builder: (context) => _ProjectPickerDialog(
        projects: _projects,
        selectedProjectId: _activeProjectId,
        onCreateProject: _createProjectFromFolder,
      ),
    );
  }

  Future<void> _chooseProject() async {
    final project = await _showProjectPicker();
    if (project == null || !mounted) return;
    setState(() {
      _activeProjectId = project.id;
      _activeChatId = null;
      _page = AppPage.chat;
    });
    _scaffoldKey.currentState?.closeDrawer();
  }

  Future<void> _createChat() async {
    final project = await _showProjectPicker();
    if (project == null || !mounted) return;
    _startChat(project);
  }

  void _startChat(Project project) {
    final chat = ChatConversation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: 'New chat',
      projectId: project.id,
      planMode: _draftPlanMode,
    );
    setState(() {
      _activeProjectId = project.id;
      _activeChatId = chat.id;
      _chats.insert(0, chat);
      _draftPlanMode = false;
      _page = AppPage.chat;
    });
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _selectChat(String chatId) {
    final chat = _chats.firstWhere((item) => item.id == chatId);
    setState(() {
      _activeChatId = chat.id;
      _activeProjectId = chat.projectId;
      _page = AppPage.chat;
    });
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _selectProject(Project project) {
    setState(() {
      _activeProjectId = project.id;
      _activeChatId = null;
      _page = AppPage.chat;
    });
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _toggleSidebar() {
    if (MediaQuery.sizeOf(context).width < 840) {
      _scaffoldKey.currentState?.openDrawer();
      return;
    }
    setState(() => _sidebarOpen = !_sidebarOpen);
  }

  Widget _buildSidebar() {
    return _Sidebar(
      projects: _projects,
      activeProjectId: _activeProjectId,
      onCreateProject: _createProjectFromFolder,
      onSelectProject: _selectProject,
      chats: _chats,
      activeChatId: _activeChatId,
      page: _page,
      onNewChat: _createChat,
      onSelectChat: _selectChat,
      onRenameChat: _renameChat,
      onDeleteChat: _deleteChat,
      onSelectPage: _selectPage,
    );
  }

  Future<void> _searchChats() async {
    final chatId = await showDialog<String>(
      context: context,
      builder: (context) => _ChatSearchDialog(chats: _chats),
    );
    if (chatId == null || !mounted) return;
    _selectChat(chatId);
  }

  Future<void> _renameChat(String chatId) async {
    final chat = _chats.firstWhere((item) => item.id == chatId);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _RenameChatDialog(initialName: chat.title),
    );
    if (result == null || result.isEmpty || !mounted) return;
    setState(() {
      final index = _chats.indexWhere((item) => item.id == chatId);
      if (index >= 0) _chats[index] = _chats[index].copyWith(title: result);
    });
  }

  Future<void> _deleteChat(String chatId) async {
    final chat = _chats.firstWhere((item) => item.id == chatId);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation'),
        content: Text('Delete “${chat.title}” from this session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    _stopGeneration(chatId);
    setState(() {
      _chats.removeWhere((item) => item.id == chatId);
      _messagesByChatId.remove(chatId);
      if (_activeChatId == chatId) _activeChatId = null;
    });
  }

  void _addProvider(ProviderProfile provider) {
    final configuredModels = provider.availableModels;
    final configuredProvider = provider.copyWith(models: configuredModels);
    setState(() {
      _providers.removeWhere((item) => item.id == configuredProvider.id);
      _providers.add(configuredProvider);
      _selectedProviderId = configuredProvider.id;
      _selectedModelId = configuredProvider.model;
      _page = AppPage.chat;
    });
    _showNotice(
      'Provider profile saved for this session.',
    );
    unawaited(_refreshProviderModels(configuredProvider.id));
  }

  Future<void> _refreshProviderModels(String providerId) async {
    ProviderProfile? provider;
    for (final item in _providers) {
      if (item.id == providerId) provider = item;
    }
    if (provider == null) return;
    setState(() {
      _refreshingProviderIds.add(providerId);
      _modelDiscoveryErrors.remove(providerId);
    });
    try {
      final discovered = await _chatClient.discoverModels(provider: provider);
      if (!mounted) return;
      final index = _providers.indexWhere((item) => item.id == providerId);
      if (index < 0) return;
      final latestProvider = _providers[index];
      final discoveredById = {for (final model in discovered) model.id: model};
      final models = <ModelProfile>[
        discoveredById[latestProvider.model] ??
            ModelProfile(id: latestProvider.model),
        for (final model in discovered)
          if (model.id != latestProvider.model) model,
      ];
      setState(() {
        _providers[index] = latestProvider.copyWith(models: models);
        if (_selectedProviderId == providerId &&
            !_providers[index]
                .availableModels
                .any((model) => model.id == _selectedModelId)) {
          _selectedModelId = latestProvider.model;
        }
      });
    } on ChatConnectionException catch (error) {
      if (mounted) {
        setState(() => _modelDiscoveryErrors[providerId] = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _modelDiscoveryErrors[providerId] =
            'Could not read the provider model list.');
      }
    } finally {
      if (mounted) setState(() => _refreshingProviderIds.remove(providerId));
    }
  }

  Future<void> _openModelPicker() async {
    final selected = await showDialog<ModelReference>(
      context: context,
      builder: (context) => ModelPickerDialog(
        providers: List.unmodifiable(_providers),
        selectedProviderId: _selectedProviderId,
        selectedModelId: _selectedModelId,
        onConfigureModels: _openModelSetup,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedProviderId = selected.providerId;
      _selectedModelId = selected.modelId;
    });
  }

  void _selectPage(AppPage page) {
    setState(() => _page = page);
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _openModelSetup() {
    setState(() {
      _settingsTab = SettingsTab.models;
      _page = AppPage.settings;
    });
  }

  Future<List<ChatAttachment>> _pickProjectAttachments(
    List<ChatAttachment> alreadyAttached,
  ) async {
    final project = _activeProject;
    if (project == null) return const [];
    try {
      if (widget.attachmentPicker != null) {
        return await widget.attachmentPicker!(project, alreadyAttached);
      }
      final files = await openFiles(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Source and text files',
            extensions: ProjectAttachmentLoader.supportedExtensions,
          ),
        ],
        initialDirectory: project.path,
        confirmButtonText: 'Attach files',
      );
      if (files.isEmpty) return const [];
      return await _attachmentLoader.readFiles(
        projectPath: project.path,
        selectedPaths: files.map((file) => file.path).toList(growable: false),
        alreadyAttached: alreadyAttached,
      );
    } on ProjectAttachmentException catch (error) {
      _showNotice(error.message);
      return const [];
    } catch (_) {
      _showNotice('Could not attach those files. Try selecting them again.');
      return const [];
    }
  }

  bool _submitPrompt(String value, List<ChatAttachment> attachments) {
    if (value.trim().isEmpty && attachments.isEmpty) return false;
    final project = _activeProject;
    if (project == null) {
      _showNotice('Choose a project before starting a chat.');
      return false;
    }
    final provider = _selectedProvider;
    if (provider == null) {
      _showNotice('Choose or add a provider before sending a message.');
      return false;
    }
    try {
      _chatClient.validateProvider(provider);
    } on ChatConnectionException catch (error) {
      _showNotice(error.message);
      return false;
    }
    if (_activeChatId != null && _generationStops.containsKey(_activeChatId)) {
      _showNotice(
          'Wait for the current response to stop before sending again.');
      return false;
    }
    if ((_activeChat?.planMode ?? _draftPlanMode) && !_canUsePlanMode) {
      _showNotice(
        'Plan first needs a tool-capable model and computer access. Update those settings or turn Plan first off.',
      );
      return false;
    }
    if (_activeChatId == null) _startChat(project);
    final reasoningEffort = _selectedReasoningEffortId;
    final chatId = _activeChatId!;
    final planMode = _activeChat?.planMode ?? _draftPlanMode;
    final existingMessages = _messagesByChatId[chatId] ?? const <ChatMessage>[];
    final userMessage = ChatMessage(
      id: _newMessageId(),
      role: ChatMessageRole.user,
      content: value,
      status: ChatMessageStatus.complete,
      attachments: List.unmodifiable(attachments),
    );
    final assistantMessage = ChatMessage(
      id: _newMessageId(),
      role: ChatMessageRole.assistant,
      content: '',
      status: ChatMessageStatus.streaming,
    );
    final history = [
      ...existingMessages.where(_isProviderHistoryMessage),
      userMessage,
    ];
    final stop = Completer<void>();
    setState(() {
      _messagesByChatId[chatId] = [
        ...existingMessages,
        userMessage,
        assistantMessage,
      ];
      _generationStops[chatId] = stop;
      final chatIndex = _chats.indexWhere((chat) => chat.id == chatId);
      if (chatIndex >= 0 && _chats[chatIndex].title == 'New chat') {
        final title = value.isNotEmpty
            ? (value.length <= 36 ? value : '${value.substring(0, 33)}…')
            : 'Files: ${attachments.first.relativePath}';
        _chats[chatIndex] = _chats[chatIndex].copyWith(
          title: title,
        );
      }
    });
    unawaited(
      _streamAssistant(
        chatId: chatId,
        assistantMessageId: assistantMessage.id,
        provider: provider,
        history: history,
        projectPath: project.path,
        permissionMode: _permissionMode,
        planMode: planMode,
        reasoningEffort: reasoningEffort,
        enableProjectTools: _permissionMode != AgentPermissionMode.chatOnly &&
            _selectedModelProfile?.supportsTools != false,
        stop: stop,
      ),
    );
    return true;
  }

  String _newMessageId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_messageId++}';

  Future<void> _streamAssistant({
    required String chatId,
    required String assistantMessageId,
    required ProviderProfile provider,
    required List<ChatMessage> history,
    required String projectPath,
    required AgentPermissionMode permissionMode,
    required bool planMode,
    required bool enableProjectTools,
    required String? reasoningEffort,
    required Completer<void> stop,
  }) async {
    var activeAssistantMessageId = assistantMessageId;
    var completedToolCalls = 0;
    var isPlanMode = planMode;
    final fullAccess = permissionMode == AgentPermissionMode.fullAccess;
    final projectToolExecutor = ProjectToolExecutor();
    final toolCallLoopGuard = ToolCallLoopGuard();
    try {
      for (var toolRound = 0; toolRound < 6; toolRound++) {
        if (stop.isCompleted) return;
        final toolCalls = <AgentToolCall>[];
        var rejectedToolCall = false;
        await for (final event in _chatClient.streamEvents(
          provider: provider,
          history: history,
          abortTrigger: stop.future,
          enableProjectTools: enableProjectTools,
          fullAccess: fullAccess,
          allowComputerPaths:
              permissionMode != AgentPermissionMode.chatOnly && !isPlanMode,
          planMode: isPlanMode,
          reasoningEffort: reasoningEffort,
        )) {
          if (!mounted) return;
          switch (event) {
            case ChatTextEvent(:final text):
              _updateChatMessage(
                chatId,
                activeAssistantMessageId,
                (message) => message.copyWith(
                  content: message.content + text,
                  status: ChatMessageStatus.streaming,
                ),
              );
            case ChatToolCallEvent(:final toolCall):
              if (enableProjectTools) {
                toolCalls.add(toolCall);
              } else if (!rejectedToolCall) {
                rejectedToolCall = true;
                _updateChatMessage(
                  chatId,
                  activeAssistantMessageId,
                  (message) => message.copyWith(
                    content: message.content.isEmpty
                        ? 'The selected model or permission mode does not allow project tools.'
                        : '${message.content}\n\nThe selected model or permission mode does not allow project tools.',
                    status: ChatMessageStatus.streaming,
                  ),
                );
              }
          }
        }
        if (!mounted || stop.isCompleted) return;
        if (toolCalls.isEmpty) {
          _updateChatMessage(
            chatId,
            activeAssistantMessageId,
            (message) => message.copyWith(
              status: ChatMessageStatus.complete,
            ),
          );
          return;
        }

        final currentAssistant = _messagesByChatId[chatId]!
            .firstWhere((message) => message.id == activeAssistantMessageId);
        final assistantToolMessage = currentAssistant.copyWith(
          content: currentAssistant.content.isEmpty
              ? 'Checking files.'
              : currentAssistant.content,
          status: ChatMessageStatus.complete,
          toolCalls: List.unmodifiable(toolCalls),
        );
        _updateChatMessage(
          chatId,
          activeAssistantMessageId,
          (_) => assistantToolMessage,
        );
        history.add(assistantToolMessage);

        for (final toolCall in toolCalls) {
          if (stop.isCompleted) return;
          completedToolCalls++;
          final loopDecision = toolCallLoopGuard.inspect(toolCall);
          final isPlanSubmission = toolCall.name == 'submit_plan';
          final proposedPlan = toolCall.arguments['plan'];
          final validPlan = proposedPlan is String &&
              proposedPlan.trim().isNotEmpty &&
              proposedPlan.length <= 32768 &&
              RegExp(r'^#{1,6}\s+\S').hasMatch(proposedPlan.trimLeft());
          final reviewCanStart = isPlanSubmission &&
              isPlanMode &&
              toolCall.hasValidArguments &&
              validPlan &&
              !loopDecision.blocked &&
              completedToolCalls <= 8;
          final action = ChatMessage(
            id: _newMessageId(),
            role: ChatMessageRole.tool,
            content: '',
            status: reviewCanStart
                ? ChatMessageStatus.awaitingApproval
                : !loopDecision.blocked &&
                        _requiresToolApproval(permissionMode, toolCall.name)
                    ? ChatMessageStatus.awaitingApproval
                    : ChatMessageStatus.complete,
            toolCallId: toolCall.id,
            toolName: toolCall.name,
            toolArguments: toolCall.arguments,
            toolActionStatus: reviewCanStart
                ? ToolActionStatus.awaitingPlanReview
                : loopDecision.blocked
                    ? ToolActionStatus.loopBlocked
                    : _requiresToolApproval(permissionMode, toolCall.name) &&
                            toolCall.hasValidArguments &&
                            projectToolExecutor.supports(
                              toolCall.name,
                              fullAccess: fullAccess,
                            )
                        ? ToolActionStatus.awaitingApproval
                        : ToolActionStatus.running,
          );
          _appendChatMessage(chatId, action);

          if (isPlanSubmission) {
            final withinToolLimit = completedToolCalls <= 8;
            if (loopDecision.blocked) {
              const result =
                  'Repeated plan submission stopped before review after four identical attempts in this response.';
              _updateToolAction(
                toolCall.id,
                content: result,
                actionStatus: ToolActionStatus.loopBlocked,
              );
              history.add(action.copyWith(
                content: result,
                status: ChatMessageStatus.complete,
                toolActionStatus: ToolActionStatus.loopBlocked,
              ));
              continue;
            }
            if (!isPlanMode) {
              const result =
                  'Plan review is only available when Plan first is enabled. No computer action was run.';
              _updateToolAction(
                toolCall.id,
                content: result,
                actionStatus: ToolActionStatus.failed,
              );
              history.add(action.copyWith(
                content: result,
                status: ChatMessageStatus.complete,
                toolActionStatus: ToolActionStatus.failed,
              ));
              continue;
            }
            if (!toolCall.hasValidArguments || !validPlan) {
              const result =
                  'The plan must be valid Markdown with a heading. No project action was run.';
              _updateToolAction(
                toolCall.id,
                content: result,
                actionStatus: ToolActionStatus.failed,
              );
              history.add(action.copyWith(
                content: result,
                status: ChatMessageStatus.complete,
                toolActionStatus: ToolActionStatus.failed,
              ));
              continue;
            }
            if (!withinToolLimit) {
              const result =
                  'The agent action limit for this response was reached. The plan was not reviewed.';
              _updateToolAction(
                toolCall.id,
                content: result,
                actionStatus: ToolActionStatus.failed,
              );
              history.add(action.copyWith(
                content: result,
                status: ChatMessageStatus.complete,
                toolActionStatus: ToolActionStatus.failed,
              ));
              continue;
            }

            final review = Completer<PlanReviewResponse>();
            _pendingPlanReviews[toolCall.id] = review;
            final response = await Future.any<PlanReviewResponse>([
              review.future,
              stop.future.then((_) => const PlanReviewResponse(
                    decision: PlanReviewDecision.cancel,
                  )),
            ]);
            _pendingPlanReviews.remove(toolCall.id);
            if (stop.isCompleted) {
              _updateToolAction(
                toolCall.id,
                content: 'Plan review was cancelled when generation stopped.',
                actionStatus: ToolActionStatus.cancelled,
              );
              return;
            }

            if (response.decision == PlanReviewDecision.approve) {
              isPlanMode = false;
              _setChatPlanMode(chatId, false);
              const result =
                  'The user approved the plan. Continue with implementation now, following the selected computer access permissions.';
              _updateToolAction(
                toolCall.id,
                content: result,
                actionStatus: ToolActionStatus.planApproved,
              );
              history.add(action.copyWith(
                content: result,
                status: ChatMessageStatus.complete,
                toolActionStatus: ToolActionStatus.planApproved,
              ));
            } else if (response.decision == PlanReviewDecision.requestChanges) {
              final feedback = response.feedback.trim().isEmpty
                  ? 'Revise the plan to better match the original request.'
                  : response.feedback.trim();
              final result =
                  'The user requested plan changes. Revise the plan and submit it for review again. User feedback: $feedback';
              _updateToolAction(
                toolCall.id,
                content: result,
                actionStatus: ToolActionStatus.planRevisionRequested,
              );
              history.add(action.copyWith(
                content: result,
                status: ChatMessageStatus.complete,
                toolActionStatus: ToolActionStatus.planRevisionRequested,
              ));
            } else {
              _setChatPlanMode(chatId, false);
              const result =
                  'The user cancelled the plan. No project changes were made.';
              _updateToolAction(
                toolCall.id,
                content: result,
                actionStatus: ToolActionStatus.cancelled,
              );
              return;
            }
            continue;
          }

          final blockedDuringPlanning = isPlanMode &&
              !const {
                'list_project_files',
                'search_project_files',
                'read_project_file',
              }.contains(toolCall.name);

          var approved = fullAccess ||
              (permissionMode == AgentPermissionMode.autoApproveProjectReads &&
                  toolCall.name != 'edit_project_file');
          final withinToolLimit = completedToolCalls <= 8;
          if (!isPlanSubmission &&
              !blockedDuringPlanning &&
              !loopDecision.blocked &&
              _requiresToolApproval(permissionMode, toolCall.name) &&
              toolCall.hasValidArguments &&
              projectToolExecutor.supports(
                toolCall.name,
                fullAccess: fullAccess,
              ) &&
              withinToolLimit) {
            final approval = Completer<bool>();
            _pendingToolApprovals[toolCall.id] = approval;
            approved = await Future.any<bool>([
              approval.future,
              stop.future.then((_) => false),
            ]);
            _pendingToolApprovals.remove(toolCall.id);
          }

          if (stop.isCompleted) {
            _updateToolAction(
              toolCall.id,
              content: 'Approval was cancelled when the response was stopped.',
              actionStatus: ToolActionStatus.cancelled,
            );
            return;
          }

          final String toolResult;
          final ToolActionStatus actionStatus;
          if (blockedDuringPlanning) {
            toolResult =
                'This action is unavailable while Plan first is active. Only listing, searching, and reading are allowed before the user approves a plan.';
            actionStatus = ToolActionStatus.denied;
          } else if (loopDecision.blocked) {
            toolResult =
                'Repeated tool call stopped before execution after four identical attempts in this response. Try a different action or send a new message to reset the limit.';
            actionStatus = ToolActionStatus.loopBlocked;
          } else if (!toolCall.hasValidArguments) {
            toolResult =
                'The tool arguments were invalid. No computer files were accessed.';
            actionStatus = ToolActionStatus.failed;
          } else if (!projectToolExecutor.supports(
            toolCall.name,
            fullAccess: fullAccess,
          )) {
            toolResult = 'The requested project tool is not available.';
            actionStatus = ToolActionStatus.failed;
          } else if (!withinToolLimit) {
            toolResult =
                'The agent action limit for this response was reached. No action was run.';
            actionStatus = ToolActionStatus.failed;
          } else if (!approved) {
            toolResult =
                'The user denied this computer access request. No files were accessed.';
            actionStatus = ToolActionStatus.denied;
          } else if (permissionMode == AgentPermissionMode.chatOnly) {
            toolResult =
                'Computer file access is disabled. No files were accessed.';
            actionStatus = ToolActionStatus.denied;
          } else {
            _updateToolAction(
              toolCall.id,
              content: '',
              actionStatus: ToolActionStatus.running,
            );
            toolResult = await projectToolExecutor.execute(
              projectPath: projectPath,
              call: toolCall,
              fullAccess: fullAccess && !isPlanMode,
              allowComputerPaths:
                  permissionMode != AgentPermissionMode.chatOnly && !isPlanMode,
              abortTrigger: stop.future,
            );
            actionStatus = toolResult.startsWith('Tool error:')
                ? ToolActionStatus.failed
                : toolResult.startsWith('Tool cancelled:')
                    ? ToolActionStatus.cancelled
                    : ToolActionStatus.completed;
          }
          if (!mounted) return;
          final completedAction = action.copyWith(
            content: toolResult,
            status: ChatMessageStatus.complete,
            toolActionStatus: actionStatus,
          );
          _updateChatMessage(chatId, action.id, (_) => completedAction);
          history.add(completedAction);
        }

        if (toolRound == 5) {
          _appendChatMessage(
            chatId,
            ChatMessage(
              id: _newMessageId(),
              role: ChatMessageRole.assistant,
              content:
                  'The agent action limit for this response was reached. Send a follow-up message to continue.',
              status: ChatMessageStatus.complete,
            ),
          );
          return;
        }

        final nextAssistant = ChatMessage(
          id: _newMessageId(),
          role: ChatMessageRole.assistant,
          content: '',
          status: ChatMessageStatus.streaming,
        );
        activeAssistantMessageId = nextAssistant.id;
        _appendChatMessage(chatId, nextAssistant);
      }
    } on ChatConnectionException catch (error) {
      if (!mounted || stop.isCompleted) return;
      _updateChatMessage(
        chatId,
        activeAssistantMessageId,
        (message) => message.copyWith(
          status: ChatMessageStatus.failed,
          error: error.message,
        ),
      );
    } catch (_) {
      if (!mounted || stop.isCompleted) return;
      _updateChatMessage(
        chatId,
        activeAssistantMessageId,
        (message) => message.copyWith(
          status: ChatMessageStatus.failed,
          error:
              'The response could not be read. Check the provider and try again.',
        ),
      );
    } finally {
      if (identical(_generationStops[chatId], stop)) {
        _generationStops.remove(chatId);
        _pendingToolApprovals
            .removeWhere((_, approval) => approval.isCompleted);
        if (mounted) setState(() {});
      }
    }
  }

  void _updateChatMessage(
    String chatId,
    String messageId,
    ChatMessage Function(ChatMessage) update,
  ) {
    final messages = _messagesByChatId[chatId];
    if (messages == null) return;
    final index = messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    setState(() => messages[index] = update(messages[index]));
  }

  void _stopGeneration(String chatId) {
    final stop = _generationStops[chatId];
    if (stop == null) return;
    final messages = _messagesByChatId[chatId];
    for (final message in messages ?? const <ChatMessage>[]) {
      if (message.role != ChatMessageRole.tool ||
          (message.toolActionStatus != ToolActionStatus.awaitingApproval &&
              message.toolActionStatus !=
                  ToolActionStatus.awaitingPlanReview) ||
          message.toolCallId == null) {
        continue;
      }
      if (message.toolActionStatus == ToolActionStatus.awaitingPlanReview) {
        _resolvePlanReview(
          message.toolCallId!,
          const PlanReviewResponse(decision: PlanReviewDecision.cancel),
        );
      } else {
        _resolveToolApproval(message.toolCallId!, false);
      }
      _updateToolAction(
        message.toolCallId!,
        content: 'Approval was cancelled when the response was stopped.',
        actionStatus: ToolActionStatus.cancelled,
      );
    }
    if (!stop.isCompleted) stop.complete();
    if (messages == null) return;
    final activeIndex = messages.lastIndexWhere(
      (message) =>
          message.role == ChatMessageRole.assistant &&
          message.status == ChatMessageStatus.streaming,
    );
    if (activeIndex < 0) return;
    final message = messages[activeIndex];
    _updateChatMessage(
      chatId,
      message.id,
      (current) => ChatMessage(
        id: current.id,
        role: current.role,
        content: current.content,
        status: ChatMessageStatus.stopped,
      ),
    );
  }

  void _retryAssistant(String chatId, String assistantMessageId) {
    final provider = _selectedProvider;
    if (provider == null) {
      _showNotice('Choose or add a provider before retrying.');
      return;
    }
    try {
      _chatClient.validateProvider(provider);
    } on ChatConnectionException catch (error) {
      _showNotice(error.message);
      return;
    }
    if (_generationStops.containsKey(chatId)) {
      _showNotice('Wait for the current response to stop before retrying.');
      return;
    }
    final messages = _messagesByChatId[chatId];
    if (messages == null) return;
    ChatConversation? conversation;
    for (final chat in _chats) {
      if (chat.id == chatId) {
        conversation = chat;
        break;
      }
    }
    Project? project;
    for (final item in _projects) {
      if (item.id == conversation?.projectId) {
        project = item;
        break;
      }
    }
    if (project == null) {
      _showNotice('The project for this chat is no longer available.');
      return;
    }
    final assistantIndex = messages.indexWhere(
      (message) => message.id == assistantMessageId,
    );
    if (assistantIndex < 1) return;
    final previousMessages = messages.take(assistantIndex).toList();
    final history = previousMessages.where(_isProviderHistoryMessage).toList();
    final reasoningEffort = _selectedReasoningEffortId;
    final stop = Completer<void>();
    setState(() {
      messages[assistantIndex] = ChatMessage(
        id: assistantMessageId,
        role: ChatMessageRole.assistant,
        content: '',
        status: ChatMessageStatus.streaming,
      );
      _generationStops[chatId] = stop;
    });
    unawaited(
      _streamAssistant(
        chatId: chatId,
        assistantMessageId: assistantMessageId,
        provider: provider,
        history: history,
        projectPath: project.path,
        permissionMode: _permissionMode,
        planMode: conversation?.planMode ?? false,
        reasoningEffort: reasoningEffort,
        enableProjectTools: _permissionMode != AgentPermissionMode.chatOnly &&
            _selectedModelProfile?.supportsTools != false,
        stop: stop,
      ),
    );
  }

  void _addAgentTask(String prompt) {
    setState(() {
      _agentTasks.insert(
        0,
        AgentTask(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          prompt: prompt,
        ),
      );
    });
    _showNotice(
      'Task added to the preview. Agent execution will be integrated later.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _createChat,
        const SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _toggleSidebar,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _searchChats,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _createChat,
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
            _toggleSidebar,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _searchChats,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: _scaffoldKey,
          drawer: Drawer(width: 268, child: _buildSidebar()),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showSidebar = _sidebarOpen && constraints.maxWidth >= 840;
                return Row(
                  children: [
                    if (showSidebar)
                      AnimatedContainer(
                        key: const Key('sidebar.panel'),
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: 268,
                        child: _buildSidebar(),
                      ),
                    if (showSidebar)
                      const VerticalDivider(width: 1, thickness: 1),
                    Expanded(
                      child: Column(
                        children: [
                          _TopBar(
                            page: _page,
                            sidebarOpen: showSidebar,
                            activeProject: _activeProject,
                            selectedProvider: _selectedProvider,
                            selectedModel: _selectedModelProfile,
                            selectedReasoningEffortId:
                                _selectedReasoningEffortId,
                            onToggleSidebar: _toggleSidebar,
                            onSelectWorkspace: _chooseProject,
                            onChooseModel: _openModelPicker,
                            onSelectReasoningEffort: _selectReasoningEffort,
                            onOpenAgents: () => _selectPage(AppPage.agents),
                            onOpenChanges: () => _selectPage(AppPage.changes),
                          ),
                          Expanded(
                            child: switch (_page) {
                              AppPage.chat => ChatScreen(
                                  key: const Key('page.chat'),
                                  title: _activeChat?.title,
                                  chatId: _activeChatId,
                                  project: _activeProject,
                                  hasModel: _selectedProvider != null,
                                  messages: _activeChatId == null
                                      ? const []
                                      : _messagesByChatId[_activeChatId] ??
                                          const [],
                                  isGenerating: _activeChatId != null &&
                                      _generationStops
                                          .containsKey(_activeChatId),
                                  providerLabel: _selectedProvider?.routeLabel,
                                  permissionMode: _permissionMode,
                                  planMode:
                                      _activeChat?.planMode ?? _draftPlanMode,
                                  canUsePlanMode: _canUsePlanMode,
                                  onPlanModeChanged: (enabled) {
                                    if (enabled && !_canUsePlanMode) {
                                      _showNotice(
                                        'Choose a tool-capable model and enable computer access to use Plan first.',
                                      );
                                      return;
                                    }
                                    _setPlanMode(enabled);
                                  },
                                  onSend: _submitPrompt,
                                  onPickAttachments: _pickProjectAttachments,
                                  onStop: () => _stopGeneration(_activeChatId!),
                                  onRetry: (messageId) => _retryAssistant(
                                    _activeChatId!,
                                    messageId,
                                  ),
                                  onChooseProject: _chooseProject,
                                  onCreateProject: _createProjectFromFolder,
                                  onNewChat: _createChat,
                                  onConfigureModels: _openModelSetup,
                                  onOpenAgents: () =>
                                      _selectPage(AppPage.agents),
                                  onOpenChanges: () =>
                                      _selectPage(AppPage.changes),
                                  onPermissionModeChanged:
                                      _changePermissionMode,
                                  onApproveTool: (toolCallId) =>
                                      _resolveToolApproval(toolCallId, true),
                                  onDenyTool: (toolCallId) =>
                                      _resolveToolApproval(toolCallId, false),
                                  onApprovePlan: _approvePlan,
                                  onKeepPlanning: _keepPlanning,
                                  onCancelPlan: _cancelPlan,
                                ),
                              AppPage.agents => AgentsScreen(
                                  key: const Key('page.agents'),
                                  tasks: _agentTasks,
                                  onAddTask: _addAgentTask,
                                ),
                              AppPage.changes => ChangesScreen(
                                  key: const Key('page.changes'),
                                  changes: _projectChanges,
                                ),
                              AppPage.settings => SettingsScreen(
                                  key: const Key('page.settings'),
                                  selectedTab: _settingsTab,
                                  providers: _providers,
                                  refreshingProviderIds: _refreshingProviderIds,
                                  modelDiscoveryErrors: _modelDiscoveryErrors,
                                  onSelectTab: (tab) =>
                                      setState(() => _settingsTab = tab),
                                  onAddProvider: _addProvider,
                                  onRefreshModels: (provider) =>
                                      _refreshProviderModels(provider.id),
                                  onDeleteProvider: (provider) => setState(() {
                                    _providers.remove(provider);
                                    _refreshingProviderIds.remove(provider.id);
                                    _modelDiscoveryErrors.remove(provider.id);
                                    if (_selectedProviderId == provider.id) {
                                      _selectedProviderId = null;
                                      _selectedModelId = null;
                                    }
                                  }),
                                  onNotice: _showNotice,
                                  workspacePath: _activeProject?.path,
                                  onSelectWorkspace: _createProjectFromFolder,
                                  permissionMode: _permissionMode,
                                  onPermissionModeChanged:
                                      _changePermissionMode,
                                ),
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatSearchDialog extends StatefulWidget {
  const _ChatSearchDialog({required this.chats});

  final List<ChatConversation> chats;

  @override
  State<_ChatSearchDialog> createState() => _ChatSearchDialogState();
}

class _ChatSearchDialogState extends State<_ChatSearchDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final matches = widget.chats
        .where(
            (chat) => chat.title.toLowerCase().contains(_query.toLowerCase()))
        .toList(growable: false);
    return AlertDialog(
      icon: const Icon(AppIcons.searchRounded, color: AppColors.blue),
      title: const Text('Search conversations'),
      content: SizedBox(
        width: 460,
        height: 330,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              key: const Key('chat.search.input'),
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: const InputDecoration(
                hintText: 'Search by conversation name',
                prefixIcon: Icon(AppIcons.searchRounded),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: matches.isEmpty
                  ? const Center(
                      child: Text(
                        'No matching conversations',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final chat = matches[index];
                        return ListTile(
                          leading: const Icon(
                            AppIcons.chatBubbleOutlineRounded,
                          ),
                          title: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, chat.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _RenameChatDialog extends StatefulWidget {
  const _RenameChatDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameChatDialog> createState() => _RenameChatDialogState();
}

class _RenameChatDialogState extends State<_RenameChatDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename conversation'),
      content: TextField(
        key: const Key('chat.rename.input'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _ProjectPickerDialog extends StatefulWidget {
  const _ProjectPickerDialog({
    required this.projects,
    required this.selectedProjectId,
    required this.onCreateProject,
  });

  final List<Project> projects;
  final String? selectedProjectId;
  final Future<Project?> Function() onCreateProject;

  @override
  State<_ProjectPickerDialog> createState() => _ProjectPickerDialogState();
}

class _ProjectPickerDialogState extends State<_ProjectPickerDialog> {
  bool _creating = false;

  Future<void> _createProject() async {
    setState(() => _creating = true);
    final project = await widget.onCreateProject();
    if (!mounted) return;
    setState(() => _creating = false);
    if (project != null) Navigator.pop(context, project);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(AppIcons.folderOpenRounded, color: AppColors.blue),
      title: const Text('Choose a project', key: Key('project.picker.title')),
      content: SizedBox(
        width: 500,
        height: 340,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Each chat stays linked to its project folder.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 13),
            Expanded(
              child: widget.projects.isEmpty
                  ? const Center(
                      child: Text(
                        'No projects added yet.',
                        key: Key('project.empty'),
                        style: TextStyle(color: AppColors.muted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: widget.projects.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 5),
                      itemBuilder: (context, index) {
                        final project = widget.projects[index];
                        final selected = project.id == widget.selectedProjectId;
                        return Material(
                          color: selected ? AppColors.ice : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            key: Key('project.select.${project.id}'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.pop(context, project),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    AppIcons.folderOpenRounded,
                                    size: 19,
                                    color: AppColors.blueDeep,
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          project.name,
                                          style: const TextStyle(
                                            color: AppColors.ink,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          project.path,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(
                                      AppIcons.checkRounded,
                                      size: 17,
                                      color: AppColors.blueDeep,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('project.create'),
              onPressed: _creating ? null : _createProject,
              icon: const Icon(AppIcons.folderPlus, size: 17),
              label:
                  Text(_creating ? 'Opening folder picker…' : 'Create project'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.projects,
    required this.activeProjectId,
    required this.onCreateProject,
    required this.onSelectProject,
    required this.chats,
    required this.activeChatId,
    required this.page,
    required this.onNewChat,
    required this.onSelectChat,
    required this.onRenameChat,
    required this.onDeleteChat,
    required this.onSelectPage,
  });

  final List<Project> projects;
  final String? activeProjectId;
  final Future<Project?> Function() onCreateProject;
  final ValueChanged<Project> onSelectProject;
  final List<ChatConversation> chats;
  final String? activeChatId;
  final AppPage page;
  final VoidCallback onNewChat;
  final ValueChanged<String> onSelectChat;
  final ValueChanged<String> onRenameChat;
  final ValueChanged<String> onDeleteChat;
  final ValueChanged<AppPage> onSelectPage;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FCFF),
      padding: const EdgeInsets.fromLTRB(16, 17, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const PenguinMark(size: 34),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Penguin Code',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.iceStrong,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Text(
                  'Preview',
                  style: TextStyle(
                    color: AppColors.blueDeep,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            key: const Key('sidebar.new-chat'),
            onPressed: onNewChat,
            icon: const Icon(AppIcons.addRounded, size: 19),
            label: const Text('New chat'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              backgroundColor: AppColors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.only(left: 9, bottom: 7),
            child: Text(
              'Workspace',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
          ),
          _SideItem(
            icon: AppIcons.chatBubbleOutlineRounded,
            label: 'Chat',
            selected: page == AppPage.chat,
            onTap: () => onSelectPage(AppPage.chat),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: 9),
                        child: Text(
                          'Projects',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('sidebar.project.create'),
                      tooltip: 'Create project',
                      visualDensity: VisualDensity.compact,
                      onPressed: () async => onCreateProject(),
                      icon: const Icon(AppIcons.folderPlus, size: 17),
                    ),
                  ],
                ),
                if (projects.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(10, 7, 8, 9),
                    child: Text(
                      'Choose a folder to add a project.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  )
                else
                  ...projects.map(
                    (project) => _ProjectHistoryTile(
                      project: project,
                      selected: activeProjectId == project.id,
                      onTap: () => onSelectProject(project),
                    ),
                  ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: 9),
                        child: Text(
                          'Recent chats',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'New chat',
                      visualDensity: VisualDensity.compact,
                      onPressed: onNewChat,
                      icon: const Icon(AppIcons.addRounded, size: 18),
                    ),
                  ],
                ),
                if (chats.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(10, 7, 8, 8),
                    child: Text(
                      'New chats will appear here.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  )
                else
                  ...chats.map((chat) {
                    String? projectName;
                    for (final project in projects) {
                      if (project.id == chat.projectId) {
                        projectName = project.name;
                        break;
                      }
                    }
                    return _ChatHistoryTile(
                      chat: chat,
                      projectName: projectName ?? 'Project unavailable',
                      selected: activeChatId == chat.id,
                      onTap: () => onSelectChat(chat.id),
                      onRename: () => onRenameChat(chat.id),
                      onDelete: () => onDeleteChat(chat.id),
                    );
                  }),
              ],
            ),
          ),
          const Divider(height: 22),
          _SideItem(
            key: const Key('sidebar.settings'),
            icon: AppIcons.settingsOutlined,
            label: 'Settings',
            selected: page == AppPage.settings,
            onTap: () => onSelectPage(AppPage.settings),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 29,
                height: 29,
                decoration: const BoxDecoration(
                  color: AppColors.iceStrong,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  AppIcons.personOutlineRounded,
                  size: 17,
                  color: AppColors.blueDeep,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Account',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                AppIcons.moreHorizRounded,
                color: AppColors.muted,
                size: 18,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectHistoryTile extends StatelessWidget {
  const _ProjectHistoryTile({
    required this.project,
    required this.selected,
    required this.onTap,
  });

  final Project project;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: project.path,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: selected ? AppColors.iceStrong : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            key: Key('sidebar.project.${project.id}'),
            borderRadius: BorderRadius.circular(9),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    AppIcons.folderOpenRounded,
                    size: 16,
                    color: selected ? AppColors.blueDeep : AppColors.muted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppColors.blueDeep : AppColors.ink,
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? AppColors.iceStrong : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? AppColors.blueDeep : AppColors.muted,
                ),
                const SizedBox(width: 11),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppColors.blueDeep : AppColors.ink,
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatHistoryTile extends StatelessWidget {
  const _ChatHistoryTile({
    required this.chat,
    required this.projectName,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final ChatConversation chat;
  final String projectName;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? AppColors.ice : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(
              left: 10,
              top: 5,
              bottom: 5,
              right: 3,
            ),
            child: Row(
              children: [
                const Icon(
                  AppIcons.chatBubbleOutlineRounded,
                  size: 15,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        projectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Options for ${chat.title}',
                  padding: EdgeInsets.zero,
                  iconSize: 17,
                  onSelected: (value) =>
                      value == 'rename' ? onRename() : onDelete(),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                  icon: const Icon(
                    AppIcons.moreHorizRounded,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.page,
    required this.sidebarOpen,
    required this.activeProject,
    required this.selectedProvider,
    required this.selectedModel,
    required this.selectedReasoningEffortId,
    required this.onToggleSidebar,
    required this.onSelectWorkspace,
    required this.onChooseModel,
    required this.onSelectReasoningEffort,
    required this.onOpenAgents,
    required this.onOpenChanges,
  });

  final AppPage page;
  final bool sidebarOpen;
  final Project? activeProject;
  final ProviderProfile? selectedProvider;
  final ModelProfile? selectedModel;
  final String? selectedReasoningEffortId;
  final VoidCallback onToggleSidebar;
  final VoidCallback onSelectWorkspace;
  final VoidCallback onChooseModel;
  final ValueChanged<String?> onSelectReasoningEffort;
  final VoidCallback onOpenAgents;
  final VoidCallback onOpenChanges;

  String get _pageName => switch (page) {
        AppPage.chat => 'Chat',
        AppPage.agents => 'Subagents',
        AppPage.changes => 'Changes',
        AppPage.settings => 'Settings',
      };

  @override
  Widget build(BuildContext context) {
    final projectLabel = activeProject?.name ?? 'Choose project';
    final projectTooltip = activeProject?.path ?? 'Choose a project folder';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 840;
        return Container(
          height: 64,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 17),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              IconButton(
                key: const Key('sidebar.toggle'),
                tooltip: sidebarOpen ? 'Hide sidebar' : 'Show sidebar',
                onPressed: onToggleSidebar,
                icon: Icon(
                  sidebarOpen ? AppIcons.menuOpenRounded : AppIcons.menuRounded,
                ),
              ),
              SizedBox(width: compact ? 4 : 8),
              Text(_pageName, style: Theme.of(context).textTheme.titleLarge),
              if (compact) ...[
                const SizedBox(width: 6),
                IconButton(
                  key: const Key('workspace.select'),
                  tooltip: projectTooltip,
                  onPressed: onSelectWorkspace,
                  icon: const Icon(AppIcons.folderOpenRounded, size: 18),
                ),
              ] else ...[
                const SizedBox(width: 15),
                Container(width: 1, height: 24, color: AppColors.line),
                const SizedBox(width: 12),
                TextButton.icon(
                  key: const Key('workspace.select'),
                  onPressed: onSelectWorkspace,
                  icon: const Icon(AppIcons.folderOpenRounded, size: 17),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 210),
                    child: Text(projectLabel, overflow: TextOverflow.ellipsis),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.muted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (!compact)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.ice,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        AppIcons.removeRedEyeOutlined,
                        size: 13,
                        color: AppColors.blueDeep,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Design preview',
                        style: TextStyle(
                          color: AppColors.blueDeep,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!compact) const SizedBox(width: 9),
              TextButton(
                key: const Key('model.selector'),
                onPressed: onChooseModel,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.ink,
                ),
                child: Container(
                  height: 38,
                  constraints: BoxConstraints(maxWidth: compact ? 160 : 220),
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        AppIcons.autoAwesomeOutlined,
                        size: 16,
                        color: AppColors.blue,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          selectedProvider?.routeLabel ?? 'Choose model',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        AppIcons.keyboardArrowDownRounded,
                        size: 18,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
              if (selectedModel?.reasoningEfforts.isNotEmpty == true)
                PopupMenuButton<String>(
                  key: const Key('model.effort.selector'),
                  tooltip:
                      'Reasoning effort: ${selectedReasoningEffortId == null ? 'Provider default' : _formatReasoningEffort(selectedReasoningEffortId!)}',
                  onSelected: (value) => onSelectReasoningEffort(
                    value == 'default'
                        ? null
                        : value.substring('effort:'.length),
                  ),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      key: const Key('model.effort.option.default'),
                      value: 'default',
                      child: _ReasoningEffortOption(
                        label: 'Provider default',
                        selected: selectedReasoningEffortId == null,
                      ),
                    ),
                    for (final effort in selectedModel!.reasoningEfforts.keys)
                      PopupMenuItem(
                        key: Key('model.effort.option.${effort.toLowerCase()}'),
                        value: 'effort:$effort',
                        child: _ReasoningEffortOption(
                          label: _formatReasoningEffort(effort),
                          selected: selectedReasoningEffortId == effort,
                        ),
                      ),
                  ],
                  child: compact
                      ? const SizedBox(
                          width: 38,
                          height: 38,
                          child: Icon(AppIcons.modelReasoning, size: 19),
                        )
                      : Container(
                          height: 38,
                          constraints: const BoxConstraints(maxWidth: 190),
                          margin: const EdgeInsets.only(left: 7),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: AppColors.canvas,
                            border: Border.all(color: AppColors.line),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(AppIcons.modelReasoning,
                                  size: 15, color: AppColors.blue),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  selectedReasoningEffortId == null
                                      ? 'Provider default'
                                      : _formatReasoningEffort(
                                          selectedReasoningEffortId!,
                                        ),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(
                                AppIcons.keyboardArrowDownRounded,
                                size: 17,
                                color: AppColors.muted,
                              ),
                            ],
                          ),
                        ),
                ),
              if (compact)
                PopupMenuButton<String>(
                  key: const Key('topbar.tools'),
                  tooltip: 'Project tools',
                  onSelected: (value) =>
                      value == 'agents' ? onOpenAgents() : onOpenChanges(),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'agents',
                      child: Row(
                        children: [
                          Icon(AppIcons.hubOutlined, size: 18),
                          SizedBox(width: 9),
                          Text('Subagents'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'changes',
                      child: Row(
                        children: [
                          Icon(AppIcons.differenceOutlined, size: 18),
                          SizedBox(width: 9),
                          Text('Review changes'),
                        ],
                      ),
                    ),
                  ],
                  icon: const Icon(AppIcons.moreHorizRounded),
                )
              else ...[
                const SizedBox(width: 4),
                IconButton(
                  key: const Key('topbar.agents'),
                  tooltip: 'Subagents',
                  onPressed: onOpenAgents,
                  icon: const Icon(AppIcons.hubOutlined, size: 19),
                ),
                IconButton(
                  key: const Key('topbar.changes'),
                  tooltip: 'Review changes',
                  onPressed: onOpenChanges,
                  icon: const Icon(AppIcons.differenceOutlined, size: 19),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReasoningEffortOption extends StatelessWidget {
  const _ReasoningEffortOption({
    required this.label,
    required this.selected,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 20,
            child:
                selected ? const Icon(AppIcons.checkRounded, size: 16) : null,
          ),
          Text(label),
        ],
      );
}

String _formatReasoningEffort(String id) => switch (id.toLowerCase()) {
      'off' => 'Off',
      'minimal' => 'Minimal',
      'low' => 'Low',
      'medium' => 'Medium',
      'high' => 'High',
      'xhigh' => 'Extra high',
      'max' => 'Max',
      _ => id
          .split(RegExp(r'[-_ ]+'))
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' '),
    };

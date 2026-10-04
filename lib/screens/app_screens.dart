import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/project_attachment_loader.dart';
import '../widgets/app_icons.dart';
import '../widgets/project_access_menu.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.title,
    required this.chatId,
    required this.project,
    required this.hasModel,
    required this.messages,
    required this.isGenerating,
    required this.providerLabel,
    required this.permissionMode,
    required this.onSend,
    required this.onPickAttachments,
    required this.onStop,
    required this.onRetry,
    required this.onChooseProject,
    required this.onCreateProject,
    required this.onNewChat,
    required this.onConfigureModels,
    required this.onOpenAgents,
    required this.onOpenChanges,
    required this.onPermissionModeChanged,
    required this.onApproveTool,
    required this.onDenyTool,
  });

  final String? title;
  final String? chatId;
  final Project? project;
  final bool hasModel;
  final List<ChatMessage> messages;
  final bool isGenerating;
  final String? providerLabel;
  final AgentPermissionMode permissionMode;
  final bool Function(String, List<ChatAttachment>) onSend;
  final Future<List<ChatAttachment>> Function(
    List<ChatAttachment> alreadyAttached,
  ) onPickAttachments;
  final VoidCallback onStop;
  final ValueChanged<String> onRetry;
  final VoidCallback onChooseProject;
  final Future<Project?> Function() onCreateProject;
  final VoidCallback onNewChat;
  final VoidCallback onConfigureModels;
  final VoidCallback onOpenAgents;
  final VoidCallback onOpenChanges;
  final ValueChanged<AgentPermissionMode> onPermissionModeChanged;
  final ValueChanged<String> onApproveTool;
  final ValueChanged<String> onDenyTool;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _pendingAttachments = <ChatAttachment>[];
  bool _isPickingAttachments = false;

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId ||
        oldWidget.project?.id != widget.project?.id) {
      _pendingAttachments.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty && _pendingAttachments.isEmpty) return;
    if (widget.onSend(prompt, List.unmodifiable(_pendingAttachments))) {
      _controller.clear();
      setState(_pendingAttachments.clear);
    }
  }

  Future<void> _pickAttachments() async {
    if (widget.project == null || _isPickingAttachments) return;
    if (_pendingAttachments.length >= ProjectAttachmentLoader.maxAttachments) {
      _showNotice(context, 'A message can include up to 4 files.');
      return;
    }
    final projectId = widget.project!.id;
    final chatId = widget.chatId;
    setState(() => _isPickingAttachments = true);
    try {
      final files = await widget.onPickAttachments(
        List.unmodifiable(_pendingAttachments),
      );
      if (!mounted ||
          files.isEmpty ||
          widget.project?.id != projectId ||
          widget.chatId != chatId) {
        return;
      }
      setState(() => _pendingAttachments.addAll(files));
    } finally {
      if (mounted) setState(() => _isPickingAttachments = false);
    }
  }

  void _removeAttachment(String relativePath) {
    setState(() {
      _pendingAttachments.removeWhere(
        (attachment) => attachment.relativePath == relativePath,
      );
    });
  }

  void _useSuggestion(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/penguin-chat-wallpaper.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.42),
                      Colors.white.withValues(alpha: 0.25),
                      AppColors.canvas.withValues(alpha: 0.73),
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                ),
              ),
              if (widget.title == null)
                _EmptyChatWelcome(
                  project: widget.project,
                  hasModel: widget.hasModel,
                  onUseSuggestion: _useSuggestion,
                  onChooseProject: widget.onChooseProject,
                  onCreateProject: widget.onCreateProject,
                  onNewChat: widget.onNewChat,
                  onConfigureModels: widget.onConfigureModels,
                )
              else if (widget.messages.isNotEmpty)
                _MessageTimeline(
                  messages: widget.messages,
                  onRetry: widget.onRetry,
                  onApproveTool: widget.onApproveTool,
                  onDenyTool: widget.onDenyTool,
                )
              else
                _ConversationPlaceholder(
                  title: widget.title!,
                  project: widget.project!,
                  hasModel: widget.hasModel,
                  onOpenAgents: widget.onOpenAgents,
                  onOpenChanges: widget.onOpenChanges,
                ),
            ],
          ),
        ),
        _Composer(
          controller: _controller,
          focusNode: _focusNode,
          onSend: _send,
          onStop: widget.onStop,
          enabled: widget.project != null,
          isGenerating: widget.isGenerating,
          providerLabel: widget.providerLabel,
          permissionMode: widget.permissionMode,
          onPermissionModeChanged: widget.onPermissionModeChanged,
          attachments: _pendingAttachments,
          isPickingAttachments: _isPickingAttachments,
          onAddAttachments: _pickAttachments,
          onRemoveAttachment: _removeAttachment,
        ),
      ],
    );
  }
}

class _EmptyChatWelcome extends StatelessWidget {
  const _EmptyChatWelcome({
    required this.project,
    required this.hasModel,
    required this.onUseSuggestion,
    required this.onChooseProject,
    required this.onCreateProject,
    required this.onNewChat,
    required this.onConfigureModels,
  });

  final Project? project;
  final bool hasModel;
  final ValueChanged<String> onUseSuggestion;
  final VoidCallback onChooseProject;
  final Future<Project?> Function() onCreateProject;
  final VoidCallback onNewChat;
  final VoidCallback onConfigureModels;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final left = constraints.maxWidth < 650 ? 25.0 : 72.0;
        return Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(left, 34, 30, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 590),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.87),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          AppIcons.folderOpenRounded,
                          size: 15,
                          color: AppColors.blue,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          project?.name ?? 'No project selected',
                          style: const TextStyle(
                            color: AppColors.blueDeep,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    project == null
                        ? 'Choose a project to get started'
                        : 'What are we building today?',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    project == null
                        ? 'Select a folder on this computer to use as the working directory for your chats.'
                        : 'New chats will use ${project!.name} as their working directory.',
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 15,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 25),
                  if (project == null)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          key: const Key('home.project.choose'),
                          onPressed: onChooseProject,
                          icon:
                              const Icon(AppIcons.folderOpenRounded, size: 17),
                          label: const Text('Choose a project'),
                        ),
                        OutlinedButton.icon(
                          key: const Key('home.project.create'),
                          onPressed: () async => onCreateProject(),
                          icon: const Icon(AppIcons.folderPlus, size: 17),
                          label: const Text('Create project'),
                        ),
                      ],
                    )
                  else ...[
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        _SuggestionChip(
                          icon: AppIcons.autoAwesomeOutlined,
                          label: 'Plan a feature',
                          onTap: () => onUseSuggestion(
                            'Help me plan a feature for this project: ',
                          ),
                        ),
                        _SuggestionChip(
                          icon: AppIcons.bugReportOutlined,
                          label: 'Understand an error',
                          onTap: () => onUseSuggestion(
                            'Help me reason through this error: ',
                          ),
                        ),
                        _SuggestionChip(
                          icon: AppIcons.rateReviewOutlined,
                          label: 'Review a code snippet',
                          onTap: () => onUseSuggestion(
                            'Review this code snippet and point out possible issues: ',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          key: const Key('home.new-chat'),
                          onPressed: onNewChat,
                          icon: const Icon(AppIcons.addRounded, size: 17),
                          label: const Text('Start a new chat'),
                        ),
                        if (!hasModel)
                          TextButton.icon(
                            key: const Key('chat.configure-models'),
                            onPressed: onConfigureModels,
                            icon: const Icon(AppIcons.addLinkRounded, size: 17),
                            label: const Text('Set up a provider and model'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.blueDeep,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 8,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Project access follows your selected permission for reads. File edits always need your approval. The agent cannot run commands.',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.blueDeep),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(color: AppColors.ink, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationPlaceholder extends StatelessWidget {
  const _ConversationPlaceholder({
    required this.title,
    required this.project,
    required this.hasModel,
    required this.onOpenAgents,
    required this.onOpenChanges,
  });

  final String title;
  final Project project;
  final bool hasModel;
  final VoidCallback onOpenAgents;
  final VoidCallback onOpenChanges;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140E4167),
              blurRadius: 28,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  AppIcons.chatBubbleOutlineRounded,
                  size: 17,
                  color: AppColors.blue,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Text(
                  'No messages',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              project.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            const SizedBox(height: 16),
            Text(
              hasModel
                  ? 'Start the conversation.'
                  : 'Connect a model to get started.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Project access follows your selected permission for reads. File edits always need your approval. The agent cannot run commands.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenAgents,
                  icon: const Icon(AppIcons.hubOutlined, size: 16),
                  label: const Text('Subagents'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenChanges,
                  icon: const Icon(AppIcons.differenceOutlined, size: 16),
                  label: const Text('Changes'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onStop,
    required this.enabled,
    required this.isGenerating,
    required this.providerLabel,
    required this.permissionMode,
    required this.onPermissionModeChanged,
    required this.attachments,
    required this.isPickingAttachments,
    required this.onAddAttachments,
    required this.onRemoveAttachment,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final bool enabled;
  final bool isGenerating;
  final String? providerLabel;
  final AgentPermissionMode permissionMode;
  final ValueChanged<AgentPermissionMode> onPermissionModeChanged;
  final List<ChatAttachment> attachments;
  final bool isPickingAttachments;
  final VoidCallback onAddAttachments;
  final ValueChanged<String> onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
      decoration: BoxDecoration(
        color: AppColors.canvas.withValues(alpha: 0.9),
        border: const Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(13, 6, 10, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: AppColors.line),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0C174465),
                      blurRadius: 18,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    if (attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final attachment in attachments)
                              InputChip(
                                key: Key(
                                  'composer.attachment.${attachment.relativePath}',
                                ),
                                avatar: const Icon(
                                  AppIcons.fileCodeOutlined,
                                  size: 15,
                                ),
                                label: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 245),
                                  child: Text(
                                    attachment.relativePath,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                onDeleted: () => onRemoveAttachment(
                                  attachment.relativePath,
                                ),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: AppColors.ice,
                              ),
                          ],
                        ),
                      ),
                    TextField(
                      key: const Key('composer.input'),
                      enabled: enabled,
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => onSend(),
                      decoration: InputDecoration(
                        hintText: enabled
                            ? 'Message Penguin Code…'
                            : 'Choose a project to start a chat…',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 10,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          key: const Key('composer.attach'),
                          tooltip: 'Attach project files',
                          onPressed: enabled && !isPickingAttachments
                              ? onAddAttachments
                              : null,
                          visualDensity: VisualDensity.compact,
                          icon: isPickingAttachments
                              ? const SizedBox.square(
                                  dimension: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  AppIcons.attachFileRounded,
                                  size: 19,
                                  color: AppColors.muted,
                                ),
                        ),
                        const SizedBox(width: 2),
                        ProjectAccessMenu(
                          value: permissionMode,
                          onChanged: onPermissionModeChanged,
                          compact: true,
                          enabled: enabled && !isGenerating,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            enabled && attachments.isNotEmpty
                                ? '${attachments.length} file${attachments.length == 1 ? '' : 's'} attached · ${permissionMode.compactLabel}.'
                                : enabled
                                    ? 'Project access: ${permissionMode.compactLabel}.'
                                    : 'Select a project folder to begin.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (!isGenerating)
                          const Text(
                            'Enter to send',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 10,
                            ),
                          ),
                        const SizedBox(width: 9),
                        Tooltip(
                          message:
                              isGenerating ? 'Stop generating' : 'Send message',
                          child: FilledButton(
                            key: Key(
                              isGenerating ? 'composer.stop' : 'composer.send',
                            ),
                            onPressed: !enabled
                                ? null
                                : isGenerating
                                    ? onStop
                                    : onSend,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(38, 36),
                              padding: EdgeInsets.zero,
                              backgroundColor: AppColors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                            child: Icon(
                              isGenerating
                                  ? AppIcons.stopRounded
                                  : AppIcons.arrowUpwardRounded,
                              size: 19,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                providerLabel == null
                    ? 'Choose a provider · selected files are included as context.'
                    : 'Connected to $providerLabel · selected file context is sent with your message.',
                style: const TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageTimeline extends StatefulWidget {
  const _MessageTimeline({
    required this.messages,
    required this.onRetry,
    required this.onApproveTool,
    required this.onDenyTool,
  });

  final List<ChatMessage> messages;
  final ValueChanged<String> onRetry;
  final ValueChanged<String> onApproveTool;
  final ValueChanged<String> onDenyTool;

  @override
  State<_MessageTimeline> createState() => _MessageTimelineState();
}

class _MessageTimelineState extends State<_MessageTimeline> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _MessageTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView.separated(
          key: const Key('chat.messages'),
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 32),
          itemCount: widget.messages.length,
          separatorBuilder: (context, index) => const SizedBox(height: 18),
          itemBuilder: (context, index) {
            final message = widget.messages[index];
            if (message.role == ChatMessageRole.tool) {
              return _ToolActionCard(
                message: message,
                onApprove: widget.onApproveTool,
                onDeny: widget.onDenyTool,
              );
            }
            final user = message.role == ChatMessageRole.user;
            return Align(
              alignment: user ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment:
                      user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.only(bottom: 6, left: 3, right: 3),
                      child: Text(
                        user ? 'You' : 'Penguin Code',
                        style: const TextStyle(
                          color: AppColors.blueDeep,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: user
                            ? AppColors.blue.withValues(alpha: 0.96)
                            : Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(17),
                        border: user ? null : Border.all(color: AppColors.line),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0C174465),
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.attachments.isNotEmpty) ...[
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final attachment in message.attachments)
                                  Chip(
                                    key: Key(
                                      'chat.attachment.${message.id}.${attachment.relativePath}',
                                    ),
                                    avatar: Icon(
                                      AppIcons.fileCodeOutlined,
                                      size: 14,
                                      color: user
                                          ? Colors.white
                                          : AppColors.blueDeep,
                                    ),
                                    label: Text(
                                      attachment.relativePath,
                                      style: TextStyle(
                                        color:
                                            user ? Colors.white : AppColors.ink,
                                        fontSize: 10,
                                      ),
                                    ),
                                    backgroundColor: user
                                        ? AppColors.blueDeep
                                        : AppColors.ice,
                                    side: BorderSide.none,
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            if (message.content.isNotEmpty)
                              const SizedBox(height: 7),
                          ],
                          if (message.content.isNotEmpty ||
                              (message.status == ChatMessageStatus.streaming &&
                                  message.attachments.isEmpty))
                            SelectableText(
                              message.content.isEmpty
                                  ? 'Thinking…'
                                  : message.content,
                              key: Key('chat.message.${message.id}'),
                              style: TextStyle(
                                color: user ? Colors.white : AppColors.ink,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!user && message.status == ChatMessageStatus.stopped)
                      const _MessageStatus(label: 'Response stopped')
                    else if (!user &&
                        message.status == ChatMessageStatus.failed)
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            Text(
                              message.error ?? 'The response failed.',
                              style: const TextStyle(
                                color: AppColors.danger,
                                fontSize: 11,
                              ),
                            ),
                            TextButton.icon(
                              key: Key('chat.retry.${message.id}'),
                              onPressed: () => widget.onRetry(message.id),
                              icon:
                                  const Icon(AppIcons.refreshRounded, size: 15),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ToolActionCard extends StatelessWidget {
  const _ToolActionCard({
    required this.message,
    required this.onApprove,
    required this.onDeny,
  });

  final ChatMessage message;
  final ValueChanged<String> onApprove;
  final ValueChanged<String> onDeny;

  @override
  Widget build(BuildContext context) {
    final callId = message.toolCallId;
    final name = switch (message.toolName) {
      'list_project_files' => 'List project files',
      'search_project_files' => 'Search project files',
      'read_project_file' => 'Read a project file',
      'edit_project_file' => 'Edit a project file',
      _ => 'Project file action',
    };
    final isEdit = message.toolName == 'edit_project_file';
    final target = message.toolArguments['file_path'] ??
        message.toolArguments['path'] ??
        message.toolArguments['query'] ??
        '.';
    final actionStatus = message.toolActionStatus;
    final icon = switch (message.toolName) {
      'list_project_files' => AppIcons.folderOpenRounded,
      'search_project_files' => AppIcons.searchRounded,
      _ => AppIcons.fileCodeOutlined,
    };
    final statusLabel = switch (actionStatus) {
      ToolActionStatus.awaitingApproval => 'Approval needed',
      ToolActionStatus.running => 'Working',
      ToolActionStatus.completed => 'Completed',
      ToolActionStatus.denied => 'Denied',
      ToolActionStatus.failed => 'Could not run',
      ToolActionStatus.cancelled => 'Cancelled',
      null => 'Project action',
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          key: Key('chat.tool.${message.id}'),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.ice,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 17, color: AppColors.blueDeep),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          SelectableText(
                            '$target',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (actionStatus == ToolActionStatus.running)
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: actionStatus == ToolActionStatus.denied
                              ? AppColors.muted
                              : AppColors.blueDeep,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                if (actionStatus == ToolActionStatus.awaitingApproval) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      isEdit
                          ? 'Review the proposed replacement. It applies only if the file was read and has not changed since then.'
                          : 'Penguin Code will only read files inside the selected project.',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (isEdit) ...[
                    _ProjectTextDiff(
                      oldText: message.toolArguments['old_string'] is String
                          ? message.toolArguments['old_string'] as String
                          : '',
                      newText: message.toolArguments['new_string'] is String
                          ? message.toolArguments['new_string'] as String
                          : '',
                    ),
                  ],
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        key: Key('chat.tool.approve.$callId'),
                        onPressed:
                            callId == null ? null : () => onApprove(callId),
                        icon: const Icon(AppIcons.checkRounded, size: 15),
                        label: const Text('Approve once'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      TextButton(
                        key: Key('chat.tool.deny.$callId'),
                        onPressed: callId == null ? null : () => onDeny(callId),
                        child: const Text('Deny'),
                      ),
                    ],
                  ),
                ] else ...[
                  if (isEdit)
                    _ProjectTextDiff(
                      oldText: message.toolArguments['old_string'] is String
                          ? message.toolArguments['old_string'] as String
                          : '',
                      newText: message.toolArguments['new_string'] is String
                          ? message.toolArguments['new_string'] as String
                          : '',
                    ),
                  if (message.content.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SelectableText(
                      message.content,
                      key: Key('chat.tool.result.${message.id}'),
                      maxLines: 10,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectTextDiff extends StatelessWidget {
  const _ProjectTextDiff({required this.oldText, required this.newText});

  final String oldText;
  final String newText;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('chat.tool.edit.diff'),
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: AppColors.canvas,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DiffTextBlock(label: 'Before', text: oldText, added: false),
            const Divider(height: 1),
            _DiffTextBlock(label: 'After', text: newText, added: true),
          ],
        ),
      );
}

class _DiffTextBlock extends StatelessWidget {
  const _DiffTextBlock({
    required this.label,
    required this.text,
    required this.added,
  });

  final String label;
  final String text;
  final bool added;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: added ? AppColors.blueDeep : AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 112),
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: SelectableText(
                    text.isEmpty ? 'Empty replacement' : text,
                    style: TextStyle(
                      color: added ? AppColors.ink : AppColors.muted,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _MessageStatus extends StatelessWidget {
  const _MessageStatus({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7, left: 3),
      child: Text(
        label,
        style: const TextStyle(color: AppColors.muted, fontSize: 10),
      ),
    );
  }
}

class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key, required this.tasks, required this.onAddTask});

  final List<AgentTask> tasks;
  final ValueChanged<String> onAddTask;

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  Future<void> _createTask() async {
    final prompt = await showDialog<String>(
      context: context,
      builder: (context) => const _DelegateTaskDialog(),
    );
    if (prompt == null || prompt.isEmpty || !mounted) return;
    widget.onAddTask(prompt);
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _PageHeading(
                  eyebrow: 'Parallel work',
                  title: 'Subagents',
                  description:
                      'Delegate focused tasks and review their progress and results here.',
                ),
              ),
              FilledButton.icon(
                key: const Key('agents.create'),
                onPressed: _createTask,
                icon: const Icon(AppIcons.addRounded, size: 18),
                label: const Text('Delegate task'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (widget.tasks.isEmpty)
            _EmptyPanel(
              icon: AppIcons.hubOutlined,
              title: 'No delegated tasks yet',
              description:
                  'Task status, activity, and summaries will appear here.',
              actionLabel: 'Prepare a task',
              onAction: _createTask,
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: widget.tasks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final task = widget.tasks[index];
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.ice,
                        child: Icon(
                          AppIcons.smartToyOutlined,
                          color: AppColors.blueDeep,
                        ),
                      ),
                      title: Text(
                        task.prompt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Waiting for agent integration'),
                      ),
                      trailing: const Icon(
                        AppIcons.hourglassEmptyRounded,
                        color: AppColors.amber,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DelegateTaskDialog extends StatefulWidget {
  const _DelegateTaskDialog();

  @override
  State<_DelegateTaskDialog> createState() => _DelegateTaskDialogState();
}

class _DelegateTaskDialogState extends State<_DelegateTaskDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(AppIcons.hubOutlined, color: AppColors.blue),
      title: const Text('Delegate a task'),
      content: SizedBox(
        width: 460,
        child: TextField(
          key: const Key('agents.task.input'),
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Describe a focused task for a subagent…',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('agents.task.create'),
          onPressed: _submit,
          child: const Text('Add task'),
        ),
      ],
    );
  }
}

class ChangesScreen extends StatelessWidget {
  const ChangesScreen({super.key, required this.changes});

  final List<ProjectFileChange> changes;

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageHeading(
            eyebrow: 'Project review',
            title: 'Changes',
            description: 'Review file edits applied by the agent this session.',
          ),
          const SizedBox(height: 24),
          if (changes.isEmpty)
            const _EmptyPanel(
              icon: AppIcons.differenceOutlined,
              title: 'No file edits yet',
              description: 'Approved project edits will appear here.',
            )
          else
            Expanded(
              child: ListView.separated(
                key: const Key('changes.list'),
                itemCount: changes.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) => _ProjectChangeCard(
                  key: ValueKey('changes.item.$index'),
                  change: changes[index],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProjectChangeCard extends StatelessWidget {
  const _ProjectChangeCard({super.key, required this.change});

  final ProjectFileChange change;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    AppIcons.fileCodeOutlined,
                    size: 18,
                    color: AppColors.blueDeep,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      change.relativePath,
                      key: Key('changes.item.path.${change.relativePath}'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${change.projectName} · ${change.chatTitle}',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                ),
              ),
              _ProjectTextDiff(
                oldText: change.oldText,
                newText: change.newText,
              ),
            ],
          ),
        ),
      );
}

void _showNotice(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

class _PageScaffold extends StatelessWidget {
  const _PageScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.canvas,
      padding: const EdgeInsets.fromLTRB(36, 30, 36, 32),
      child: child,
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  final String eyebrow;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: AppColors.blueDeep,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 7),
        Text(
          description,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  color: AppColors.iceStrong,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.blueDeep, size: 24),
              ),
              const SizedBox(height: 15),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 7),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(AppIcons.addRounded, size: 17),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

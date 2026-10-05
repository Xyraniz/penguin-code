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
    required this.canUseComputer,
    required this.workingDirectoryPath,
    required this.outputDirectoryPath,
    required this.hasModel,
    required this.messages,
    required this.isGenerating,
    required this.providerLabel,
    required this.permissionMode,
    required this.planMode,
    required this.canUsePlanMode,
    required this.material3SkillInstalled,
    required this.material3SkillActive,
    required this.onMaterial3SkillChanged,
    required this.onPlanModeChanged,
    required this.onSend,
    required this.onPickAttachments,
    required this.onStop,
    required this.onRetry,
    required this.onChooseProject,
    required this.onConfigureModels,
    required this.onOpenAgents,
    required this.onOpenChanges,
    required this.onPermissionModeChanged,
    required this.onApproveTool,
    required this.onDenyTool,
    required this.onApprovePlan,
    required this.onKeepPlanning,
    required this.onCancelPlan,
    required this.onOpenDirectory,
  });

  final String? title;
  final String? chatId;
  final Project? project;
  final bool canUseComputer;
  final String? workingDirectoryPath;
  final String? outputDirectoryPath;
  final bool hasModel;
  final List<ChatMessage> messages;
  final bool isGenerating;
  final String? providerLabel;
  final AgentPermissionMode permissionMode;
  final bool planMode;
  final bool canUsePlanMode;
  final bool material3SkillInstalled;
  final bool material3SkillActive;
  final ValueChanged<bool> onMaterial3SkillChanged;
  final ValueChanged<bool> onPlanModeChanged;
  final bool Function(String, List<ChatAttachment>) onSend;
  final Future<List<ChatAttachment>> Function(
    List<ChatAttachment> alreadyAttached,
  ) onPickAttachments;
  final VoidCallback onStop;
  final ValueChanged<String> onRetry;
  final VoidCallback onChooseProject;
  final VoidCallback onConfigureModels;
  final VoidCallback onOpenAgents;
  final VoidCallback onOpenChanges;
  final ValueChanged<AgentPermissionMode> onPermissionModeChanged;
  final ValueChanged<String> onApproveTool;
  final ValueChanged<String> onDenyTool;
  final ValueChanged<String> onApprovePlan;
  final void Function(String, String) onKeepPlanning;
  final ValueChanged<String> onCancelPlan;
  final ValueChanged<String> onOpenDirectory;

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
    if (_isPickingAttachments) return;
    if (_pendingAttachments.length >= ProjectAttachmentLoader.maxAttachments) {
      _showNotice(context, 'A message can include up to 4 files.');
      return;
    }
    final projectId = widget.project?.id;
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

  Future<void> _requestPlanChanges(String toolCallId) async {
    final feedback = await showDialog<String>(
      context: context,
      builder: (context) => const _PlanFeedbackDialog(),
    );
    if (feedback != null) {
      widget.onKeepPlanning(toolCallId, feedback.trim());
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
                  permissionMode: widget.permissionMode,
                  onUseSuggestion: _useSuggestion,
                  onChooseProject: widget.onChooseProject,
                  onConfigureModels: widget.onConfigureModels,
                )
              else if (widget.messages.isNotEmpty)
                _MessageTimeline(
                  messages: widget.messages,
                  onRetry: widget.onRetry,
                  onApproveTool: widget.onApproveTool,
                  onDenyTool: widget.onDenyTool,
                  onApprovePlan: widget.onApprovePlan,
                  onKeepPlanning: _requestPlanChanges,
                  onCancelPlan: widget.onCancelPlan,
                )
              else
                _ConversationPlaceholder(
                  title: widget.title!,
                  project: widget.project,
                  hasModel: widget.hasModel,
                  permissionMode: widget.permissionMode,
                  onOpenAgents: widget.onOpenAgents,
                  onOpenChanges: widget.onOpenChanges,
                ),
            ],
          ),
        ),
        if (widget.chatId != null &&
            widget.workingDirectoryPath != null &&
            widget.outputDirectoryPath != null)
          _ChatDirectoriesBar(
            workingDirectoryPath: widget.workingDirectoryPath!,
            outputDirectoryPath: widget.outputDirectoryPath!,
            onOpenDirectory: widget.onOpenDirectory,
          ),
        _Composer(
          controller: _controller,
          focusNode: _focusNode,
          onSend: _send,
          onStop: widget.onStop,
          enabled: true,
          hasProject: widget.project != null,
          canUseComputer: widget.canUseComputer,
          onChooseProject: widget.onChooseProject,
          isGenerating: widget.isGenerating,
          providerLabel: widget.providerLabel,
          permissionMode: widget.permissionMode,
          onPermissionModeChanged: widget.onPermissionModeChanged,
          planMode: widget.planMode,
          canUsePlanMode: widget.canUsePlanMode,
          material3SkillInstalled: widget.material3SkillInstalled,
          material3SkillActive: widget.material3SkillActive,
          onMaterial3SkillChanged: widget.onMaterial3SkillChanged,
          onPlanModeChanged: widget.onPlanModeChanged,
          attachments: _pendingAttachments,
          isPickingAttachments: _isPickingAttachments,
          onAddAttachments: _pickAttachments,
          onRemoveAttachment: _removeAttachment,
        ),
      ],
    );
  }
}

class _ChatDirectoriesBar extends StatelessWidget {
  const _ChatDirectoriesBar({
    required this.workingDirectoryPath,
    required this.outputDirectoryPath,
    required this.onOpenDirectory,
  });

  final String workingDirectoryPath;
  final String outputDirectoryPath;
  final ValueChanged<String> onOpenDirectory;

  String _folderName(String path) =>
      path.split(RegExp(r'[\\/]')).where((segment) => segment.isNotEmpty).last;

  @override
  Widget build(BuildContext context) {
    Widget folderButton(String label, String path, IconData icon) => Tooltip(
          message: path,
          child: TextButton.icon(
            onPressed: () => onOpenDirectory(path),
            icon: Icon(icon, size: 15),
            label: Text(
              '$label · ${_folderName(path)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              textStyle: const TextStyle(fontSize: 11),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 3, 20, 1),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Row(
            children: [
              const Icon(AppIcons.folderOpenRounded,
                  size: 14, color: AppColors.muted),
              const SizedBox(width: 4),
              folderButton('Workspace', workingDirectoryPath,
                  AppIcons.folderOpenRounded),
              const SizedBox(width: 4),
              folderButton(
                  'Outputs', outputDirectoryPath, AppIcons.fileCodeOutlined),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanFeedbackDialog extends StatefulWidget {
  const _PlanFeedbackDialog();

  @override
  State<_PlanFeedbackDialog> createState() => _PlanFeedbackDialogState();
}

class _PlanFeedbackDialogState extends State<_PlanFeedbackDialog> {
  final _feedbackController = TextEditingController();

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('What should change?'),
        content: SizedBox(
          width: 420,
          child: TextField(
            key: const Key('chat.plan.feedback'),
            controller: _feedbackController,
            autofocus: true,
            minLines: 3,
            maxLines: 7,
            maxLength: 4000,
            decoration: const InputDecoration(
              hintText: 'Describe what the plan should account for.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('chat.plan.feedback.submit'),
            onPressed: () => Navigator.pop(context, _feedbackController.text),
            child: const Text('Keep planning'),
          ),
        ],
      );
}

class _EmptyChatWelcome extends StatelessWidget {
  const _EmptyChatWelcome({
    required this.project,
    required this.hasModel,
    required this.permissionMode,
    required this.onUseSuggestion,
    required this.onChooseProject,
    required this.onConfigureModels,
  });

  final Project? project;
  final bool hasModel;
  final AgentPermissionMode permissionMode;
  final ValueChanged<String> onUseSuggestion;
  final VoidCallback onChooseProject;
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
                          AppIcons.chatBubbleOutlineRounded,
                          size: 15,
                          color: AppColors.blue,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          project?.name ?? 'General chat',
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
                        ? 'What would you like to talk about?'
                        : 'What are we building today?',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    project == null
                        ? 'Start with a regular chat. Choose a project whenever you want Penguin Code to work with files.'
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
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          key: const Key('home.project.choose'),
                          onPressed: onChooseProject,
                          icon:
                              const Icon(AppIcons.folderOpenRounded, size: 17),
                          label: const Text('Choose a project'),
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
                    Text(
                      _accessDescription(permissionMode),
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
    required this.permissionMode,
    required this.onOpenAgents,
    required this.onOpenChanges,
  });

  final String title;
  final Project? project;
  final bool hasModel;
  final AgentPermissionMode permissionMode;
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
            if (project != null)
              Text(
                project!.path,
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
            Text(
              _accessDescription(permissionMode),
              style: const TextStyle(
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
    required this.hasProject,
    required this.canUseComputer,
    required this.onChooseProject,
    required this.isGenerating,
    required this.providerLabel,
    required this.permissionMode,
    required this.onPermissionModeChanged,
    required this.planMode,
    required this.canUsePlanMode,
    required this.material3SkillInstalled,
    required this.material3SkillActive,
    required this.onMaterial3SkillChanged,
    required this.onPlanModeChanged,
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
  final bool hasProject;
  final bool canUseComputer;
  final VoidCallback onChooseProject;
  final bool isGenerating;
  final String? providerLabel;
  final AgentPermissionMode permissionMode;
  final bool planMode;
  final bool canUsePlanMode;
  final bool material3SkillInstalled;
  final bool material3SkillActive;
  final ValueChanged<bool> onMaterial3SkillChanged;
  final ValueChanged<bool> onPlanModeChanged;
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
                    if (attachments.isNotEmpty || material3SkillInstalled)
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
                            if (material3SkillInstalled)
                              Tooltip(
                                message: material3SkillActive
                                    ? 'Material Design 3 is active for this chat.'
                                    : 'Add Material Design 3 guidance to this chat.',
                                child: FilterChip(
                                  key: const Key(
                                      'composer.skill.material3.toggle'),
                                  selected: material3SkillActive,
                                  showCheckmark: false,
                                  onSelected: isGenerating
                                      ? null
                                      : onMaterial3SkillChanged,
                                  avatar: Icon(
                                    AppIcons.component,
                                    size: 15,
                                    color: material3SkillActive
                                        ? AppColors.blueDeep
                                        : AppColors.muted,
                                  ),
                                  label: const Text('Material 3'),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 5),
                                  side: BorderSide(
                                    color: material3SkillActive
                                        ? AppColors.blue
                                        : AppColors.line,
                                  ),
                                  backgroundColor: Colors.white,
                                  selectedColor: AppColors.ice,
                                  labelStyle: TextStyle(
                                    color: material3SkillActive
                                        ? AppColors.blueDeep
                                        : AppColors.muted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
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
                      decoration: const InputDecoration(
                        hintText: 'Message Penguin Code…',
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
                          tooltip: 'Attach files',
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
                        if (canUseComputer)
                          ProjectAccessMenu(
                            value: permissionMode,
                            onChanged: onPermissionModeChanged,
                            compact: true,
                            enabled: enabled && !isGenerating,
                          ),
                        if (!hasProject)
                          IconButton(
                            key: const Key('composer.project.select'),
                            tooltip: 'Choose a project for file tools',
                            visualDensity: VisualDensity.compact,
                            onPressed: onChooseProject,
                            icon: const Icon(
                              AppIcons.folderOpenRounded,
                              size: 19,
                              color: AppColors.blueDeep,
                            ),
                          ),
                        const SizedBox(width: 5),
                        if (canUseComputer)
                          Tooltip(
                            message: canUsePlanMode || planMode
                                ? 'Plan first and review the plan before making changes.'
                                : 'Choose a tool-capable model and enable computer access to use Plan first.',
                            child: FilterChip(
                              key: const Key('composer.plan.toggle'),
                              selected: planMode,
                              showCheckmark: false,
                              onSelected:
                                  !isGenerating && (canUsePlanMode || planMode)
                                      ? onPlanModeChanged
                                      : null,
                              avatar: Icon(
                                AppIcons.modelReasoning,
                                size: 15,
                                color: planMode
                                    ? AppColors.blueDeep
                                    : AppColors.muted,
                              ),
                              label: const Text('Plan first'),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              side: BorderSide(
                                color:
                                    planMode ? AppColors.blue : AppColors.line,
                              ),
                              backgroundColor: Colors.white,
                              selectedColor: AppColors.ice,
                              labelStyle: TextStyle(
                                color: planMode
                                    ? AppColors.blueDeep
                                    : AppColors.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            planMode
                                ? 'Plan first is on · read-only until approval.'
                                : attachments.isNotEmpty && hasProject
                                    ? '${attachments.length} file${attachments.length == 1 ? '' : 's'} attached · ${_composerAccessLabel(permissionMode)}'
                                    : canUseComputer
                                        ? hasProject
                                            ? _composerAccessLabel(
                                                permissionMode)
                                            : 'Chat workspace · ${_composerAccessLabel(permissionMode)}'
                                        : 'Chat only · computer access is unavailable.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: planMode
                                  ? AppColors.blueDeep
                                  : !hasProject
                                      ? AppColors.muted
                                      : permissionMode ==
                                              AgentPermissionMode.fullAccess
                                          ? AppColors.amber
                                          : AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (!isGenerating)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Text(
                              'Enter to send',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 10,
                              ),
                            ),
                          ),
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

String _accessDescription(AgentPermissionMode mode) => switch (mode) {
      AgentPermissionMode.chatOnly =>
        'Computer file access is disabled. Choose another mode to let the agent work with files.',
      AgentPermissionMode.askBeforeEachAction =>
        'The agent can work with supported files anywhere on your computer. Every file action needs your approval. Commands require Full access.',
      AgentPermissionMode.autoApproveProjectReads =>
        'The agent can work with supported files anywhere on your computer. Listing, search, and reads run automatically; edits need your approval. Commands require Full access.',
      AgentPermissionMode.fullAccess =>
        'Full access is enabled. The connected model can read and edit files anywhere on your computer and run commands without asking first.',
    };

String _composerAccessLabel(AgentPermissionMode mode) =>
    mode == AgentPermissionMode.fullAccess
        ? 'Full access is on · files and commands run without approval.'
        : 'Computer access: ${mode.compactLabel}.';

class _MessageTimeline extends StatefulWidget {
  const _MessageTimeline({
    required this.messages,
    required this.onRetry,
    required this.onApproveTool,
    required this.onDenyTool,
    required this.onApprovePlan,
    required this.onKeepPlanning,
    required this.onCancelPlan,
  });

  final List<ChatMessage> messages;
  final ValueChanged<String> onRetry;
  final ValueChanged<String> onApproveTool;
  final ValueChanged<String> onDenyTool;
  final ValueChanged<String> onApprovePlan;
  final ValueChanged<String> onKeepPlanning;
  final ValueChanged<String> onCancelPlan;

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
                onApprovePlan: widget.onApprovePlan,
                onKeepPlanning: widget.onKeepPlanning,
                onCancelPlan: widget.onCancelPlan,
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
    required this.onApprovePlan,
    required this.onKeepPlanning,
    required this.onCancelPlan,
  });

  final ChatMessage message;
  final ValueChanged<String> onApprove;
  final ValueChanged<String> onDeny;
  final ValueChanged<String> onApprovePlan;
  final ValueChanged<String> onKeepPlanning;
  final ValueChanged<String> onCancelPlan;

  @override
  Widget build(BuildContext context) {
    final callId = message.toolCallId;
    if (message.toolName == 'submit_plan') {
      return _PlanReviewCard(
        message: message,
        onApprove: onApprovePlan,
        onKeepPlanning: onKeepPlanning,
        onCancel: onCancelPlan,
      );
    }
    final isMcpTool = message.toolName?.startsWith('mcp_tool_') ?? false;
    final mcpToolName = message.toolName?.replaceFirst(
      RegExp(r'^mcp_tool_\d+_'),
      '',
    );
    final name = isMcpTool
        ? 'MCP tool · ${mcpToolName ?? 'external'}'
        : switch (message.toolName) {
            'list_project_files' => 'List computer files',
            'search_project_files' => 'Search computer files',
            'read_project_file' => 'Read a file',
            'edit_project_file' => 'Edit a file',
            'run_command' => 'Run a command',
            _ => 'Computer file action',
          };
    final isEdit = message.toolName == 'edit_project_file';
    final target = message.toolArguments['command'] ??
        message.toolArguments['file_path'] ??
        message.toolArguments['path'] ??
        message.toolArguments['query'] ??
        '.';
    final actionStatus = message.toolActionStatus;
    final icon = switch (message.toolName) {
      'list_project_files' => AppIcons.folderOpenRounded,
      'search_project_files' => AppIcons.searchRounded,
      'run_command' => AppIcons.terminalRounded,
      _ when isMcpTool => AppIcons.hubOutlined,
      _ => AppIcons.fileCodeOutlined,
    };
    final statusLabel = switch (actionStatus) {
      ToolActionStatus.awaitingApproval => 'Approval needed',
      ToolActionStatus.awaitingPlanReview => 'Review needed',
      ToolActionStatus.running => message.toolName == 'run_command'
          ? 'Running command'
          : isMcpTool
              ? 'Running MCP tool'
              : 'Working',
      ToolActionStatus.completed => 'Completed',
      ToolActionStatus.planApproved => 'Plan approved',
      ToolActionStatus.planRevisionRequested => 'Plan revision requested',
      ToolActionStatus.denied => 'Denied',
      ToolActionStatus.failed => 'Could not run',
      ToolActionStatus.cancelled => 'Cancelled',
      ToolActionStatus.loopBlocked => 'Loop stopped',
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
                              fontFamily: 'monospace',
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
                      isMcpTool
                          ? 'This tool will run in the connected local MCP server. Review the request before every call.'
                          : isEdit
                              ? 'Review the proposed replacement. It applies only if the file was read and has not changed since then.'
                              : 'This request can access supported files anywhere on your computer. The selected access mode controls approval.',
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

class _PlanReviewCard extends StatelessWidget {
  const _PlanReviewCard({
    required this.message,
    required this.onApprove,
    required this.onKeepPlanning,
    required this.onCancel,
  });

  final ChatMessage message;
  final ValueChanged<String> onApprove;
  final ValueChanged<String> onKeepPlanning;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final callId = message.toolCallId;
    final status = message.toolActionStatus;
    final awaitingReview = status == ToolActionStatus.awaitingPlanReview;
    final plan = message.toolArguments['plan'];
    final statusLabel = switch (status) {
      ToolActionStatus.awaitingPlanReview => 'Review needed',
      ToolActionStatus.planApproved => 'Approved',
      ToolActionStatus.planRevisionRequested => 'Changes requested',
      ToolActionStatus.cancelled => 'Cancelled',
      ToolActionStatus.failed => 'Could not review',
      ToolActionStatus.loopBlocked => 'Loop stopped',
      _ => 'Plan review',
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          key: Key('chat.plan.review.${message.id}'),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.ice,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        AppIcons.rateReviewOutlined,
                        size: 18,
                        color: AppColors.blueDeep,
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Text(
                        'Implementation plan',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      statusLabel,
                      key: Key('chat.plan.status.${message.id}'),
                      style: TextStyle(
                        color: awaitingReview
                            ? AppColors.blueDeep
                            : AppColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (plan is String && plan.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          plan,
                          key: Key('chat.plan.content.${message.id}'),
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (awaitingReview) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Project changes and commands stay unavailable until you approve this plan.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilledButton.icon(
                        key: Key('chat.plan.approve.$callId'),
                        onPressed:
                            callId == null ? null : () => onApprove(callId),
                        icon: const Icon(AppIcons.checkRounded, size: 15),
                        label: const Text('Approve plan'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 35),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      OutlinedButton.icon(
                        key: Key('chat.plan.revise.$callId'),
                        onPressed: callId == null
                            ? null
                            : () => onKeepPlanning(callId),
                        icon: const Icon(AppIcons.editNoteRounded, size: 15),
                        label: const Text('Keep planning'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 35),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      TextButton(
                        key: Key('chat.plan.cancel.$callId'),
                        onPressed:
                            callId == null ? null : () => onCancel(callId),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ] else if (message.content.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  SelectableText(
                    message.content,
                    key: Key('chat.plan.result.${message.id}'),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
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

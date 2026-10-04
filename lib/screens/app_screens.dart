import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../widgets/app_icons.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.title,
    required this.project,
    required this.hasModel,
    required this.onSend,
    required this.onChooseProject,
    required this.onCreateProject,
    required this.onNewChat,
    required this.onConfigureModels,
    required this.onOpenAgents,
    required this.onOpenChanges,
  });

  final String? title;
  final Project? project;
  final bool hasModel;
  final ValueChanged<String> onSend;
  final VoidCallback onChooseProject;
  final Future<Project?> Function() onCreateProject;
  final VoidCallback onNewChat;
  final VoidCallback onConfigureModels;
  final VoidCallback onOpenAgents;
  final VoidCallback onOpenChanges;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final prompt = _controller.text.trim();
    if (prompt.isNotEmpty) widget.onSend(prompt);
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
          enabled: widget.project != null,
          onAttachment: () => _showNotice(
            context,
            'Attachments will be available when the agent is connected.',
          ),
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
                          icon: AppIcons.searchRounded,
                          label: 'Explore the project',
                          onTap: () => onUseSuggestion(
                            'Explore this project and explain its main parts.',
                          ),
                        ),
                        _SuggestionChip(
                          icon: AppIcons.bugReportOutlined,
                          label: 'Investigate an error',
                          onTap: () => onUseSuggestion(
                            'Help me investigate this error: ',
                          ),
                        ),
                        _SuggestionChip(
                          icon: AppIcons.rateReviewOutlined,
                          label: 'Review changes',
                          onTap: () => onUseSuggestion(
                            'Review the pending changes and point out possible issues.',
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
                      'Folder access and agent execution are not connected in this preview.',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
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
                  ? 'Agent execution is not connected in this preview.'
                  : 'Connect a model to get started.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'This chat is linked to its project folder. File access is not enabled yet.',
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
    required this.enabled,
    required this.onAttachment,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool enabled;
  final VoidCallback onAttachment;

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
                            ? 'Write a task for Penguin Code…'
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
                          tooltip: 'Attach a file',
                          onPressed: enabled ? onAttachment : null,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            AppIcons.attachFileRounded,
                            size: 19,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            enabled
                                ? 'Project folder attached · file access is not enabled yet.'
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
                        const Text(
                          'Enter to send',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 9),
                        FilledButton(
                          key: const Key('composer.send'),
                          onPressed: enabled ? onSend : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(38, 36),
                            padding: EdgeInsets.zero,
                            backgroundColor: AppColors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          child: const Icon(
                            AppIcons.arrowUpwardRounded,
                            size: 19,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Design preview · messages are not sent to a model',
                style: TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
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
  const ChangesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeading(
            eyebrow: 'Project review',
            title: 'Changes',
            description:
                'Review modified files before accepting the agent’s work.',
          ),
          SizedBox(height: 24),
          _EmptyPanel(
            icon: AppIcons.differenceOutlined,
            title: 'No pending changes',
            description:
                'File diffs and accept or discard actions will appear here.',
          ),
        ],
      ),
    );
  }
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

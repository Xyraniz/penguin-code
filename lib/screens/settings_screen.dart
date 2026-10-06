import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/mcp_stdio_client.dart';
import '../widgets/app_icons.dart';
import '../widgets/project_access_menu.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.selectedTab,
    required this.providers,
    required this.refreshingProviderIds,
    required this.modelDiscoveryErrors,
    required this.onSelectTab,
    required this.onAddProvider,
    required this.onRefreshModels,
    required this.onDeleteProvider,
    required this.onNotice,
    required this.workspacePath,
    required this.onSelectWorkspace,
    required this.responseDetail,
    required this.reasoningSummary,
    required this.subagentsEnabled,
    required this.onResponseDetailChanged,
    required this.onReasoningSummaryChanged,
    required this.onSubagentsEnabledChanged,
    required this.permissionMode,
    required this.onPermissionModeChanged,
    required this.userProfileText,
    required this.agentMemoryText,
    required this.memoriesEnabled,
    required this.pastChatSearchEnabled,
    required this.autoRememberPreferences,
    required this.autoSelectSkills,
    required this.skillLearningEnabled,
    required this.dataDirectoryPath,
    required this.isLocalDataReady,
    required this.onSaveUserProfile,
    required this.onSaveAgentMemory,
    required this.onMemoriesEnabledChanged,
    required this.onPastChatSearchEnabledChanged,
    required this.onAutoRememberChanged,
    required this.onAutoSelectSkillsChanged,
    required this.onSkillLearningChanged,
    required this.skillsDirectoryPath,
    required this.mcpServers,
    required this.mcpServerStatuses,
    required this.onAddMcpServer,
    required this.onUpdateMcpServer,
    required this.onToggleMcpServer,
    required this.onDeleteMcpServer,
    required this.onRefreshMcpServer,
  });

  final SettingsTab selectedTab;
  final List<ProviderProfile> providers;
  final Set<String> refreshingProviderIds;
  final Map<String, String> modelDiscoveryErrors;
  final ValueChanged<SettingsTab> onSelectTab;
  final ValueChanged<ProviderProfile> onAddProvider;
  final ValueChanged<ProviderProfile> onRefreshModels;
  final ValueChanged<ProviderProfile> onDeleteProvider;
  final ValueChanged<String> onNotice;
  final String? workspacePath;
  final VoidCallback onSelectWorkspace;
  final ResponseDetail responseDetail;
  final ReasoningSummary reasoningSummary;
  final bool subagentsEnabled;
  final ValueChanged<ResponseDetail> onResponseDetailChanged;
  final ValueChanged<ReasoningSummary> onReasoningSummaryChanged;
  final ValueChanged<bool> onSubagentsEnabledChanged;
  final AgentPermissionMode permissionMode;
  final ValueChanged<AgentPermissionMode> onPermissionModeChanged;
  final String userProfileText;
  final String agentMemoryText;
  final bool memoriesEnabled;
  final bool pastChatSearchEnabled;
  final bool autoRememberPreferences;
  final bool autoSelectSkills;
  final bool skillLearningEnabled;
  final String? dataDirectoryPath;
  final bool isLocalDataReady;
  final Future<void> Function(String) onSaveUserProfile;
  final Future<void> Function(String) onSaveAgentMemory;
  final ValueChanged<bool> onMemoriesEnabledChanged;
  final ValueChanged<bool> onPastChatSearchEnabledChanged;
  final ValueChanged<bool> onAutoRememberChanged;
  final ValueChanged<bool> onAutoSelectSkillsChanged;
  final ValueChanged<bool> onSkillLearningChanged;
  final String? skillsDirectoryPath;
  final List<McpServerProfile> mcpServers;
  final Map<String, McpServerStatus> mcpServerStatuses;
  final Future<void> Function(McpServerProfile) onAddMcpServer;
  final Future<void> Function(McpServerProfile, McpServerProfile)
      onUpdateMcpServer;
  final void Function(McpServerProfile, bool) onToggleMcpServer;
  final ValueChanged<McpServerProfile> onDeleteMcpServer;
  final ValueChanged<McpServerProfile> onRefreshMcpServer;

  String get _title => switch (selectedTab) {
        SettingsTab.general => 'General',
        SettingsTab.models => 'Providers and models',
        SettingsTab.tools => 'Tools and permissions',
        SettingsTab.mcp => 'MCP servers',
        SettingsTab.memory => 'Memories',
        SettingsTab.shortcuts => 'Keyboard shortcuts',
      };

  String get _description => switch (selectedTab) {
        SettingsTab.general => 'Application preferences and active project.',
        SettingsTab.models => 'Connection profiles and available models.',
        SettingsTab.tools => 'Choose which actions require your approval.',
        SettingsTab.mcp =>
          'Connect local and remote tool servers to your agent.',
        SettingsTab.memory => 'Personal context and skill matching.',
        SettingsTab.shortcuts => 'Quick actions for working from the keyboard.',
      };

  Widget _tabButton(SettingsTab tab, IconData icon, String label) {
    final selected = selectedTab == tab;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppColors.iceStrong : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => onSelectTab(tab),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? AppColors.blueDeep : AppColors.muted,
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? AppColors.blueDeep : AppColors.ink,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsContent() {
    return switch (selectedTab) {
      SettingsTab.general => _GeneralSettings(
          workspacePath: workspacePath,
          onSelectWorkspace: onSelectWorkspace,
          onNotice: onNotice,
          responseDetail: responseDetail,
          reasoningSummary: reasoningSummary,
          subagentsEnabled: subagentsEnabled,
          onResponseDetailChanged: onResponseDetailChanged,
          onReasoningSummaryChanged: onReasoningSummaryChanged,
          onSubagentsEnabledChanged: onSubagentsEnabledChanged,
        ),
      SettingsTab.models => _ModelSettings(
          providers: providers,
          refreshingProviderIds: refreshingProviderIds,
          modelDiscoveryErrors: modelDiscoveryErrors,
          onAddProvider: onAddProvider,
          onRefreshModels: onRefreshModels,
          onDeleteProvider: onDeleteProvider,
        ),
      SettingsTab.tools => _ToolSettings(
          permissionMode: permissionMode,
          onPermissionModeChanged: onPermissionModeChanged,
        ),
      SettingsTab.mcp => _McpSettings(
          servers: mcpServers,
          statuses: mcpServerStatuses,
          onAdd: onAddMcpServer,
          onUpdate: onUpdateMcpServer,
          onToggle: onToggleMcpServer,
          onDelete: onDeleteMcpServer,
          onRefresh: onRefreshMcpServer,
        ),
      SettingsTab.memory => _MemorySettings(
          userProfileText: userProfileText,
          agentMemoryText: agentMemoryText,
          memoriesEnabled: memoriesEnabled,
          pastChatSearchEnabled: pastChatSearchEnabled,
          autoRememberPreferences: autoRememberPreferences,
          autoSelectSkills: autoSelectSkills,
          skillLearningEnabled: skillLearningEnabled,
          dataDirectoryPath: dataDirectoryPath,
          isLocalDataReady: isLocalDataReady,
          skillsDirectoryPath: skillsDirectoryPath,
          onSaveUserProfile: onSaveUserProfile,
          onSaveAgentMemory: onSaveAgentMemory,
          onMemoriesEnabledChanged: onMemoriesEnabledChanged,
          onPastChatSearchEnabledChanged: onPastChatSearchEnabledChanged,
          onAutoRememberChanged: onAutoRememberChanged,
          onAutoSelectSkillsChanged: onAutoSelectSkillsChanged,
          onSkillLearningChanged: onSkillLearningChanged,
        ),
      SettingsTab.shortcuts => const _ShortcutSettings(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.canvas,
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageHeading(
            eyebrow: 'Preferences',
            title: 'Settings',
            description:
                'Choose how Penguin Code connects and works on your computer.',
          ),
          const SizedBox(height: 21),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 850;
                final tabs = [
                  _tabButton(
                    SettingsTab.general,
                    AppIcons.tuneRounded,
                    'General',
                  ),
                  _tabButton(
                    SettingsTab.models,
                    AppIcons.autoAwesomeOutlined,
                    'Models',
                  ),
                  _tabButton(
                    SettingsTab.tools,
                    AppIcons.securityOutlined,
                    'Tools and permissions',
                  ),
                  _tabButton(
                    SettingsTab.mcp,
                    AppIcons.hubOutlined,
                    'MCP servers',
                  ),
                  _tabButton(
                    SettingsTab.memory,
                    AppIcons.modelReasoning,
                    'Memories',
                  ),
                  _tabButton(
                    SettingsTab.shortcuts,
                    AppIcons.keyboardOutlined,
                    'Keyboard shortcuts',
                  ),
                ];
                final content = Expanded(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _description,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 19),
                          _settingsContent(),
                        ],
                      ),
                    ),
                  ),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: tabs),
                      ),
                      const SizedBox(height: 12),
                      content,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 220, child: Column(children: tabs)),
                    const SizedBox(width: 24),
                    const VerticalDivider(width: 1),
                    const SizedBox(width: 24),
                    content,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MemorySettings extends StatefulWidget {
  const _MemorySettings({
    required this.userProfileText,
    required this.agentMemoryText,
    required this.memoriesEnabled,
    required this.pastChatSearchEnabled,
    required this.autoRememberPreferences,
    required this.autoSelectSkills,
    required this.skillLearningEnabled,
    required this.dataDirectoryPath,
    required this.isLocalDataReady,
    required this.skillsDirectoryPath,
    required this.onSaveUserProfile,
    required this.onSaveAgentMemory,
    required this.onMemoriesEnabledChanged,
    required this.onPastChatSearchEnabledChanged,
    required this.onAutoRememberChanged,
    required this.onAutoSelectSkillsChanged,
    required this.onSkillLearningChanged,
  });

  final String userProfileText;
  final String agentMemoryText;
  final bool memoriesEnabled;
  final bool pastChatSearchEnabled;
  final bool autoRememberPreferences;
  final bool autoSelectSkills;
  final bool skillLearningEnabled;
  final String? dataDirectoryPath;
  final bool isLocalDataReady;
  final String? skillsDirectoryPath;
  final Future<void> Function(String) onSaveUserProfile;
  final Future<void> Function(String) onSaveAgentMemory;
  final ValueChanged<bool> onMemoriesEnabledChanged;
  final ValueChanged<bool> onPastChatSearchEnabledChanged;
  final ValueChanged<bool> onAutoRememberChanged;
  final ValueChanged<bool> onAutoSelectSkillsChanged;
  final ValueChanged<bool> onSkillLearningChanged;

  @override
  State<_MemorySettings> createState() => _MemorySettingsState();
}

class _MemorySettingsState extends State<_MemorySettings> {
  late final TextEditingController _userController =
      TextEditingController(text: widget.userProfileText);
  late final TextEditingController _agentController =
      TextEditingController(text: widget.agentMemoryText);
  bool _savingUserProfile = false;
  bool _savingAgentMemory = false;

  @override
  void didUpdateWidget(covariant _MemorySettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfileText != widget.userProfileText &&
        _userController.text == oldWidget.userProfileText) {
      _userController.text = widget.userProfileText;
    }
    if (oldWidget.agentMemoryText != widget.agentMemoryText &&
        _agentController.text == oldWidget.agentMemoryText) {
      _agentController.text = widget.agentMemoryText;
    }
  }

  @override
  void dispose() {
    _userController.dispose();
    _agentController.dispose();
    super.dispose();
  }

  Future<void> _saveUserProfile() async {
    setState(() => _savingUserProfile = true);
    try {
      await widget.onSaveUserProfile(_userController.text);
    } finally {
      if (mounted) setState(() => _savingUserProfile = false);
    }
  }

  Future<void> _saveAgentMemory() async {
    setState(() => _savingAgentMemory = true);
    try {
      await widget.onSaveAgentMemory(_agentController.text);
    } finally {
      if (mounted) setState(() => _savingAgentMemory = false);
    }
  }

  Widget _fileCard({
    required String title,
    required String description,
    required TextEditingController controller,
    required String editorKey,
    required String saveKey,
    required String hintText,
    required bool saving,
    required VoidCallback? onSave,
    Widget? trailing,
  }) =>
      _SettingsCard(
        title: title,
        description: description,
        trailing: trailing,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: Key(editorKey),
              controller: controller,
              minLines: 7,
              maxLines: 12,
              maxLength: AgentMemoryLimits.maxCharacters,
              enabled: widget.isLocalDataReady,
              decoration: InputDecoration(
                hintText: hintText,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: Key(saveKey),
                onPressed: onSave,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.checkRounded, size: 17),
                label: Text(saving ? 'Saving' : 'Save file'),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fileCard(
          title: 'User profile',
          description:
              'Store stable facts about you, your preferences, and how you like to work. The app can save clear preferences automatically.',
          controller: _userController,
          editorKey: 'settings.memories.user.editor',
          saveKey: 'settings.memories.user.save',
          hintText:
              '# User profile\n\n## User preferences\n- Add facts about yourself and how you like the agent to work.',
          saving: _savingUserProfile,
          onSave: widget.isLocalDataReady && !_savingUserProfile
              ? _saveUserProfile
              : null,
          trailing: Switch.adaptive(
            value: widget.memoriesEnabled,
            onChanged: widget.isLocalDataReady
                ? widget.onMemoriesEnabledChanged
                : null,
          ),
        ),
        const SizedBox(height: 13),
        _fileCard(
          title: 'Agent notes',
          description:
              'Keep verified environment details, conventions, and lessons the agent learns. The agent can update this file with its memory tool.',
          controller: _agentController,
          editorKey: 'settings.memories.agent.editor',
          saveKey: 'settings.memories.agent.save',
          hintText:
              '# Penguin Code memory\n\n## Learned notes\n- Add durable facts that help across future chats.',
          saving: _savingAgentMemory,
          onSave: widget.isLocalDataReady && !_savingAgentMemory
              ? _saveAgentMemory
              : null,
        ),
        const SizedBox(height: 13),
        _SettingsCard(
          title: 'Past conversation search',
          description:
              'The agent can search saved chats when you ask it to recall something. Matching excerpts are sent to your selected model.',
          child: SwitchListTile.adaptive(
            key: const Key('settings.historySearch.enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow the agent to search past chats'),
            subtitle: const Text(
              'Off by default. Conversation search in the chat list stays local.',
            ),
            value: widget.pastChatSearchEnabled,
            onChanged: widget.isLocalDataReady
                ? widget.onPastChatSearchEnabledChanged
                : null,
          ),
        ),
        const SizedBox(height: 13),
        _SettingsCard(
          title: 'Automatic learning',
          description:
              'The app saves clear preference statements to the user profile. The model can also save durable, verified notes when memory is enabled.',
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remember explicit preferences'),
                subtitle: const Text(
                  'Only direct preferences are saved; likely credentials are skipped.',
                ),
                value: widget.autoRememberPreferences,
                onChanged: widget.memoriesEnabled
                    ? widget.onAutoRememberChanged
                    : null,
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Automatically select matching skills'),
                subtitle: const Text(
                  'Match installed skills to each request and your saved preferences.',
                ),
                value: widget.autoSelectSkills,
                onChanged: widget.isLocalDataReady
                    ? widget.onAutoSelectSkillsChanged
                    : null,
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                key: const Key('settings.memories.skillLearning'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Let the agent propose reusable skills'),
                subtitle: const Text(
                  'Off by default. Proposals stay pending until you review and approve them in Skills.',
                ),
                value: widget.skillLearningEnabled,
                onChanged: widget.onSkillLearningChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        _SettingsCard(
          title: 'Local agent files',
          description: widget.isLocalDataReady
              ? 'Chats, workspaces, outputs, skills, and memory files stay on this computer.'
              : 'Preparing the local agent folders…',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                widget.dataDirectoryPath ?? 'Waiting for the data folder',
                style: theme.textTheme.bodySmall,
              ),
              if (widget.dataDirectoryPath != null) ...[
                const SizedBox(height: 7),
                SelectableText(
                  'User profile: ${_pathToMemoryFile(widget.dataDirectoryPath!, 'USER.md')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 5),
                SelectableText(
                  'Agent notes: ${_pathToMemoryFile(widget.dataDirectoryPath!, 'MEMORY.md')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
              if (widget.skillsDirectoryPath != null) ...[
                const SizedBox(height: 7),
                Text(
                  'Local skills: ${widget.skillsDirectoryPath}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _pathToMemoryFile(String root, String fileName) =>
      '$root${root.endsWith('\\') || root.endsWith('/') ? '' : '/'}$fileName';
}

abstract final class AgentMemoryLimits {
  static const maxCharacters = 4096;
}

class _GeneralSettings extends StatelessWidget {
  const _GeneralSettings({
    required this.workspacePath,
    required this.onSelectWorkspace,
    required this.onNotice,
    required this.responseDetail,
    required this.reasoningSummary,
    required this.subagentsEnabled,
    required this.onResponseDetailChanged,
    required this.onReasoningSummaryChanged,
    required this.onSubagentsEnabledChanged,
  });

  final String? workspacePath;
  final VoidCallback onSelectWorkspace;
  final ValueChanged<String> onNotice;
  final ResponseDetail responseDetail;
  final ReasoningSummary reasoningSummary;
  final bool subagentsEnabled;
  final ValueChanged<ResponseDetail> onResponseDetailChanged;
  final ValueChanged<ReasoningSummary> onReasoningSummaryChanged;
  final ValueChanged<bool> onSubagentsEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SettingsCard(
          title: 'Project folder',
          description: 'Folder attached to the current project.',
          trailing: OutlinedButton.icon(
            key: const Key('settings.workspace'),
            onPressed: onSelectWorkspace,
            icon: const Icon(AppIcons.folderOpenRounded, size: 17),
            label: const Text('Choose project'),
          ),
          child: Text(
            workspacePath ?? 'No project selected',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
        const SizedBox(height: 13),
        _SettingsCard(
          title: 'Appearance',
          description: 'Penguin Code visual theme.',
          child: Row(
            children: [
              const _ChoicePill(
                icon: AppIcons.lightModeOutlined,
                label: 'Sky light',
                selected: true,
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () =>
                    onNotice('Dark theme will be added in a later iteration.'),
                child: const Text('Dark theme'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        const _SettingsCard(
          title: 'Language',
          description: 'Interface language.',
          child: _ChoicePill(
            icon: AppIcons.languageRounded,
            label: 'English',
            selected: true,
          ),
        ),
        const SizedBox(height: 13),
        _SettingsCard(
          title: 'Output detail',
          description:
              'Choose how much detail to request in model responses. Provider behavior may vary.',
          child: DropdownButtonFormField<ResponseDetail>(
            key: const Key('settings.responseDetail'),
            initialValue: responseDetail,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: ResponseDetail.modelDefault,
                child: Text('Model default'),
              ),
              DropdownMenuItem(
                value: ResponseDetail.low,
                child: Text('Low'),
              ),
              DropdownMenuItem(
                value: ResponseDetail.medium,
                child: Text('Medium'),
              ),
              DropdownMenuItem(
                value: ResponseDetail.high,
                child: Text('High'),
              ),
            ],
            onChanged: (value) {
              if (value != null) onResponseDetailChanged(value);
            },
          ),
        ),
        const SizedBox(height: 13),
        _SettingsCard(
          title: 'Reasoning summary',
          description:
              'Choose whether the model adds a high-level summary. Hidden chain-of-thought is never requested.',
          child: DropdownButtonFormField<ReasoningSummary>(
            key: const Key('settings.reasoningSummary'),
            initialValue: reasoningSummary,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: ReasoningSummary.automatic,
                child: Text('Automatic'),
              ),
              DropdownMenuItem(
                value: ReasoningSummary.concise,
                child: Text('Concise'),
              ),
              DropdownMenuItem(
                value: ReasoningSummary.detailed,
                child: Text('Detailed'),
              ),
              DropdownMenuItem(
                value: ReasoningSummary.none,
                child: Text('None'),
              ),
            ],
            onChanged: (value) {
              if (value != null) onReasoningSummaryChanged(value);
            },
          ),
        ),
        const SizedBox(height: 13),
        _SettingsCard(
          title: 'Subagents',
          description:
              'Let the model delegate focused tasks that run with the current provider and computer access permissions.',
          trailing: Switch.adaptive(
            key: const Key('settings.subagents'),
            value: subagentsEnabled,
            onChanged: onSubagentsEnabledChanged,
          ),
          child: const Text(
            'Off by default. Up to three delegated tasks can run at once.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _ModelSettings extends StatelessWidget {
  const _ModelSettings({
    required this.providers,
    required this.refreshingProviderIds,
    required this.modelDiscoveryErrors,
    required this.onAddProvider,
    required this.onRefreshModels,
    required this.onDeleteProvider,
  });

  final List<ProviderProfile> providers;
  final Set<String> refreshingProviderIds;
  final Map<String, String> modelDiscoveryErrors;
  final ValueChanged<ProviderProfile> onAddProvider;
  final ValueChanged<ProviderProfile> onRefreshModels;
  final ValueChanged<ProviderProfile> onDeleteProvider;

  Future<void> _add(BuildContext context) async {
    final provider = await showDialog<ProviderProfile>(
      context: context,
      builder: (context) => const _ProviderDialog(),
    );
    if (provider != null) onAddProvider(provider);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E9),
            border: Border.all(color: const Color(0xFFF0E1BE)),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIcons.infoOutlineRounded,
                color: AppColors.amber,
                size: 19,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Provider profiles and API keys stay in memory for this session. Models are discovered from the provider model list; the entered model remains available when discovery is unsupported.',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Provider profiles',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton.icon(
              key: const Key('provider.add'),
              onPressed: () => _add(context),
              icon: const Icon(AppIcons.addRounded, size: 18),
              label: const Text('Add provider'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (providers.isEmpty)
          _NoProviders(onAdd: () => _add(context))
        else
          ...providers.map(
            (provider) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.ice,
                    child: Icon(
                      provider.onDevice
                          ? AppIcons.devicesOutlined
                          : AppIcons.cloudOutlined,
                      color: AppColors.blueDeep,
                    ),
                  ),
                  title: Text(provider.name),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.endpoint,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${provider.availableModels.length} ${provider.availableModels.length == 1 ? 'model' : 'models'} available',
                          style: const TextStyle(fontSize: 11),
                        ),
                        if (refreshingProviderIds.contains(provider.id)) ...[
                          const SizedBox(height: 6),
                          const Row(
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 7),
                              Text(
                                'Discovering models',
                                style: TextStyle(
                                  color: AppColors.blueDeep,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (modelDiscoveryErrors[provider.id] case final error?)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              error,
                              style: const TextStyle(
                                color: AppColors.red,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _StatusTag(
                        label: 'Configured',
                        color: AppColors.green,
                      ),
                      const SizedBox(width: 7),
                      IconButton(
                        key: Key('provider.refresh.${provider.id}'),
                        tooltip: 'Refresh models',
                        onPressed: refreshingProviderIds.contains(provider.id)
                            ? null
                            : () => onRefreshModels(provider),
                        icon: const Icon(AppIcons.refreshRounded, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Remove ' + provider.name,
                        onPressed: () => onDeleteProvider(provider),
                        icon: const Icon(
                          AppIcons.deleteOutlineRounded,
                          size: 19,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NoProviders extends StatelessWidget {
  const _NoProviders({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(AppIcons.linkOffRounded, color: AppColors.blue, size: 28),
          const SizedBox(height: 10),
          Text(
            'No providers added',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 5),
          const Text(
            'Add a profile to prepare the model selector.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 13),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(AppIcons.addRounded, size: 17),
            label: const Text('Add provider'),
          ),
        ],
      ),
    );
  }
}

class _ProviderDialog extends StatefulWidget {
  const _ProviderDialog();

  @override
  State<_ProviderDialog> createState() => _ProviderDialogState();
}

class _ProviderDialogState extends State<_ProviderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _model = TextEditingController();
  final _endpoint = TextEditingController();
  final _apiKey = TextEditingController();
  bool _onDevice = false;

  @override
  void dispose() {
    _name.dispose();
    _model.dispose();
    _endpoint.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Complete this field.' : null;

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final model = _model.text.trim();
    final endpoint = _endpoint.text.trim();
    final name = _name.text.trim();
    Navigator.pop(
      context,
      ProviderProfile(
        id: name + ':' + endpoint,
        name: name,
        model: model,
        endpoint: endpoint,
        onDevice: _onDevice,
        apiKey: _apiKey.text.trim().isEmpty ? null : _apiKey.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(AppIcons.addLinkRounded, color: AppColors.blue),
      title: const Text('Add provider'),
      content: SizedBox(
        width: 470,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Configure an OpenAI-compatible chat endpoint. Profiles and keys are kept in memory for this session.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                TextFormField(
                  key: const Key('provider.name'),
                  controller: _name,
                  validator: _required,
                  decoration: const InputDecoration(labelText: 'Provider name'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('provider.endpoint'),
                  controller: _endpoint,
                  validator: _required,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'http://127.0.0.1:11434/v1',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('provider.model'),
                  controller: _model,
                  validator: _required,
                  decoration: const InputDecoration(
                    labelText: 'Model identifier',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('provider.key'),
                  controller: _apiKey,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API key (optional)',
                    prefixIcon: Icon(AppIcons.keyOutlined),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _onDevice,
                  onChanged: (value) => setState(() => _onDevice = value),
                  title: const Text('Runs on this computer'),
                  subtitle: const Text(
                    'For example, a model server on this computer.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('provider.save'),
          onPressed: _save,
          child: const Text('Save profile'),
        ),
      ],
    );
  }
}

class _ToolSettings extends StatelessWidget {
  const _ToolSettings({
    required this.permissionMode,
    required this.onPermissionModeChanged,
  });

  final AgentPermissionMode permissionMode;
  final ValueChanged<AgentPermissionMode> onPermissionModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose computer access',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  permissionMode == AgentPermissionMode.fullAccess
                      ? 'Full access is enabled. The connected model can access files across your computer and run commands without per-action approval.'
                      : 'This setting controls which files the agent can access and when it needs approval. File edits require your approval outside Full access.',
                  style: TextStyle(
                    color: permissionMode == AgentPermissionMode.fullAccess
                        ? AppColors.amber
                        : AppColors.muted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 13),
                ProjectAccessMenu(
                  value: permissionMode,
                  onChanged: onPermissionModeChanged,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _AvailableProjectTools(),
        const SizedBox(height: 14),
        _SafetyNote(permissionMode: permissionMode),
      ],
    );
  }
}

class _AvailableProjectTools extends StatelessWidget {
  const _AvailableProjectTools();

  @override
  Widget build(BuildContext context) {
    const tools = [
      (
        AppIcons.folderOpenRounded,
        'List computer files',
        'Inspect readable files and folders anywhere on the computer.',
      ),
      (
        AppIcons.searchRounded,
        'Search computer files',
        'Find literal text in supported source and text files anywhere on the computer.',
      ),
      (
        AppIcons.fileCodeOutlined,
        'Read a file',
        'Read one supported file from any computer folder.',
      ),
      (
        AppIcons.editNoteRounded,
        'Edit a file',
        'Replace a unique text match after reading. Approval depends on the selected mode.',
      ),
      (
        AppIcons.terminalRounded,
        'Run a command',
        'Run shell commands on your computer. Available in Full access mode.',
      ),
    ];
    return Column(
      children: [
        for (final tool in tools)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                leading: Icon(tool.$1, color: AppColors.blueDeep),
                title: Text(tool.$2),
                subtitle: Text(tool.$3),
                dense: true,
              ),
            ),
          ),
      ],
    );
  }
}

class _SafetyNote extends StatelessWidget {
  const _SafetyNote({required this.permissionMode});

  final AgentPermissionMode permissionMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: permissionMode == AgentPermissionMode.fullAccess
            ? const Color(0xFFFFF5E5)
            : AppColors.ice,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            permissionMode == AgentPermissionMode.fullAccess
                ? AppIcons.securityOutlined
                : AppIcons.shieldOutlined,
            color: permissionMode == AgentPermissionMode.fullAccess
                ? AppColors.amber
                : AppColors.blueDeep,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              permissionMode == AgentPermissionMode.fullAccess
                  ? 'The connected model may send file contents and command output to your selected provider. Only use Full access with a model you trust.'
                  : 'File tools can access supported files anywhere on your computer. Credential files, unsupported files, and symbolic links remain excluded. The selected access mode controls approvals, and shell commands require Full access.',
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _McpSettings extends StatelessWidget {
  const _McpSettings({
    required this.servers,
    required this.statuses,
    required this.onAdd,
    required this.onUpdate,
    required this.onToggle,
    required this.onDelete,
    required this.onRefresh,
  });

  final List<McpServerProfile> servers;
  final Map<String, McpServerStatus> statuses;
  final Future<void> Function(McpServerProfile) onAdd;
  final Future<void> Function(McpServerProfile, McpServerProfile) onUpdate;
  final void Function(McpServerProfile, bool) onToggle;
  final ValueChanged<McpServerProfile> onDelete;
  final ValueChanged<McpServerProfile> onRefresh;

  Future<void> _addServer(BuildContext context) async {
    final profile = await showDialog<McpServerProfile>(
      context: context,
      builder: (context) => const _McpServerDialog(),
    );
    if (profile != null) await onAdd(profile);
  }

  Future<void> _editServer(
    BuildContext context,
    McpServerProfile server,
  ) async {
    final updated = await showDialog<McpServerProfile>(
      context: context,
      builder: (context) => _McpServerDialog(existing: server),
    );
    if (updated != null) await onUpdate(server, updated);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'MCP servers',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton.icon(
              key: const Key('settings.mcp.add'),
              onPressed: () => _addServer(context),
              icon: const Icon(AppIcons.addRounded, size: 16),
              label: const Text('Add server'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Connect local programs over stdio or remote endpoints over HTTP and SSE. Only enable servers you trust. Their tools and results are sent to the selected model, and every tool call asks for your approval, including in Full access mode.',
          style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 14),
        if (servers.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No MCP servers configured. Add a local command or remote endpoint to make its tools available in chat.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ),
        for (final server in servers)
          _McpServerCard(
            server: server,
            status: statuses[server.id] ??
                const McpServerStatus(
                  state: McpServerConnectionState.disconnected,
                ),
            onToggle: (enabled) => onToggle(server, enabled),
            onEdit: () => _editServer(context, server),
            onDelete: () => onDelete(server),
            onRefresh: () => onRefresh(server),
          ),
      ],
    );
  }
}

class _McpServerCard extends StatelessWidget {
  const _McpServerCard({
    required this.server,
    required this.status,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
  });

  final McpServerProfile server;
  final McpServerStatus status;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final connected = status.state == McpServerConnectionState.connected;
    final stateText = switch (status.state) {
      McpServerConnectionState.disconnected => 'Not connected',
      McpServerConnectionState.connecting => 'Connecting…',
      McpServerConnectionState.connected =>
        'Connected · ${status.toolCount} ${status.toolCount == 1 ? 'tool' : 'tools'}',
      McpServerConnectionState.error =>
        'Connection failed: ${status.error ?? 'Unknown error.'}',
    };
    final connectionTarget = switch (server.transport) {
      McpTransportType.stdio =>
        '${server.command}${server.arguments.isEmpty ? '' : ' ${server.arguments.join(' ')}'}',
      McpTransportType.http || McpTransportType.sse => server.endpoint,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 8, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(AppIcons.hubOutlined,
                    color: AppColors.blueDeep, size: 19),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    server.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit server',
                  onPressed: onEdit,
                  icon: const Icon(AppIcons.editNoteRounded, size: 17),
                ),
                IconButton(
                  tooltip: 'Refresh tools',
                  onPressed: connected ? onRefresh : null,
                  icon: const Icon(AppIcons.refreshRounded, size: 17),
                ),
                IconButton(
                  tooltip: 'Remove server',
                  onPressed: onDelete,
                  icon: const Icon(AppIcons.deleteOutlineRounded, size: 17),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 28, right: 8),
              child: Text(
                connectionTarget,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (status.state == McpServerConnectionState.error)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 5, right: 8),
                child: Text(
                  stateText,
                  style: const TextStyle(
                    color: AppColors.amber,
                    fontSize: 11,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 5),
                child: Text(
                  stateText,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ),
            SwitchListTile(
              key: Key('settings.mcp.toggle.${server.id}'),
              contentPadding: const EdgeInsets.only(left: 26, right: 7),
              dense: true,
              title: const Text('Connect server'),
              subtitle:
                  const Text('Start at launch and expose tools in chats.'),
              value: server.enabled,
              onChanged: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _McpServerDialog extends StatefulWidget {
  const _McpServerDialog({this.existing});

  final McpServerProfile? existing;

  @override
  State<_McpServerDialog> createState() => _McpServerDialogState();
}

class _McpServerDialogState extends State<_McpServerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _command = TextEditingController();
  final _arguments = TextEditingController();
  final _endpoint = TextEditingController();
  final _headers = TextEditingController();
  late McpTransportType _transport;
  bool _clearSavedCredentials = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _transport = existing?.transport ?? McpTransportType.stdio;
    _name.text = existing?.name ?? '';
    _command.text = existing?.command ?? '';
    _arguments.text = existing?.arguments.join('\n') ?? '';
    _endpoint.text = existing?.endpoint ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    _arguments.dispose();
    _endpoint.dispose();
    _headers.dispose();
    super.dispose();
  }

  Map<String, String>? _parseHeaders() {
    final headers = <String, String>{};
    final names = <String>{};
    for (final line in _headers.text.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) continue;
      final separator = line.indexOf(':');
      if (separator <= 0) return null;
      final name = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (!isValidMcpHeaderName(name) ||
          value.contains('\r') ||
          value.contains('\n') ||
          !names.add(name.toLowerCase())) {
        return null;
      }
      headers[name] = value;
    }
    if (headers.length > 32 ||
        utf8.encode(jsonEncode(headers)).length > 16384) {
      return null;
    }
    return headers;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final parsedHeaders = _parseHeaders();
    final arguments = _arguments.text
        .split(RegExp(r'\r?\n'))
        .where((value) => value.trim().isNotEmpty)
        .map((value) => value.trim())
        .toList(growable: false);
    final existing = widget.existing;
    final headers =
        _transport == McpTransportType.stdio || _clearSavedCredentials
            ? const <String, String>{}
            : _headers.text.trim().isEmpty && existing != null
                ? existing.headers
                : parsedHeaders ?? const <String, String>{};
    Navigator.of(context).pop(McpServerProfile(
      id: existing?.id ?? 'mcp-${DateTime.now().microsecondsSinceEpoch}',
      name: _name.text.trim(),
      transport: _transport,
      command: _transport == McpTransportType.stdio ? _command.text.trim() : '',
      arguments: arguments,
      endpoint:
          _transport == McpTransportType.stdio ? '' : _endpoint.text.trim(),
      headers: headers,
      savedHeaderNames: existing?.credentialHeaderNames ?? const [],
      enabled: existing?.enabled ?? false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('settings.mcp.add.dialog'),
      title:
          Text(widget.existing == null ? 'Add MCP server' : 'Edit MCP server'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  switch (_transport) {
                    McpTransportType.stdio =>
                      'Starts the executable directly with separate arguments. The app does not assemble a shell command. Windows may still dispatch .bat and .cmd launchers through the system shell.',
                    McpTransportType.http =>
                      'Uses Streamable HTTP and falls back to legacy SSE when needed. Use HTTPS for remote servers; plain HTTP is allowed only on loopback addresses.',
                    McpTransportType.sse =>
                      'Connects to a legacy MCP HTTP+SSE server. Use HTTPS for remote servers; plain HTTP is allowed only on loopback addresses.',
                  },
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 15),
                TextFormField(
                  key: const Key('settings.mcp.name'),
                  controller: _name,
                  autofocus: true,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Server name'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<McpTransportType>(
                  key: const Key('settings.mcp.transport'),
                  initialValue: _transport,
                  decoration: const InputDecoration(labelText: 'Transport'),
                  items: const [
                    DropdownMenuItem(
                      value: McpTransportType.stdio,
                      child: Text('Local command (stdio)'),
                    ),
                    DropdownMenuItem(
                      value: McpTransportType.http,
                      child: Text('HTTP (Streamable HTTP)'),
                    ),
                    DropdownMenuItem(
                      value: McpTransportType.sse,
                      child: Text('SSE (legacy)'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _transport = value);
                  },
                ),
                const SizedBox(height: 10),
                if (_transport == McpTransportType.stdio) ...[
                  TextFormField(
                    key: const Key('settings.mcp.command'),
                    controller: _command,
                    maxLength: 1024,
                    decoration: const InputDecoration(
                      labelText: 'Program or executable path',
                      hintText: 'npx',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Required'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: const Key('settings.mcp.arguments'),
                    controller: _arguments,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 16384,
                    decoration: const InputDecoration(
                      labelText: 'Arguments',
                      hintText: '-y\n@vendor/server',
                      helperText:
                          'One argument per line; no shell command is assembled.',
                    ),
                    validator: (value) {
                      final arguments = (value ?? '')
                          .split(RegExp(r'\r?\n'))
                          .where((argument) => argument.trim().isNotEmpty);
                      return arguments.length > 64
                          ? 'Use no more than 64 arguments.'
                          : null;
                    },
                  ),
                ] else ...[
                  TextFormField(
                    key: const Key('settings.mcp.endpoint'),
                    controller: _endpoint,
                    maxLength: 2048,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'https://example.com/mcp',
                    ),
                    validator: (value) =>
                        isAllowedMcpEndpoint(value?.trim() ?? '')
                            ? null
                            : 'Use HTTPS, or HTTP on localhost / 127.0.0.1.',
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: const Key('settings.mcp.headers'),
                    controller: _headers,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 16384,
                    decoration: InputDecoration(
                      labelText: 'Request headers',
                      hintText: 'Authorization: Bearer token',
                      helperText: widget.existing == null
                          ? 'Optional. One header per line. Values are stored in the OS secure store.'
                          : 'Leave blank to keep saved headers. New values replace them and stay in the OS secure store.',
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty || _parseHeaders() != null
                            ? null
                            : 'Use unique valid header names, one per line.',
                  ),
                  if (widget.existing?.credentialHeaderNames.isNotEmpty == true)
                    CheckboxListTile(
                      key: const Key('settings.mcp.clear_credentials'),
                      contentPadding: EdgeInsets.zero,
                      value: _clearSavedCredentials,
                      onChanged: (value) => setState(
                        () => _clearSavedCredentials = value ?? false,
                      ),
                      title: const Text('Clear saved request headers'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('settings.mcp.add.save'),
          onPressed: _save,
          child: Text(widget.existing == null ? 'Add server' : 'Save changes'),
        ),
      ],
    );
  }
}

class _ShortcutSettings extends StatelessWidget {
  const _ShortcutSettings();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _ShortcutRow(action: 'Send task', shortcut: 'Enter'),
        SizedBox(height: 8),
        _ShortcutRow(action: 'New line', shortcut: 'Shift + Enter'),
        SizedBox(height: 8),
        _ShortcutRow(action: 'New chat', shortcut: 'Ctrl + N'),
        SizedBox(height: 8),
        _ShortcutRow(action: 'Show or hide history', shortcut: 'Ctrl + B'),
        SizedBox(height: 8),
        _ShortcutRow(action: 'Search conversations', shortcut: 'Ctrl + K'),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.action, required this.shortcut});

  final String action;
  final String shortcut;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(action, style: const TextStyle(color: AppColors.ink)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppColors.line),
              ),
              child: Text(
                shortcut,
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.description,
    required this.child,
    this.trailing,
  });

  final String title;
  final String description;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 13),
            child,
          ],
        ),
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.ice : Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: selected ? AppColors.sky : AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.blueDeep),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.blueDeep,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
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
            letterSpacing: 0.2,
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

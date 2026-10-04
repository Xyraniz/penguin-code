import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../widgets/app_icons.dart';
import '../widgets/project_access_menu.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.selectedTab,
    required this.providers,
    required this.onSelectTab,
    required this.onAddProvider,
    required this.onDeleteProvider,
    required this.onNotice,
    required this.workspacePath,
    required this.onSelectWorkspace,
    required this.permissionMode,
    required this.onPermissionModeChanged,
  });

  final SettingsTab selectedTab;
  final List<ProviderProfile> providers;
  final ValueChanged<SettingsTab> onSelectTab;
  final ValueChanged<ProviderProfile> onAddProvider;
  final ValueChanged<ProviderProfile> onDeleteProvider;
  final ValueChanged<String> onNotice;
  final String? workspacePath;
  final VoidCallback onSelectWorkspace;
  final AgentPermissionMode permissionMode;
  final ValueChanged<AgentPermissionMode> onPermissionModeChanged;

  String get _title => switch (selectedTab) {
        SettingsTab.general => 'General',
        SettingsTab.models => 'Providers and models',
        SettingsTab.tools => 'Tools and permissions',
        SettingsTab.shortcuts => 'Keyboard shortcuts',
      };

  String get _description => switch (selectedTab) {
        SettingsTab.general => 'Application preferences and active project.',
        SettingsTab.models => 'Connection profiles and available models.',
        SettingsTab.tools => 'Choose which actions require your approval.',
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
        ),
      SettingsTab.models => _ModelSettings(
          providers: providers,
          onAddProvider: onAddProvider,
          onDeleteProvider: onDeleteProvider,
        ),
      SettingsTab.tools => _ToolSettings(
          permissionMode: permissionMode,
          onPermissionModeChanged: onPermissionModeChanged,
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

class _GeneralSettings extends StatelessWidget {
  const _GeneralSettings({
    required this.workspacePath,
    required this.onSelectWorkspace,
    required this.onNotice,
  });

  final String? workspacePath;
  final VoidCallback onSelectWorkspace;
  final ValueChanged<String> onNotice;

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
      ],
    );
  }
}

class _ModelSettings extends StatelessWidget {
  const _ModelSettings({
    required this.providers,
    required this.onAddProvider,
    required this.onDeleteProvider,
  });

  final List<ProviderProfile> providers;
  final ValueChanged<ProviderProfile> onAddProvider;
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
                  'Provider profiles, API keys, and chat messages stay in memory for this session. Messages are sent to the configured provider.',
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
                  subtitle: Text(provider.model + ' · ' + provider.endpoint),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _StatusTag(
                        label: 'Configured',
                        color: AppColors.green,
                      ),
                      const SizedBox(width: 7),
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
        id: name + ':' + model + ':' + endpoint,
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
                  'Choose project access',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'This setting controls which read-only tools are sent to the selected model.',
                  style: TextStyle(
                    color: AppColors.muted,
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
        const _SafetyNote(),
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
        'List project files',
        'Inspect readable files and folders.',
      ),
      (
        AppIcons.searchRounded,
        'Search project files',
        'Find literal text in supported source and text files.',
      ),
      (
        AppIcons.fileCodeOutlined,
        'Read a project file',
        'Read one supported file within the selected project.',
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
  const _SafetyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.ice,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.line),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.shieldOutlined, color: AppColors.blueDeep, size: 18),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Project reads stay inside the selected folder. Credential files, generated folders, unsupported files, and symbolic links are excluded. File edits and terminal commands are not available.',
              style: TextStyle(
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

import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/models/helpdesk_model.dart';
import 'package:provider/provider.dart';

class HelpdeskPanel extends StatelessWidget {
  const HelpdeskPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HelpdeskModel>(
      builder: (context, model, child) {
        if (model.isAgentModeEnabled) {
          return const _AgentHelpdeskPanel();
        }
        return const _ClientHelpdeskPanel();
      },
    );
  }
}

class _AgentHelpdeskPanel extends StatelessWidget {
  const _AgentHelpdeskPanel();

  Future<void> _openOperationalFieldsDialog(
    BuildContext context,
    HelpdeskModel model,
  ) async {
    final assignment = model.assignment;
    if (assignment == null) {
      return;
    }

    final estimatedController = TextEditingController(
      text: (assignment.ticket.estimatedMinutes ?? 30).toString(),
    );
    var selectedDifficulty =
        (assignment.ticket.difficulty ?? 'medium').trim().toLowerCase();
    var localError = '';

    final updated = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return StatefulBuilder(
              builder: (dialogContext, setState) {
                return AlertDialog(
                  title: const Text('Operational fields'),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedDifficulty,
                          decoration: const InputDecoration(
                            labelText: 'Difficulty',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'low',
                              child: Text('Low'),
                            ),
                            DropdownMenuItem(
                              value: 'medium',
                              child: Text('Medium'),
                            ),
                            DropdownMenuItem(
                              value: 'high',
                              child: Text('High'),
                            ),
                          ],
                          onChanged: model.updatingOperationalFields
                              ? null
                              : (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() {
                                    selectedDifficulty = value;
                                    localError = '';
                                  });
                                },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: estimatedController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Estimated time (min)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (localError.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            localError,
                            style: TextStyle(color: Colors.red[700]),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: model.updatingOperationalFields
                          ? null
                          : () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: model.updatingOperationalFields
                          ? null
                          : () async {
                              final estimatedMinutes = int.tryParse(
                                estimatedController.text.trim(),
                              );
                              if (estimatedMinutes == null ||
                                  estimatedMinutes <= 0) {
                                setState(() {
                                  localError =
                                      'Estimated time must be a positive number.';
                                });
                                return;
                              }
                              final saved =
                                  await model.updateAssignmentOperationalFields(
                                difficulty: selectedDifficulty,
                                estimatedMinutes: estimatedMinutes,
                              );
                              if (!dialogContext.mounted) {
                                return;
                              }
                              if (saved) {
                                Navigator.of(dialogContext).pop(true);
                                return;
                              }
                              setState(() {
                                localError = model.lastError ??
                                    'Could not update ticket operational fields.';
                              });
                            },
                      child: Text(
                        model.updatingOperationalFields
                            ? 'Saving...'
                            : 'Save fields',
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;

    estimatedController.dispose();
    if (!updated || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Operational fields updated for the current ticket.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HelpdeskModel>(
      builder: (context, model, child) {
        final assignment = model.assignment;
        final profileName = model.profileDisplayName.trim();
        final agentDisplayName = model.agent?.displayName.trim() ?? '';
        final displayName = profileName.isNotEmpty
            ? profileName
            : agentDisplayName.isNotEmpty
                ? agentDisplayName
                : model.agentId;
        final statusDropdownValue = model.hasActiveAssignment
            ? model.effectiveStatus
            : model.desiredStatus;
        final statusSelectorLocked = model.hasActiveAssignment;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(13)),
            border: Border.all(color: Theme.of(context).colorScheme.surface),
          ),
          child: SingleChildScrollView(
            primary: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Helpdesk agent console',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Use agent mode only on helpdesk operator machines. The dashboard dispatches tickets here using the target RustDesk ID.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => DesktopSettingPage.switch2page(
                      SettingsTabKey.account,
                    ),
                    child: const Text('Profile'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => model.refreshNow(),
                    child: const Text('Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    label: 'Mode',
                    value: 'Agent',
                  ),
                  _InfoChip(
                    label: 'Agent',
                    value: displayName.isEmpty ? 'Pending...' : displayName,
                  ),
                  _InfoChip(
                    label: 'Current',
                    value: _statusLabel(model.effectiveStatus),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ConstrainedBox(
                    constraints:
                        const BoxConstraints(minWidth: 180, maxWidth: 220),
                    child: DropdownButtonFormField<String>(
                      value: statusDropdownValue,
                      decoration: const InputDecoration(
                        labelText: 'Operator status',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'offline',
                          child: Text('Offline'),
                        ),
                        DropdownMenuItem(
                          value: 'away',
                          child: Text('Away'),
                        ),
                        DropdownMenuItem(
                          value: 'available',
                          child: Text('Available'),
                        ),
                        DropdownMenuItem(
                          value: 'opening',
                          child: Text('Opening (automatic)'),
                        ),
                        DropdownMenuItem(
                          value: 'busy',
                          child: Text('Busy (automatic)'),
                        ),
                      ],
                      onChanged: statusSelectorLocked ? null : (value) {
                        if (value != null) {
                          model.setDesiredStatus(value);
                        }
                      },
                    ),
                  ),
                  if (model.lastPresenceSyncAt != null) ...[
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Last sync: ${model.lastPresenceSyncAt!.toLocal()}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              if (model.waitingForClientApproval) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surface.withOpacity(0.24),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Waiting for the client to approve the support prompt on their computer.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SwitchListTile.adaptive(
                value: model.autoConnectEnabled,
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-connect assigned tickets'),
                subtitle: const Text(
                  'When the dashboard dispatches a RustDesk ID to this agent, the app accepts the ticket and opens the remote connection automatically.',
                ),
                onChanged: (value) => model.setAutoConnectEnabled(value),
              ),
              if (model.lastError?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 10),
                Text(
                  model.lastError!,
                  style: TextStyle(color: Colors.red[700]),
                ),
              ],
              if (assignment != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surface.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current assignment',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text('Ticket: ${assignment.ticket.ticketId}'),
                      Text('Target RustDesk ID: ${assignment.ticket.clientId}'),
                      Text('Client: ${assignment.ticket.clientLabel}'),
                      Text('Status: ${_statusLabel(assignment.ticket.status)}'),
                      if ((assignment.ticket.title ?? '').trim().isNotEmpty)
                        Text('Title: ${assignment.ticket.title}'),
                      if ((assignment.ticket.description ?? '')
                          .trim()
                          .isNotEmpty)
                        Text('Description: ${assignment.ticket.description}'),
                      if ((assignment.ticket.difficulty ?? '')
                          .trim()
                          .isNotEmpty)
                        Text(
                            'Difficulty: ${_difficultyLabel(assignment.ticket.difficulty)}'),
                      if (assignment.ticket.estimatedMinutes != null)
                        Text(
                          'Estimated: ${assignment.ticket.estimatedMinutes} min',
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: model.updatingOperationalFields
                            ? null
                            : () => _openOperationalFieldsDialog(
                                  context,
                                  model,
                                ),
                        child: Text(
                          model.updatingOperationalFields
                              ? 'Saving fields...'
                              : 'Edit difficulty and estimate',
                        ),
                      ),
                      if ((assignment.ticket.summary ?? '').trim().isNotEmpty &&
                          (assignment.ticket.title ?? '').trim().isEmpty)
                        Text('Summary: ${assignment.ticket.summary}'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (model.canAcceptAssignment)
                            ElevatedButton(
                              onPressed: model.startingAssignment
                                  ? null
                                  : () => model.acceptAndConnect(),
                              child: Text(
                                model.startingAssignment
                                    ? 'Starting...'
                                    : 'Accept and connect',
                              ),
                            ),
                          if (!model.canAcceptAssignment)
                            OutlinedButton(
                              onPressed: () => model.acceptAndConnect(),
                              child: const Text('Connect'),
                            ),
                          if (model.canResolveAssignment)
                            OutlinedButton(
                              onPressed: model.resolvingAssignment
                                  ? null
                                  : () => model.resolveAssignment(),
                              child: Text(
                                model.resolvingAssignment
                                    ? 'Resolving...'
                                    : 'Resolve ticket',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Only operator machines should have agent mode enabled. Customer machines should keep it disabled and use the support request flow instead.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[700]),
                ),
              ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ClientHelpdeskPanel extends StatefulWidget {
  const _ClientHelpdeskPanel();

  @override
  State<_ClientHelpdeskPanel> createState() => _ClientHelpdeskPanelState();
}

class _ClientHelpdeskPanelState extends State<_ClientHelpdeskPanel> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  int _handledComposerNonce = 0;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<bool> _ensureClientSupportPolicyAccepted(HelpdeskModel model,
      {bool forceShow = false}) async {
    if (!mounted) {
      return false;
    }

    if (!forceShow && model.clientSupportPolicyAccepted) {
      return true;
    }

    final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Support policy'),
              content: const SizedBox(
                width: 540,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'By requesting helpdesk support, this computer will switch to attended support mode.',
                      ),
                      SizedBox(height: 12),
                      Text(
                        'What this means:',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '1. The assigned helpdesk agent will connect using this machine RustDesk ID.',
                      ),
                      SizedBox(height: 6),
                      Text(
                        '2. You will see a confirmation prompt on this computer before the agent can control the session.',
                      ),
                      SizedBox(height: 6),
                      Text(
                        '3. You should only approve support requests from your organization helpdesk team.',
                      ),
                      SizedBox(height: 6),
                      Text(
                        '4. No permanent password needs to be shared manually with the agent.',
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Accept and continue'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!accepted) {
      return false;
    }

    await model.acknowledgeClientSupportPolicy();
    return true;
  }

  Future<void> _submit(HelpdeskModel model) async {
    final policyAccepted = await _ensureClientSupportPolicyAccepted(model);
    if (!policyAccepted) {
      return;
    }

    await model.prepareClientAttendedSupport();

    final created = await model.createTicket(
      title: _titleController.text,
      description: _descriptionController.text,
    );
    if (!created) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _titleController.clear();
      _descriptionController.clear();
    });
  }

  Future<void> _openQuickRequestDialog(HelpdeskModel model) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Request help'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'Printer issue in accounting',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText:
                          'Describe what the user needs and any visible error or blocker.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: model.creatingTicket
                  ? null
                  : () async {
                      await _submit(model);
                      if (!mounted) {
                        return;
                      }
                      if ((model.lastTicketMessage ?? '')
                          .startsWith('Ticket ')) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
              child:
                  Text(model.creatingTicket ? 'Creating...' : 'Create ticket'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HelpdeskModel>(
      builder: (context, model, child) {
        final requestedAgentMode = model.isAgentModeRequested;
        final authorizationKnown = model.isAgentAuthorizationKnown;
        final requestedButUnauthorized = requestedAgentMode &&
            authorizationKnown &&
            !model.isAgentAuthorized;
        final requestedPendingAuthorization =
            requestedAgentMode && !authorizationKnown;

        if (model.ticketComposerRequestNonce > _handledComposerNonce) {
          _handledComposerNonce = model.ticketComposerRequestNonce;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _openQuickRequestDialog(model);
            }
          });
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(13)),
            border: Border.all(color: Theme.of(context).colorScheme.surface),
          ),
          child: SingleChildScrollView(
            primary: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Request help',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'This machine is configured as a customer endpoint. It can create helpdesk tickets without exposing agent controls.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => DesktopSettingPage.switch2page(
                      SettingsTabKey.account,
                    ),
                    child: const Text('Profile'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    label: 'Mode',
                    value:
                        requestedAgentMode ? 'Client (restricted)' : 'Client',
                  ),
                  _InfoChip(
                    label: 'Name',
                    value: model.profileDisplayName.trim().isEmpty
                        ? 'Pending...'
                        : model.profileDisplayName.trim(),
                  ),
                ],
              ),
              if (requestedButUnauthorized ||
                  requestedPendingAuthorization) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    requestedButUnauthorized
                        ? 'This device requested helpdesk agent mode, but the dashboard has not authorized it as an operator. It will stay in client mode.'
                        : 'Validating whether this device is authorized as an operator. Until then, it stays in client mode.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[700]),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attended support policy',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Customer requests use attended approval. Once helpdesk is assigned from the dashboard, this computer will show a confirmation prompt before the session starts. The user should approve that prompt instead of sharing a password manually.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          label: 'Access',
                          value: 'Approve by click',
                        ),
                        _InfoChip(
                          label: 'Policy',
                          value: model.clientSupportPolicyAccepted
                              ? 'Accepted'
                              : 'Pending acceptance',
                        ),
                        OutlinedButton(
                          onPressed: () => _ensureClientSupportPolicyAccepted(
                            model,
                            forceShow: true,
                          ),
                          child: const Text('Review policy'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Printer issue in accounting',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText:
                      'Describe what the user needs and any visible error or blocker.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: model.creatingTicket
                        ? null
                        : () => _openQuickRequestDialog(model),
                    child: const Text('Quick form'),
                  ),
                  ElevatedButton(
                    onPressed:
                        model.creatingTicket ? null : () => _submit(model),
                    child: Text(
                      model.creatingTicket ? 'Creating...' : 'Create ticket',
                    ),
                  ),
                  Text(
                    'The ticket will include this machine RustDesk ID automatically.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[700]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Difficulty and estimated time are now defined by the assigned operator or the supervisor after reviewing the request.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[700]),
              ),
              if (model.lastTicketMessage?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 12),
                Text(
                  model.lastTicketMessage!,
                  style: TextStyle(
                    color: (model.lastTicketMessage ?? '').startsWith('Failed')
                        ? Colors.red[700]
                        : Colors.green[700],
                  ),
                ),
              ],
              if (model.lastError?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Text(
                  model.lastError!,
                  style: TextStyle(color: Colors.red[700]),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Customer computers should use this support request flow. Operator states such as Available, Away, or Offline only activate on devices that the dashboard explicitly authorizes as agents.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[700]),
                ),
              ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(String rawStatus) {
  switch (rawStatus) {
    case 'available':
      return 'Available';
    case 'away':
      return 'Away';
    case 'opening':
      return 'Opening';
    case 'busy':
      return 'Busy';
    case 'in_progress':
      return 'In progress';
    case 'resolved':
      return 'Resolved';
    case 'queued':
      return 'Queued';
    case 'failed':
      return 'Failed';
    case 'cancelled':
      return 'Cancelled';
    default:
      return 'Offline';
  }
}

String _difficultyLabel(String? rawDifficulty) {
  switch ((rawDifficulty ?? '').trim().toLowerCase()) {
    case 'low':
      return 'Low';
    case 'high':
      return 'High';
    case 'medium':
    default:
      return 'Medium';
  }
}

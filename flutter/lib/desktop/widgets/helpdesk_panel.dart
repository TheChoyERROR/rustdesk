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
        final assignment = model.assignment;
        final profileName = model.profileDisplayName.trim();
        final agentDisplayName = model.agent?.displayName.trim() ?? '';
        final displayName = profileName.isNotEmpty
            ? profileName
            : agentDisplayName.isNotEmpty
                ? agentDisplayName
                : model.agentId;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(13)),
            border: Border.all(color: Theme.of(context).colorScheme.surface),
          ),
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
                          'Helpdesk',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'This desktop app works as the agent console. Tickets are created from the monitoring dashboard with the target RustDesk ID.',
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
                      label: 'Agent',
                      value: displayName.isEmpty ? 'Pending...' : displayName),
                  _InfoChip(
                      label: 'ID',
                      value:
                          model.agentId.isEmpty ? 'Pending...' : model.agentId),
                  _InfoChip(
                    label: 'Server',
                    value: model.backendBaseUrl.isEmpty
                        ? 'Not configured'
                        : model.backendBaseUrl,
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
                      value: model.desiredStatus,
                      decoration: const InputDecoration(
                        labelText: 'Operator status',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'offline', child: Text('Offline')),
                        DropdownMenuItem(value: 'away', child: Text('Away')),
                        DropdownMenuItem(
                            value: 'available', child: Text('Available')),
                      ],
                      onChanged: (value) {
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
                      if ((assignment.ticket.summary ?? '').trim().isNotEmpty)
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
                  'Create tickets from the web dashboard using the target machine RustDesk ID. Agents set to Available will receive the dispatch here and, if auto-connect is enabled, the remote session will open automatically.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[700]),
                ),
              ),
            ],
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

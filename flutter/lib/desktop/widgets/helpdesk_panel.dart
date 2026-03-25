import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/models/helpdesk_model.dart';
import 'package:provider/provider.dart';

class HelpdeskPanel extends StatefulWidget {
  const HelpdeskPanel({super.key});

  @override
  State<HelpdeskPanel> createState() => _HelpdeskPanelState();
}

class _HelpdeskPanelState extends State<HelpdeskPanel> {
  final TextEditingController _summaryController = TextEditingController();

  @override
  void dispose() {
    _summaryController.dispose();
    super.dispose();
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
                          'Uses your RustDesk ID and monitoring profile. RustDesk account login is optional.',
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
                                  : () async {
                                      final started =
                                          await model.startAssignment();
                                      if (started && mounted) {
                                        connect(context,
                                            assignment.ticket.clientId);
                                      }
                                    },
                              child: Text(
                                model.startingAssignment
                                    ? 'Starting...'
                                    : 'Accept and connect',
                              ),
                            ),
                          if (!model.canAcceptAssignment)
                            OutlinedButton(
                              onPressed: () => connect(
                                context,
                                assignment.ticket.clientId,
                              ),
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
              Text(
                'Request support',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _summaryController,
                minLines: 1,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Ticket summary',
                  hintText: 'Example: Need access to accounting workstation',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: model.creatingTicket
                        ? null
                        : () async {
                            final created = await model.createTicket(
                              summary: _summaryController.text,
                            );
                            if (created && mounted) {
                              _summaryController.clear();
                            }
                          },
                    child: Text(
                      model.creatingTicket ? 'Creating...' : 'Create ticket',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      model.lastTicketMessage ??
                          'Agents marked as Available will be eligible to receive queued tickets.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[700]),
                    ),
                  ),
                ],
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http_service;
import 'package:flutter_hbb/utils/monitoring_profile.dart';

const String _kHelpdeskStatusOption = 'helpdesk-agent-status';
const String _kHelpdeskAutoConnectOption = 'helpdesk-auto-connect';
const String _kHelpdeskPolicyAcceptedVersionOption =
    'monitoring-helpdesk-policy-accepted-version';
const String _kHelpdeskPolicyVersion = '2026-04-attended-support-v1';

class HelpdeskAgentSnapshot {
  final String agentId;
  final String displayName;
  final String status;
  final String? avatarUrl;
  final String? currentTicketId;
  final DateTime? lastHeartbeatAt;
  final DateTime? updatedAt;

  const HelpdeskAgentSnapshot({
    required this.agentId,
    required this.displayName,
    required this.status,
    this.avatarUrl,
    this.currentTicketId,
    this.lastHeartbeatAt,
    this.updatedAt,
  });

  factory HelpdeskAgentSnapshot.fromJson(Map<String, dynamic> json) {
    return HelpdeskAgentSnapshot(
      agentId: (json['agent_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      avatarUrl: _optionalTrimmedString(json['avatar_url']),
      currentTicketId: _optionalTrimmedString(json['current_ticket_id']),
      lastHeartbeatAt: _parseDateTime(json['last_heartbeat_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }
}

class HelpdeskTicketSnapshot {
  final String ticketId;
  final String clientId;
  final String? clientDisplayName;
  final String? deviceId;
  final String? requestedBy;
  final String? title;
  final String? description;
  final String? difficulty;
  final int? estimatedMinutes;
  final String? summary;
  final String status;
  final String? assignedAgentId;
  final DateTime? openingDeadlineAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const HelpdeskTicketSnapshot({
    required this.ticketId,
    required this.clientId,
    this.clientDisplayName,
    this.deviceId,
    this.requestedBy,
    this.title,
    this.description,
    this.difficulty,
    this.estimatedMinutes,
    this.summary,
    required this.status,
    this.assignedAgentId,
    this.openingDeadlineAt,
    this.createdAt,
    this.updatedAt,
  });

  factory HelpdeskTicketSnapshot.fromJson(Map<String, dynamic> json) {
    return HelpdeskTicketSnapshot(
      ticketId: (json['ticket_id'] ?? '').toString(),
      clientId: (json['client_id'] ?? '').toString(),
      clientDisplayName: _optionalTrimmedString(json['client_display_name']),
      deviceId: _optionalTrimmedString(json['device_id']),
      requestedBy: _optionalTrimmedString(json['requested_by']),
      title: _optionalTrimmedString(json['title']),
      description: _optionalTrimmedString(json['description']),
      difficulty: _optionalTrimmedString(json['difficulty']),
      estimatedMinutes: _parseInt(json['estimated_minutes']),
      summary: _optionalTrimmedString(json['summary']),
      status: (json['status'] ?? '').toString(),
      assignedAgentId: _optionalTrimmedString(json['assigned_agent_id']),
      openingDeadlineAt: _parseDateTime(json['opening_deadline_at']),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  String get clientLabel {
    final displayName = clientDisplayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      return displayName;
    }
    return clientId;
  }
}

class HelpdeskAssignmentSnapshot {
  final HelpdeskTicketSnapshot ticket;
  final HelpdeskAgentSnapshot agent;

  const HelpdeskAssignmentSnapshot({
    required this.ticket,
    required this.agent,
  });

  factory HelpdeskAssignmentSnapshot.fromJson(Map<String, dynamic> json) {
    return HelpdeskAssignmentSnapshot(
      ticket: HelpdeskTicketSnapshot.fromJson(
        Map<String, dynamic>.from(json['ticket'] as Map),
      ),
      agent: HelpdeskAgentSnapshot.fromJson(
        Map<String, dynamic>.from(json['agent'] as Map),
      ),
    );
  }
}

class HelpdeskAgentAuthorizationSnapshot {
  final String agentId;
  final bool authorized;
  final String? displayName;

  const HelpdeskAgentAuthorizationSnapshot({
    required this.agentId,
    required this.authorized,
    this.displayName,
  });

  factory HelpdeskAgentAuthorizationSnapshot.fromJson(
      Map<String, dynamic> json) {
    return HelpdeskAgentAuthorizationSnapshot(
      agentId: (json['agent_id'] ?? '').toString(),
      authorized: json['authorized'] == true,
      displayName: _optionalTrimmedString(json['display_name']),
    );
  }
}

class HelpdeskModel with ChangeNotifier {
  final WeakReference<dynamic> parent;

  Timer? _presenceTimer;
  Timer? _assignmentTimer;
  Timer? _authorizationTimer;
  Timer? _composerRequestTimer;
  bool _initialized = false;
  bool _disposed = false;
  bool _syncingPresence = false;
  bool _syncingAssignment = false;
  bool _syncingAuthorization = false;
  bool _creatingTicket = false;
  bool _startingAssignment = false;
  bool _resolvingAssignment = false;

  String _desiredStatus = _normalizeDesiredStatus(
    bind.mainGetLocalOption(key: _kHelpdeskStatusOption).toString(),
  );
  bool _autoConnectEnabled = _boolOptionEnabled(
    bind.mainGetLocalOption(key: _kHelpdeskAutoConnectOption).toString(),
    defaultValue: true,
  );
  String _agentId = '';
  String _cachedAvatarInput = '';
  String? _cachedAvatarPayload;
  String? _lastError;
  String? _lastTicketMessage;
  DateTime? _lastPresenceSyncAt;
  HelpdeskAgentSnapshot? _agent;
  HelpdeskAssignmentSnapshot? _assignment;
  HelpdeskAgentAuthorizationSnapshot? _authorization;
  int _ticketComposerRequestNonce = 0;

  HelpdeskModel(this.parent);

  String get desiredStatus => _desiredStatus;
  String get effectiveStatus {
    final hasServerTicket =
        (_agent?.currentTicketId?.trim().isNotEmpty ?? false);
    if (_desiredStatus == 'offline') {
      final activeStatus = _agent?.status;
      if (hasServerTicket &&
          (activeStatus == 'opening' || activeStatus == 'busy')) {
        return activeStatus!;
      }
      if (_assignment != null) {
        if (_assignment!.ticket.status == 'opening') {
          return 'opening';
        }
        if (_assignment!.ticket.status == 'in_progress') {
          return 'busy';
        }
      }
      return 'offline';
    }

    if (_assignment != null) {
      if (_assignment!.ticket.status == 'opening') {
        return 'opening';
      }
      if (_assignment!.ticket.status == 'in_progress') {
        return 'busy';
      }
    }

    final activeStatus = _agent?.status;
    if (hasServerTicket &&
        (activeStatus == 'opening' || activeStatus == 'busy')) {
      return activeStatus!;
    }
    return _desiredStatus;
  }

  String get agentId => _agentId;
  HelpdeskAgentSnapshot? get agent => _agent;
  HelpdeskAssignmentSnapshot? get assignment => _assignment;
  HelpdeskAgentAuthorizationSnapshot? get authorization => _authorization;
  String? get lastError => _lastError;
  String? get lastTicketMessage => _lastTicketMessage;
  DateTime? get lastPresenceSyncAt => _lastPresenceSyncAt;
  bool get creatingTicket => _creatingTicket;
  bool get startingAssignment => _startingAssignment;
  bool get resolvingAssignment => _resolvingAssignment;
  bool get hasActiveAssignment => _assignment != null;
  bool get canAcceptAssignment => _assignment?.ticket.status == 'opening';
  bool get canResolveAssignment => _assignment?.ticket.status == 'in_progress';
  bool get autoConnectEnabled => _autoConnectEnabled;
  bool get isAgentModeRequested => monitoringHelpdeskAgentModeEnabled();
  bool get isAgentAuthorized => _authorization?.authorized == true;
  bool get isAgentModeEnabled => isAgentModeRequested && isAgentAuthorized;
  bool get isAgentAuthorizationKnown => _authorization != null;
  int get ticketComposerRequestNonce => _ticketComposerRequestNonce;
  String get profileDisplayName => monitoringDisplayName();
  String get backendBaseUrl => monitoringBaseUrl();
  bool get clientSupportPolicyAccepted =>
      bind.mainGetLocalOption(key: _kHelpdeskPolicyAcceptedVersionOption) ==
      _kHelpdeskPolicyVersion;

  void initialize() {
    if (_initialized || _disposed) {
      return;
    }
    _initialized = true;
    _authorizationTimer = periodic_immediate(
      const Duration(seconds: 15),
      () async => refreshAuthorization(),
    );
    _presenceTimer = periodic_immediate(
      const Duration(seconds: 10),
      () async => syncPresence(),
    );
    _assignmentTimer = periodic_immediate(
      const Duration(seconds: 5),
      () async => refreshAssignment(),
    );
    _composerRequestTimer = periodic_immediate(
      const Duration(seconds: 1),
      () async => _pollPendingTicketComposerRequest(),
    );
  }

  void disposeModel() {
    _disposed = true;
    _authorizationTimer?.cancel();
    _presenceTimer?.cancel();
    _assignmentTimer?.cancel();
    _composerRequestTimer?.cancel();
    _authorizationTimer = null;
    _presenceTimer = null;
    _assignmentTimer = null;
    _composerRequestTimer = null;
  }

  Future<void> refreshNow() async {
    await refreshAuthorization(force: true);
    await syncPresence(force: true);
    await refreshAssignment(force: true);
  }

  Future<void> onMonitoringProfileChanged() async {
    _cachedAvatarInput = '';
    _cachedAvatarPayload = null;
    _lastTicketMessage = null;
    if (!isAgentModeRequested) {
      await _deactivateAgentMode();
    }
    await syncPresence(force: true);
    await refreshAssignment(force: true);
    await refreshAuthorization(force: true);
  }

  Future<void> setAgentModeEnabled(bool enabled) async {
    final nextValue = enabled ? 'Y' : 'N';
    final currentEnabled = isAgentModeRequested;
    if (currentEnabled == enabled) {
      await onMonitoringProfileChanged();
      return;
    }

    _lastError = null;
    _lastTicketMessage = null;
    await bind.mainSetLocalOption(
      key: kMonitoringHelpdeskAgentModeOption,
      value: nextValue,
    );

    if (!enabled) {
      await _deactivateAgentMode();
    } else {
      _assignment = null;
    }

    notifyListeners();
    await refreshNow();
  }

  Future<void> setDesiredStatus(String nextStatus) async {
    final normalized = _normalizeDesiredStatus(nextStatus);
    if (_desiredStatus == normalized) {
      await refreshNow();
      return;
    }

    _desiredStatus = normalized;
    _lastError = null;
    _lastTicketMessage = null;
    await bind.mainSetLocalOption(
        key: _kHelpdeskStatusOption, value: normalized);
    notifyListeners();
    await refreshNow();
  }

  Future<void> setAutoConnectEnabled(bool enabled) async {
    if (_autoConnectEnabled == enabled) {
      return;
    }

    _autoConnectEnabled = enabled;
    await bind.mainSetLocalOption(
      key: _kHelpdeskAutoConnectOption,
      value: enabled ? 'Y' : 'N',
    );
    notifyListeners();

    if (enabled && canAcceptAssignment) {
      unawaited(acceptAndConnect());
    }
  }

  Future<void> refreshAuthorization({bool force = false}) async {
    if (_disposed || _syncingAuthorization) {
      return;
    }

    final baseUrl = monitoringBaseUrl();
    if (baseUrl.isEmpty) {
      if (force) {
        _authorization = null;
        _lastError = 'Monitoring server URL is not configured.';
        notifyListeners();
      }
      return;
    }

    _syncingAuthorization = true;
    try {
      final agentId = await _resolveAgentId();
      if (agentId.isEmpty) {
        throw Exception('RustDesk ID is not available yet.');
      }

      final response = await http_service.get(
        Uri.parse(
          '$baseUrl/api/v1/helpdesk/agents/${Uri.encodeComponent(agentId)}/authorization',
        ),
      );
      final payload = _decodeJsonBody(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_responseMessage(payload, response.body));
      }

      final authorizationJson = payload['authorization'];
      if (authorizationJson is! Map) {
        throw Exception('Authorization response is missing.');
      }

      final nextAuthorization = HelpdeskAgentAuthorizationSnapshot.fromJson(
        Map<String, dynamic>.from(authorizationJson),
      );
      final wasAuthorized = _authorization?.authorized == true;
      _authorization = nextAuthorization;

      if (isAgentModeRequested && !nextAuthorization.authorized) {
        if (wasAuthorized || _agent != null || _assignment != null) {
          await _deactivateAgentMode(notifyBackend: false);
        }
        _lastError =
            'This RustDesk ID is not authorized as a helpdesk agent in the dashboard.';
      } else if (nextAuthorization.authorized &&
          _lastError ==
              'This RustDesk ID is not authorized as a helpdesk agent in the dashboard.') {
        _lastError = null;
      }
    } catch (error) {
      if (force) {
        _lastError = 'Failed to verify helpdesk authorization: $error';
      }
    } finally {
      _syncingAuthorization = false;
      notifyListeners();
    }
  }

  Future<bool> createTicket({
    required String title,
    required String description,
    required String difficulty,
    required int estimatedMinutes,
  }) async {
    if (_creatingTicket) {
      return false;
    }

    final baseUrl = monitoringBaseUrl();
    if (baseUrl.isEmpty) {
      _lastError = 'Monitoring server URL is not configured.';
      notifyListeners();
      return false;
    }

    final trimmedTitle = title.trim();
    final trimmedDescription = description.trim();
    final trimmedDifficulty = difficulty.trim();
    if (trimmedTitle.isEmpty) {
      _lastTicketMessage = 'Please enter a title before creating the ticket.';
      notifyListeners();
      return false;
    }
    if (trimmedDescription.isEmpty) {
      _lastTicketMessage =
          'Please describe the issue before creating the ticket.';
      notifyListeners();
      return false;
    }
    if (trimmedDifficulty.isEmpty) {
      _lastTicketMessage =
          'Please choose a difficulty level before creating the ticket.';
      notifyListeners();
      return false;
    }
    if (estimatedMinutes <= 0) {
      _lastTicketMessage = 'Please enter an estimated time greater than zero.';
      notifyListeners();
      return false;
    }

    _creatingTicket = true;
    _lastError = null;
    _lastTicketMessage = null;
    notifyListeners();

    try {
      final clientId = await _resolveAgentId();
      if (clientId.isEmpty) {
        throw Exception('RustDesk ID is not available yet.');
      }

      final displayName = _displayNameOrFallback(clientId);
      final deviceId = _deviceId();
      final response = await http_service.post(
        Uri.parse('$baseUrl/api/v1/helpdesk/tickets'),
        body: jsonEncode({
          'client_id': clientId,
          'client_display_name': displayName,
          'device_id': deviceId.isEmpty ? null : deviceId,
          'requested_by': displayName,
          'summary': trimmedTitle,
          'title': trimmedTitle,
          'description': trimmedDescription,
          'difficulty': trimmedDifficulty,
          'estimated_minutes': estimatedMinutes,
        }),
      );

      final payload = _decodeJsonBody(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_responseMessage(payload, response.body));
      }

      final ticketJson = payload['ticket'];
      if (ticketJson is! Map) {
        throw Exception('Ticket response is missing.');
      }

      final ticket = HelpdeskTicketSnapshot.fromJson(
        Map<String, dynamic>.from(ticketJson),
      );
      _lastTicketMessage =
          'Ticket ${ticket.ticketId} created for ${ticket.clientLabel}. Keep RustDesk running in the background. When the assigned helpdesk agent connects, approve the support prompt on this computer.';
      return true;
    } catch (error) {
      _lastTicketMessage = 'Failed to create ticket: $error';
      return false;
    } finally {
      _creatingTicket = false;
      notifyListeners();
    }
  }

  Future<void> _pollPendingTicketComposerRequest() async {
    if (_disposed) {
      return;
    }

    final requested = bind.mainGetLocalOption(
      key: kMonitoringOpenHelpdeskRequestOption,
    );
    if (requested.trim().toUpperCase() != 'Y') {
      return;
    }

    await bind.mainSetLocalOption(
      key: kMonitoringOpenHelpdeskRequestOption,
      value: 'N',
    );
    _ticketComposerRequestNonce += 1;
    notifyListeners();
  }

  Future<void> acknowledgeClientSupportPolicy() async {
    await bind.mainSetLocalOption(
      key: _kHelpdeskPolicyAcceptedVersionOption,
      value: _kHelpdeskPolicyVersion,
    );
    notifyListeners();
  }

  Future<void> prepareClientAttendedSupport() async {
    if (isAgentModeEnabled) {
      return;
    }

    // Customer devices should rely on attended approval so agents never need
    // to request a shared password manually.
    await bind.mainSetOption(key: 'approve-mode', value: 'click');
    await bind.mainSetOption(
      key: 'verification-method',
      value: 'use-temporary-password',
    );
    await bind.mainUpdateTemporaryPassword();
  }

  Future<bool> startAssignment() async {
    if (!isAgentModeEnabled || _startingAssignment || _assignment == null) {
      return false;
    }

    final ticket = _assignment!.ticket;
    final agentId = await _resolveAgentId();
    final baseUrl = monitoringBaseUrl();
    if (agentId.isEmpty || baseUrl.isEmpty) {
      _lastError = 'Monitoring server URL or RustDesk ID is missing.';
      notifyListeners();
      return false;
    }

    _startingAssignment = true;
    _lastError = null;
    notifyListeners();

    try {
      final response = await http_service.post(
        Uri.parse(
          '$baseUrl/api/v1/helpdesk/agents/${Uri.encodeComponent(agentId)}/assignment/start',
        ),
        body: jsonEncode({'ticket_id': ticket.ticketId}),
      );
      final payload = _decodeJsonBody(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_responseMessage(payload, response.body));
      }

      final nextTicketJson = payload['ticket'];
      final nextAgentJson = payload['agent'];
      if (nextTicketJson is! Map || nextAgentJson is! Map) {
        throw Exception('Assignment start response is incomplete.');
      }

      final nextTicket = HelpdeskTicketSnapshot.fromJson(
        Map<String, dynamic>.from(nextTicketJson),
      );
      final nextAgent = HelpdeskAgentSnapshot.fromJson(
        Map<String, dynamic>.from(nextAgentJson),
      );
      _assignment =
          HelpdeskAssignmentSnapshot(ticket: nextTicket, agent: nextAgent);
      _agent = nextAgent;
      return true;
    } catch (error) {
      _lastError = 'Failed to start assignment: $error';
      return false;
    } finally {
      _startingAssignment = false;
      notifyListeners();
    }
  }

  Future<bool> acceptAndConnect() async {
    if (!isAgentModeEnabled) {
      return false;
    }
    final assignment = _assignment;
    if (assignment == null) {
      return false;
    }

    final clientId = assignment.ticket.clientId.trim();
    if (clientId.isEmpty) {
      _lastError = 'Assigned ticket is missing the target RustDesk ID.';
      notifyListeners();
      return false;
    }

    if (canAcceptAssignment) {
      final started = await startAssignment();
      if (!started) {
        return false;
      }
    }

    final context = Get.context;
    if (context == null) {
      _lastError =
          'Assignment accepted, but the app is not ready to open the remote connection yet.';
      notifyListeners();
      return false;
    }

    await connect(context, clientId);
    return true;
  }

  Future<bool> resolveAssignment() async {
    if (!isAgentModeEnabled || _resolvingAssignment || _assignment == null) {
      return false;
    }

    final ticket = _assignment!.ticket;
    final agentId = await _resolveAgentId();
    final baseUrl = monitoringBaseUrl();
    if (agentId.isEmpty || baseUrl.isEmpty) {
      _lastError = 'Monitoring server URL or RustDesk ID is missing.';
      notifyListeners();
      return false;
    }

    _resolvingAssignment = true;
    _lastError = null;
    notifyListeners();

    try {
      final nextAgentStatus = _desiredStatus == 'away' ? 'away' : 'available';
      final response = await http_service.post(
        Uri.parse(
          '$baseUrl/api/v1/helpdesk/tickets/${Uri.encodeComponent(ticket.ticketId)}/resolve',
        ),
        body: jsonEncode({
          'agent_id': agentId,
          'next_agent_status': nextAgentStatus,
        }),
      );
      final payload = _decodeJsonBody(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_responseMessage(payload, response.body));
      }

      final nextAgentJson = payload['agent'];
      if (nextAgentJson is Map) {
        _agent = HelpdeskAgentSnapshot.fromJson(
          Map<String, dynamic>.from(nextAgentJson),
        );
      }
      _assignment = null;

      if (_desiredStatus == 'offline') {
        await syncPresence(force: true);
      }
      return true;
    } catch (error) {
      _lastError = 'Failed to resolve assignment: $error';
      return false;
    } finally {
      _resolvingAssignment = false;
      notifyListeners();
    }
  }

  Future<void> syncPresence({bool force = false}) async {
    if (_disposed || _syncingPresence) {
      return;
    }

    if (isAgentModeRequested && !isAgentAuthorized) {
      await refreshAuthorization(force: force);
    }

    if (!isAgentModeEnabled) {
      if (force) {
        await _deactivateAgentMode(notifyBackend: isAgentAuthorized);
      }
      return;
    }

    final baseUrl = monitoringBaseUrl();
    if (baseUrl.isEmpty) {
      if (force) {
        _lastError = 'Monitoring server URL is not configured.';
        notifyListeners();
      }
      return;
    }

    final statusToSend = effectiveStatus;
    if (!force &&
        _desiredStatus == 'offline' &&
        statusToSend == 'offline' &&
        _assignment == null) {
      return;
    }

    _syncingPresence = true;
    try {
      final agentId = await _resolveAgentId();
      if (agentId.isEmpty) {
        throw Exception('RustDesk ID is not available yet.');
      }

      final avatarUrl = await _resolveAvatarPayload();
      final response = await http_service.post(
        Uri.parse('$baseUrl/api/v1/helpdesk/agents/presence'),
        body: jsonEncode({
          'agent_id': agentId,
          'display_name': _displayNameOrFallback(agentId),
          'avatar_url': avatarUrl,
          'status': statusToSend,
        }),
      );
      final payload = _decodeJsonBody(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_responseMessage(payload, response.body));
      }

      final agentJson = payload['agent'];
      if (agentJson is! Map) {
        throw Exception('Agent response is missing.');
      }

      _agent = HelpdeskAgentSnapshot.fromJson(
        Map<String, dynamic>.from(agentJson),
      );
      _lastPresenceSyncAt = DateTime.now();
      _lastError = null;
    } catch (error) {
      _lastError = 'Helpdesk sync failed: $error';
    } finally {
      _syncingPresence = false;
      notifyListeners();
    }
  }

  Future<void> refreshAssignment({bool force = false}) async {
    if (_disposed || _syncingAssignment) {
      return;
    }

    if (isAgentModeRequested && !isAgentAuthorized) {
      await refreshAuthorization(force: force);
    }

    if (!isAgentModeEnabled) {
      if (_assignment != null) {
        _assignment = null;
        notifyListeners();
      }
      return;
    }

    final baseUrl = monitoringBaseUrl();
    if (baseUrl.isEmpty) {
      return;
    }

    final shouldPoll = force ||
        _assignment != null ||
        _desiredStatus != 'offline' ||
        _agent?.status == 'opening' ||
        _agent?.status == 'busy';
    if (!shouldPoll) {
      return;
    }

    _syncingAssignment = true;
    try {
      final agentId = await _resolveAgentId();
      if (agentId.isEmpty) {
        return;
      }

      final previousTicketId = _assignment?.ticket.ticketId;
      final response = await http_service.get(
        Uri.parse(
          '$baseUrl/api/v1/helpdesk/agents/${Uri.encodeComponent(agentId)}/assignment',
        ),
      );
      final payload = _decodeJsonBody(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_responseMessage(payload, response.body));
      }

      final assignmentJson = payload['assignment'];
      if (assignmentJson is Map) {
        _assignment = HelpdeskAssignmentSnapshot.fromJson(
          Map<String, dynamic>.from(assignmentJson),
        );
        _agent = _assignment!.agent;
        final currentTicketId = _assignment!.ticket.ticketId;
        if (currentTicketId != previousTicketId &&
            _assignment!.ticket.status == 'opening') {
          if (_autoConnectEnabled) {
            showToast(
                'New helpdesk ticket assigned: $currentTicketId. Starting remote connection...');
            unawaited(acceptAndConnect());
          } else {
            showToast('New helpdesk ticket assigned: $currentTicketId');
          }
        }
      } else {
        final hadAssignment = previousTicketId != null;
        final previousAgent = _agent;
        _assignment = null;
        if (previousAgent != null) {
          _agent = HelpdeskAgentSnapshot(
            agentId: previousAgent.agentId,
            displayName: previousAgent.displayName,
            status: _desiredStatus,
            avatarUrl: previousAgent.avatarUrl,
            currentTicketId: null,
            lastHeartbeatAt: previousAgent.lastHeartbeatAt,
            updatedAt: previousAgent.updatedAt,
          );
        }
        if (hadAssignment) {
          await syncPresence(force: true);
        }
      }
    } catch (error) {
      _lastError = 'Failed to refresh assignment: $error';
    } finally {
      _syncingAssignment = false;
      notifyListeners();
    }
  }

  Future<String> _resolveAgentId() async {
    if (_agentId.isNotEmpty) {
      return _agentId;
    }
    _agentId = (await bind.mainGetMyId()).trim();
    return _agentId;
  }

  String _displayNameOrFallback(String fallbackId) {
    final displayName = monitoringDisplayName().trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }
    return fallbackId;
  }

  Future<String?> _resolveAvatarPayload() async {
    final avatarInput = monitoringAvatarInput().trim();
    if (avatarInput.isEmpty) {
      _cachedAvatarInput = '';
      _cachedAvatarPayload = null;
      return null;
    }
    if (_cachedAvatarInput == avatarInput) {
      return _cachedAvatarPayload;
    }
    _cachedAvatarInput = avatarInput;
    _cachedAvatarPayload =
        await resolveMonitoringAvatarPayloadFromInput(avatarInput);
    return _cachedAvatarPayload;
  }

  String _deviceId() {
    try {
      return Platform.localHostname.trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _deactivateAgentMode({bool notifyBackend = true}) async {
    _assignment = null;

    final previousAgent = _agent;
    _agent = null;
    _lastPresenceSyncAt = null;

    if (!notifyBackend) {
      notifyListeners();
      return;
    }

    final baseUrl = monitoringBaseUrl();
    if (baseUrl.isEmpty) {
      notifyListeners();
      return;
    }

    try {
      final agentId = await _resolveAgentId();
      if (agentId.isEmpty) {
        notifyListeners();
        return;
      }

      final avatarUrl = await _resolveAvatarPayload();
      final response = await http_service.post(
        Uri.parse('$baseUrl/api/v1/helpdesk/agents/presence'),
        body: jsonEncode({
          'agent_id': agentId,
          'display_name': _displayNameOrFallback(agentId),
          'avatar_url': avatarUrl,
          'status': 'offline',
        }),
      );
      final payload = _decodeJsonBody(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final agentJson = payload['agent'];
        if (agentJson is Map) {
          final nextAgent = HelpdeskAgentSnapshot.fromJson(
            Map<String, dynamic>.from(agentJson),
          );
          _agent = HelpdeskAgentSnapshot(
            agentId: nextAgent.agentId,
            displayName: nextAgent.displayName,
            status: nextAgent.status,
            avatarUrl: nextAgent.avatarUrl,
            currentTicketId: null,
            lastHeartbeatAt: nextAgent.lastHeartbeatAt,
            updatedAt: nextAgent.updatedAt,
          );
        } else if (previousAgent != null) {
          _agent = HelpdeskAgentSnapshot(
            agentId: previousAgent.agentId,
            displayName: previousAgent.displayName,
            status: 'offline',
            avatarUrl: previousAgent.avatarUrl,
            currentTicketId: null,
            lastHeartbeatAt: previousAgent.lastHeartbeatAt,
            updatedAt: previousAgent.updatedAt,
          );
        }
      }
    } catch (_) {
      if (previousAgent != null) {
        _agent = HelpdeskAgentSnapshot(
          agentId: previousAgent.agentId,
          displayName: previousAgent.displayName,
          status: 'offline',
          avatarUrl: previousAgent.avatarUrl,
          currentTicketId: null,
          lastHeartbeatAt: previousAgent.lastHeartbeatAt,
          updatedAt: previousAgent.updatedAt,
        );
      }
    } finally {
      notifyListeners();
    }
  }
}

String _normalizeDesiredStatus(String rawStatus) {
  switch (rawStatus.trim()) {
    case 'available':
      return 'available';
    case 'away':
      return 'away';
    default:
      return 'offline';
  }
}

String? _optionalTrimmedString(dynamic value) {
  final text = (value ?? '').toString().trim();
  if (text.isEmpty) {
    return null;
  }
  return text;
}

DateTime? _parseDateTime(dynamic value) {
  final text = _optionalTrimmedString(value);
  if (text == null) {
    return null;
  }
  return DateTime.tryParse(text);
}

int? _parseInt(dynamic value) {
  if (value is int) {
    return value;
  }
  final text = _optionalTrimmedString(value);
  if (text == null) {
    return null;
  }
  return int.tryParse(text);
}

bool _boolOptionEnabled(String rawValue, {required bool defaultValue}) {
  final normalized = rawValue.trim().toUpperCase();
  if (normalized.isEmpty) {
    return defaultValue;
  }
  if (normalized == 'Y' || normalized == 'TRUE' || normalized == '1') {
    return true;
  }
  if (normalized == 'N' || normalized == 'FALSE' || normalized == '0') {
    return false;
  }
  return defaultValue;
}

Map<String, dynamic> _decodeJsonBody(String rawBody) {
  if (rawBody.trim().isEmpty) {
    return <String, dynamic>{};
  }
  final decoded = jsonDecode(rawBody);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return Map<String, dynamic>.from(decoded);
  }
  return <String, dynamic>{};
}

String _responseMessage(Map<String, dynamic> payload, String fallbackBody) {
  final message = _optionalTrimmedString(payload['message']);
  if (message != null) {
    return message;
  }
  final error = _optionalTrimmedString(payload['error']);
  if (error != null) {
    return error;
  }
  final body = fallbackBody.trim();
  if (body.isNotEmpty) {
    return body;
  }
  return 'Unknown server response.';
}

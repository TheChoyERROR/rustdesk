import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/user_model.dart';

const String kMonitoringUrlEnvKey = 'RUSTDESK_MONITORING_URL';
const String kMonitoringServerUrlOption = 'monitoring-server-url';
const String kMonitoringServerLegacyOption = 'monitoring-server';
const String kMonitoringDisplayNameOption = 'monitoring-display-name';
const String kMonitoringAvatarUrlOption = 'monitoring-avatar-url';
const String kMonitoringAvatarPathOption = 'monitoring-avatar-path';
const String kMonitoringHelpdeskAgentTokenOption =
    'monitoring-helpdesk-agent-token';
const String kMonitoringHelpdeskAgentModeOption =
    'monitoring-helpdesk-agent-mode';
const String kMonitoringOpenHelpdeskRequestOption =
    'monitoring-open-helpdesk-request';
const int kMonitoringMaxLocalAvatarBytes = 2 * 1024 * 1024;

Map<String, dynamic> _localUserInfo() {
  final userInfo = UserModel.getLocalUserInfo();
  if (userInfo == null) {
    return <String, dynamic>{};
  }
  return Map<String, dynamic>.from(userInfo);
}

String monitoringDisplayName() {
  final localDisplayName = _safeBindString(
      bind.mainGetLocalOption(key: kMonitoringDisplayNameOption));
  if (localDisplayName.isNotEmpty) {
    return localDisplayName;
  }

  final userInfo = _localUserInfo();
  final userDisplayName = (userInfo['display_name'] ?? '').toString().trim();
  if (userDisplayName.isNotEmpty) {
    return userDisplayName;
  }

  final userName = (userInfo['name'] ?? '').toString().trim();
  if (userName.isNotEmpty) {
    return userName;
  }

  return '';
}

String monitoringAvatarInput() {
  final avatarUrl =
      _safeBindString(bind.mainGetLocalOption(key: kMonitoringAvatarUrlOption));
  if (avatarUrl.isNotEmpty) {
    return avatarUrl;
  }

  final avatarPath = _safeBindString(
      bind.mainGetLocalOption(key: kMonitoringAvatarPathOption));
  if (avatarPath.isNotEmpty) {
    return avatarPath;
  }

  final userInfo = _localUserInfo();
  for (final key in ['avatar_url', 'avatar_local_path', 'avatar', 'image']) {
    final value = (userInfo[key] ?? '').toString().trim();
    if (value.isNotEmpty) {
      return value;
    }
  }

  return '';
}

String monitoringBaseUrl() {
  final candidates = [
    _safeBindString(bind.mainGetEnv(key: kMonitoringUrlEnvKey)),
    _safeBindString(bind.mainGetLocalOption(key: kMonitoringServerUrlOption)),
    _safeBindString(bind.mainGetOptionSync(key: kMonitoringServerUrlOption)),
    _safeBindString(
        bind.mainGetLocalOption(key: kMonitoringServerLegacyOption)),
    _safeBindString(bind.mainGetOptionSync(key: kMonitoringServerLegacyOption)),
  ];

  final raw =
      candidates.firstWhere((value) => value.isNotEmpty, orElse: () => '');
  if (raw.isEmpty) {
    return '';
  }

  var baseUrl = raw.trim();
  if (baseUrl.endsWith('/api/v1/session-events')) {
    baseUrl =
        baseUrl.substring(0, baseUrl.length - '/api/v1/session-events'.length);
  }
  return baseUrl.replaceFirst(RegExp(r'\/+$'), '');
}

bool monitoringHelpdeskAgentModeEnabled() {
  final rawValue = _safeBindString(
    bind.mainGetLocalOption(key: kMonitoringHelpdeskAgentModeOption),
  );
  if (rawValue.isEmpty) {
    return false;
  }

  final normalized = rawValue.toUpperCase();
  return normalized == 'Y' || normalized == 'TRUE' || normalized == '1';
}

String monitoringHelpdeskAgentToken() {
  return _safeBindString(
    bind.mainGetLocalOption(key: kMonitoringHelpdeskAgentTokenOption),
  );
}

String? validateMonitoringAvatarInput(String rawInput) {
  final avatarInput = rawInput.trim();
  if (avatarInput.isEmpty) {
    return null;
  }

  final isHttpUrl = RegExp(r'^https?:\/\/\S+$', caseSensitive: false);
  final isDataImage =
      RegExp(r'^data:image\/[a-z0-9.+-]+;base64,', caseSensitive: false);
  if (isHttpUrl.hasMatch(avatarInput) || isDataImage.hasMatch(avatarInput)) {
    return null;
  }

  final normalizedPath = _normalizeAvatarPath(avatarInput);
  final file = File(normalizedPath);
  if (!file.existsSync()) {
    return 'The selected image file does not exist.';
  }

  final extension = normalizedPath.split('.').last.toLowerCase();
  if (!['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
    return 'Only JPG, PNG, or WEBP images are supported.';
  }

  final length = file.lengthSync();
  if (length > kMonitoringMaxLocalAvatarBytes) {
    return 'The image must be 2 MB or smaller.';
  }

  return null;
}

Future<String?> resolveMonitoringAvatarPayload() async {
  return resolveMonitoringAvatarPayloadFromInput(monitoringAvatarInput());
}

Future<String?> resolveMonitoringAvatarPayloadFromInput(String rawInput) async {
  final avatarInput = rawInput.trim();
  if (avatarInput.isEmpty) {
    return null;
  }

  final isHttpUrl = RegExp(r'^https?:\/\/\S+$', caseSensitive: false);
  final isDataImage =
      RegExp(r'^data:image\/[a-z0-9.+-]+;base64,', caseSensitive: false);
  if (isHttpUrl.hasMatch(avatarInput) || isDataImage.hasMatch(avatarInput)) {
    return avatarInput;
  }

  final normalizedPath = _normalizeAvatarPath(avatarInput);
  final validationError = validateMonitoringAvatarInput(normalizedPath);
  if (validationError != null) {
    debugPrint('Monitoring avatar validation failed: $validationError');
    return null;
  }

  final file = File(normalizedPath);
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    return null;
  }

  final mime = _avatarMimeType(normalizedPath);
  if (mime == null) {
    return null;
  }

  return 'data:$mime;base64,${base64Encode(bytes)}';
}

String _normalizeAvatarPath(String rawInput) {
  var normalized = rawInput.trim();
  if (normalized.startsWith('file://')) {
    normalized = normalized.substring(7);
  }
  return normalized;
}

String? _avatarMimeType(String rawPath) {
  final extension = rawPath.split('.').last.toLowerCase();
  switch (extension) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    default:
      return null;
  }
}

String _safeBindString(dynamic value) {
  return (value ?? '').toString().trim();
}

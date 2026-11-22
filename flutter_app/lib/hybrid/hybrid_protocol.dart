import 'dart:convert';
import 'package:crypto/crypto.dart';

const String kHybridProtocolVersion = '1.0.0';
const String kHybridBridgeChannelName = 'NasqoHome';

/// Strict command allowlist matching `src/hybrid/contracts.ts`.
const Set<String> kHybridAllowedCommands = <String>{
  'navigate',
  'goBack',
  'openLegacyRecovery',
  'getSnapshot',
  'changeCurrency',
  'saveUiPreferences',
  'openInvoice',
  'openVoucher',
  'openAccountStatement',
  'printDocument',
  'exportPdf',
  'pickFile',
  'showMessage',
  'saveWorkspaceSettings',
  'saveAccountGroup',
  'saveCurrency',
  'deleteCurrency',
  'saveAccount',
  'deleteAccount',
  'createLedgerEntry',
  'updateLedgerEntry',
  'setLedgerDeleted',
  'permanentlyDeleteLedger',
  'saveWarehouse',
  'createInventoryItem',
  'updateInventoryItem',
  'deleteInventoryItem',
  'importInventoryItems',
  'batchUpdateInventoryItems',
  'getInventoryMovementsReport',
  'getCashboxesReport',
  'getInvoiceDetail',
  'getProductPriceStats',
  'saveErpData',
  'backupWorkspace',
  'restoreWorkspace',
  'resetWorkspace',
  'googleDriveAction',
};

/// 17 financial/accounting write commands requiring Dart authorization,
/// mandatory `idempotencyKey`, and native write authorization.
const Set<String> kHybridFinancialMutationCommands = <String>{
  'createLedgerEntry',
  'updateLedgerEntry',
  'setLedgerDeleted',
  'permanentlyDeleteLedger',
  'saveAccount',
  'deleteAccount',
  'saveAccountGroup',
  'saveCurrency',
  'deleteCurrency',
  'saveWarehouse',
  'createInventoryItem',
  'updateInventoryItem',
  'deleteInventoryItem',
  'importInventoryItems',
  'batchUpdateInventoryItems',
  'restoreWorkspace',
  'resetWorkspace',
};

const Set<String> kHybridHostEvents = <String>{
  'snapshotUpdated',
  'routeChanged',
  'backPressed',
  'themeChanged',
  'currencyChanged',
  'uiPreferencesUpdated',
  'serviceError',
};

const Set<String> kHybridForbiddenPayloadKeys = <String>{
  'sql',
  'rawSql',
  'execSql',
  'sqliteQuery',
  'shellCommand',
  'commandLine',
  'evalCode',
  '__proto__',
  'constructor',
  'prototype',
};

bool isReactHybridV1RawMessage(String rawJson) {
  final trimmed = rawJson.trimLeft();
  if (!trimmed.startsWith('{')) return false;
  try {
    final decoded = jsonDecode(trimmed);
    return decoded is Map &&
        decoded['protocolVersion'] == kHybridProtocolVersion &&
        decoded['kind'] == 'request';
  } catch (_) {
    return false;
  }
}

String? findForbiddenPayloadKey(Object? value, {int depth = 0}) {
  if (depth > 24) return 'عمق البيانات';
  if (value == null) return null;
  if (value is List) {
    for (final item in value) {
      final hit = findForbiddenPayloadKey(item, depth: depth + 1);
      if (hit != null) return hit;
    }
    return null;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (kHybridForbiddenPayloadKeys.contains(key)) {
        return key;
      }
      final hit = findForbiddenPayloadKey(entry.value, depth: depth + 1);
      if (hit != null) return hit;
    }
  }
  return null;
}

Object? _canonicalizeValue(Object? value) {
  if (value is Map) {
    final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
    final map = <String, Object?>{};
    for (final k in sortedKeys) {
      map[k] = _canonicalizeValue(value[k]);
    }
    return map;
  }
  if (value is List) {
    return value.map(_canonicalizeValue).toList();
  }
  return value;
}

String computeCanonicalRequestHash(
    String action, Map<String, Object?> payload) {
  final canonicalJson = jsonEncode(<String, Object?>{
    'action': action,
    'payload': _canonicalizeValue(payload),
  });
  return sha256.convert(utf8.encode(canonicalJson)).toString();
}

class HybridBridgeException implements Exception {
  const HybridBridgeException(
    this.code,
    this.message, {
    this.retryable = false,
    this.details,
  });

  final String code;
  final String message;
  final bool retryable;
  final Map<String, Object?>? details;

  Map<String, Object?> toErrorJson() => <String, Object?>{
        'code': code,
        'message': message,
        'retryable': retryable,
        if (details != null) 'details': details,
      };
}

class HybridRequestEnvelope {
  const HybridRequestEnvelope({
    required this.protocolVersion,
    required this.requestId,
    required this.action,
    required this.payload,
    required this.timestampMs,
    this.idempotencyKey,
  });

  final String protocolVersion;
  final String requestId;
  final String action;
  final Map<String, Object?> payload;
  final int timestampMs;
  final String? idempotencyKey;

  static HybridRequestEnvelope parse(Object? raw) {
    Object? decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        throw const HybridBridgeException(
          'INVALID_REQUEST',
          'تعذر تحليل رسالة JSON الواردة عبر الجسر.',
        );
      }
    }

    if (decoded is! Map) {
      throw const HybridBridgeException(
        'INVALID_REQUEST',
        'الرسالة الواردة يجب أن تكون كائن JSON صالحًا.',
      );
    }

    final map = decoded.map((k, v) => MapEntry(k.toString(), v));

    if (map['protocolVersion'] != kHybridProtocolVersion) {
      throw HybridBridgeException(
        'INVALID_REQUEST',
        'إصدار البروتوكول غير مدعوم: ${map['protocolVersion']}',
      );
    }
    if (map['kind'] != 'request') {
      throw const HybridBridgeException(
        'INVALID_REQUEST',
        'نوع الرسالة يجب أن يكون request.',
      );
    }

    final requestId = map['requestId'];
    if (requestId is! String ||
        requestId.trim().length < 4 ||
        requestId.length > 128) {
      throw const HybridBridgeException(
        'INVALID_REQUEST',
        'معرف الطلب (requestId) غير صالح.',
      );
    }

    final action = map['action'];
    if (action is! String || !kHybridAllowedCommands.contains(action)) {
      throw HybridBridgeException(
        'UNAUTHORIZED_ACTION',
        'الأمر غير مصرح به في جسر Dart: $action',
      );
    }

    final rawPayload = map['payload'];
    if (rawPayload is! Map) {
      throw const HybridBridgeException(
        'VALIDATION_ERROR',
        'بيانات الطلب (payload) يجب أن تكون كائنًا.',
      );
    }

    final payload = rawPayload.map((k, v) => MapEntry(k.toString(), v));
    final forbiddenKey = findForbiddenPayloadKey(payload);
    if (forbiddenKey != null) {
      throw HybridBridgeException(
        'UNAUTHORIZED_ACTION',
        'تم رفض حقل محظور أمنيًا في الطلب: $forbiddenKey',
      );
    }

    final rawIdem = map['idempotencyKey'];
    final idempotencyKey = rawIdem is String ? rawIdem.trim() : null;
    if (kHybridFinancialMutationCommands.contains(action)) {
      if (idempotencyKey == null ||
          idempotencyKey.length < 6 ||
          idempotencyKey.length > 256) {
        throw const HybridBridgeException(
          'VALIDATION_ERROR',
          'العمليات المالية تتطلب مفتاح عدم التكرار (idempotencyKey) صالحًا.',
        );
      }
    }

    final ts = map['timestampMs'];
    final timestampMs =
        ts is num ? ts.toInt() : DateTime.now().millisecondsSinceEpoch;

    return HybridRequestEnvelope(
      protocolVersion: kHybridProtocolVersion,
      requestId: requestId.trim(),
      action: action,
      payload: payload,
      timestampMs: timestampMs,
      idempotencyKey: idempotencyKey,
    );
  }
}

class HybridResponseEnvelope {
  const HybridResponseEnvelope({
    required this.requestId,
    required this.ok,
    this.action,
    this.data,
    this.error,
    required this.timestampMs,
  });

  final String requestId;
  final String? action;
  final bool ok;
  final Object? data;
  final Map<String, Object?>? error;
  final int timestampMs;

  factory HybridResponseEnvelope.success({
    required String requestId,
    required String action,
    Object? data,
  }) =>
      HybridResponseEnvelope(
        requestId: requestId,
        action: action,
        ok: true,
        data: data,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

  factory HybridResponseEnvelope.failure({
    required String requestId,
    String? action,
    required HybridBridgeException error,
  }) =>
      HybridResponseEnvelope(
        requestId: requestId,
        action: action,
        ok: false,
        error: error.toErrorJson(),
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'protocolVersion': kHybridProtocolVersion,
        'kind': 'response',
        'requestId': requestId,
        if (action != null) 'action': action,
        'ok': ok,
        if (ok) 'data': data,
        if (!ok && error != null) 'error': error,
        'timestampMs': timestampMs,
      };

  String toJsonString() => jsonEncode(toJson());
}

class HybridHostEventEnvelope {
  const HybridHostEventEnvelope({
    required this.event,
    required this.payload,
    required this.timestampMs,
  });

  final String event;
  final Object? payload;
  final int timestampMs;

  factory HybridHostEventEnvelope.create(String event, Object? payload) {
    assert(kHybridHostEvents.contains(event));
    return HybridHostEventEnvelope(
      event: event,
      payload: payload,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  String toJsonString() => jsonEncode(<String, Object?>{
        'protocolVersion': kHybridProtocolVersion,
        'kind': 'event',
        'event': event,
        'payload': payload,
        'timestampMs': timestampMs,
      });
}

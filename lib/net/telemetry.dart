import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../platform/storage.dart';
import '../platform/web_env.dart';
import 'online_client.dart';

/// Coletor de métricas anônimas para o Laboratório de Mecânicas e funil do Ultimato.
/// Não coleta dados pessoais (PII): gera um identificador aleatório local ([clientId]) e
/// armazena um buffer local dos últimos eventos enquanto envia em lote ao servidor quando online.
class Telemetry {
  Telemetry._();

  static const String _anonKey = 'estandarte.anonId';
  static const String _bufKey = 'estandarte.metrics_buf';
  static const int _maxStoredEvents = 50;

  static String? _cachedId;
  static final List<Map<String, dynamic>> _pending = [];
  static Timer? _flushTimer;
  static bool _flushing = false;
  static String appVersion = 'alpha-1.4';

  static String get clientId {
    if (_cachedId != null && _cachedId!.isNotEmpty) return _cachedId!;
    final saved = AppStorage.instance.getString(_anonKey);
    if (saved != null && saved.length >= 12) {
      _cachedId = saved;
      return saved;
    }
    final rng = Random.secure();
    final chars = '0123456789abcdef';
    final buf = StringBuffer('u_');
    for (var i = 0; i < 24; i++) {
      buf.write(chars[rng.nextInt(16)]);
    }
    final created = buf.toString();
    _cachedId = created;
    AppStorage.instance.setString(_anonKey, created);
    return created;
  }

  static String get platformLabel {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  static void track(
    String name, {
    String? date,
    String? challengeId,
    String? mode,
    String? difficulty,
    String? doctrine,
    String? mutation,
    String? outcome,
    int? stars,
    int? rounds,
    int? durationSec,
    Map<String, dynamic>? props,
    bool immediate = false,
    bool localOnly = false,
  }) {
    final ev = <String, dynamic>{
      'name': name,
      'tsMs': DateTime.now().millisecondsSinceEpoch,
      'clientId': clientId,
      'platform': platformLabel,
      'appVersion': appVersion,
      'date': ?date,
      'challengeId': ?challengeId,
      'mode': ?mode,
      'difficulty': ?difficulty,
      'doctrine': ?doctrine,
      'mutation': ?mutation,
      'outcome': ?outcome,
      'stars': ?stars,
      'rounds': ?rounds,
      'durationSec': ?durationSec,
      if (props != null && props.isNotEmpty) 'props': props,
    };

    _appendLocalRing(ev);
    if (localOnly) return;
    _pending.add(ev);
    if (_pending.length > 100) {
      _pending.removeRange(0, _pending.length - 100);
    }

    if (immediate) {
      unawaited(flush());
    } else {
      _flushTimer ??= Timer(const Duration(seconds: 2), () {
        _flushTimer = null;
        unawaited(flush());
      });
    }
  }

  static void _appendLocalRing(Map<String, dynamic> ev) {
    try {
      final raw = AppStorage.instance.getString(_bufKey);
      final list = raw != null
          ? (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      list.add(ev);
      if (list.length > _maxStoredEvents) {
        list.removeRange(0, list.length - _maxStoredEvents);
      }
      AppStorage.instance.setString(_bufKey, jsonEncode(list));
    } catch (_) {}
  }

  static List<Map<String, dynamic>> readLocalBuffer() {
    try {
      final raw = AppStorage.instance.getString(_bufKey);
      if (raw == null) return const [];
      return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> flush() async {
    if (_flushing || _pending.isEmpty || !WebEnv.isOnline) return;
    _flushing = true;
    final batch = _pending.take(25).toList();
    try {
      await sendMetricsBatch(serverUrl(), batch);
      _pending.removeRange(0, batch.length.clamp(0, _pending.length));
    } catch (_) {
      // Silencioso se o servidor estiver dormindo ou sem rede: fica no buffer local.
    } finally {
      _flushing = false;
      if (_pending.isNotEmpty && _flushTimer == null) {
        _flushTimer = Timer(const Duration(seconds: 8), () {
          _flushTimer = null;
        });
      }
    }
  }
}

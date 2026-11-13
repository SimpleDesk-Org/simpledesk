// SimpleDesk: the server tells whether a device is active, AFK or offline, and since when
// (`POST /api/simpledesk/peer-status`). The peer cards show it as a green, yellow or grey
// dot with "AFK · seit 12 min" and the like as tooltip.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

import '../utils/http_service.dart' as http;

/// What the server said about one device.
class PeerStatus {
  /// 'active', 'afk' or 'offline'.
  final String state;

  /// Unix seconds: the last input for 'afk', when it was last seen for 'offline' (0 = never).
  final int since;

  /// When the answer came, so an old one is not shown for long.
  final DateTime received;

  PeerStatus(this.state, this.since, this.received);
}

class PeerStatusModel {
  /// Answers older than this are not used any more.
  static const _maxAge = Duration(minutes: 2);

  /// The same devices are asked for at most this often; AFK counts in minutes anyway.
  static const _minInterval = Duration(seconds: 15);

  /// The server takes at most this many IDs at once.
  static const _maxIds = 1000;

  static final Map<String, PeerStatus> _states = {};
  static var _lastIds = <String>{};
  static var _lastQuery = DateTime.fromMillisecondsSinceEpoch(0);
  static var _running = false;

  /// Counts up when new states arrive, so the dots are drawn again.
  static final RxInt revision = 0.obs;

  /// The state of [id], null if the server did not tell it lately.
  static PeerStatus? of(String id) {
    final status = _states[id];
    if (status == null ||
        DateTime.now().difference(status.received) > _maxAge) {
      return null;
    }
    return status;
  }

  /// Asks the server for the states of [ids]. Does nothing without a login; an older server
  /// without this API answers with an error, then the dots stay as they are.
  static Future<void> query(Iterable<String> ids) async {
    final wanted = ids.take(_maxIds).toSet();
    if (_running || wanted.isEmpty || !gFFI.userModel.isLogin) {
      return;
    }
    final now = DateTime.now();
    if (setEquals(wanted, _lastIds) &&
        now.difference(_lastQuery) < _minInterval) {
      return;
    }
    _running = true;
    _lastIds = wanted;
    _lastQuery = now;
    try {
      final api = await bind.mainGetApiServer();
      if (api.isEmpty) {
        return;
      }
      final headers = getHttpHeaders();
      headers['Content-Type'] = 'application/json';
      final resp = await http.post(
          Uri.parse('$api/api/simpledesk/peer-status'),
          headers: headers,
          body: jsonEncode({'ids': wanted.toList(growable: false)}));
      if (resp.statusCode != 200) {
        debugPrint('peer-status: HTTP ${resp.statusCode}');
        return;
      }
      final body = jsonDecode(decode_http_response(resp));
      if (body is! Map) {
        return;
      }
      final received = DateTime.now();
      body.forEach((id, value) {
        if (id is String && value is Map && value['state'] is String) {
          final since = value['since'];
          _states[id] =
              PeerStatus(value['state'] as String, since is int ? since : 0, received);
        }
      });
      revision.value++;
    } catch (e) {
      debugPrint('peer-status failed: $e');
    } finally {
      _running = false;
    }
  }

  /// "seit 12 min", "seit 3 h" or "seit 2 Tagen"; '' if [since] is unknown.
  static String sinceText(int since) {
    if (since <= 0) {
      return '';
    }
    final secs = DateTime.now().millisecondsSinceEpoch ~/ 1000 - since;
    final minutes = secs < 0 ? 0 : secs ~/ 60;
    if (minutes < 1) {
      return 'seit weniger als 1 min';
    }
    if (minutes < 120) {
      return 'seit $minutes min';
    }
    if (minutes < 48 * 60) {
      return 'seit ${minutes ~/ 60} h';
    }
    return 'seit ${minutes ~/ (24 * 60)} Tagen';
  }
}

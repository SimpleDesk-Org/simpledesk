// SimpleDesk: an admin assigns each device its ID in the web panel, live. Until then the
// device shows no ID, and only an admin may change an ID, after the server agreed.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

/// The rule of the server for a new ID.
final _idPattern = RegExp(r'^[a-zA-Z][\w-]{5,15}$');

/// Whether the signed-in user may change the ID of this device.
bool get canChangeId => gFFI.userModel.isLogin && gFFI.userModel.isAdmin.value;

/// [child] (ID and one-time password), or a hint while no admin has assigned the ID yet.
class IdAssignedGate extends StatefulWidget {
  final Widget child;
  const IdAssignedGate({Key? key, required this.child}) : super(key: key);

  @override
  State<IdAssignedGate> createState() => _IdAssignedGateState();
}

class _IdAssignedGateState extends State<IdAssignedGate> {
  bool _assigned = bind.mainIsIdAssigned();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // The heartbeat brings the assignment; the service answers within a second.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final assigned = bind.mainIsIdAssigned();
      if (assigned != _assigned && mounted) {
        setState(() => _assigned = assigned);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_assigned) return widget.child;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11, top: 16, bottom: 8),
      child: Text(
        'Noch keine ID. Ein Admin vergibt sie im Web-Panel.',
        style: TextStyle(color: Theme.of(context).hintColor),
      ),
    );
  }
}

/// "ID ändern" for admins: the server checks and approves the new ID, then the client
/// changes it the normal way.
void adminChangeIdDialog() {
  final controller = TextEditingController();
  var msg = '';
  var busy = false;

  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      if (busy) return;
      final newId = controller.text.trim();
      if (!_idPattern.hasMatch(newId)) {
        setState(() => msg =
            'Die ID muss mit einem Buchstaben anfangen und 6 bis 16 Zeichen lang sein: Buchstaben, Ziffern, _ und -.');
        return;
      }
      setState(() {
        msg = '';
        busy = true;
      });
      final err = await _changeId(newId);
      if (err == null) {
        close();
        return;
      }
      setState(() {
        busy = false;
        msg = err;
      });
    }

    return CustomAlertDialog(
      title: const Text('ID ändern'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'Nur Admins dürfen die ID ändern. Der Server prüft die neue ID vorher.'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            enabled: !busy,
            inputFormatters: [LengthLimitingTextInputFormatter(16)],
            decoration: InputDecoration(
              labelText: 'Neue ID',
              errorText: msg.isEmpty ? null : msg,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => submit(),
          ),
          if (busy) const LinearProgressIndicator().marginOnly(top: 12),
        ],
      ),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        dialogButton('OK', onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

/// Null when the ID is changed, otherwise the reason in plain German.
Future<String?> _changeId(String newId) async {
  try {
    final url = await bind.mainGetApiServer();
    final headers = getHttpHeaders();
    headers['Content-Type'] = 'application/json';
    final resp = await http
        .post(Uri.parse('$url/api/simpledesk/change-id'),
            headers: headers,
            body: jsonEncode({
              'id': await bind.mainGetMyId(),
              'uuid': await bind.mainGetUuid(),
              'new_id': newId,
            }))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode == 401) {
      await gFFI.userModel.reset(resetOther: true);
      return 'Deine Anmeldung ist abgelaufen. Bitte melde dich neu an.';
    }
    if (resp.statusCode != 200) {
      try {
        final body = jsonDecode(decode_http_response(resp));
        if (body is Map && body['error'] is String) {
          return body['error'] as String;
        }
      } catch (_) {}
      return 'Der Server hat die neue ID abgelehnt (HTTP ${resp.statusCode}).';
    }
  } catch (e) {
    debugPrint('change-id request failed: $e');
    return 'Server nicht erreichbar.';
  }
  bind.mainChangeId(newId: newId);
  var status = await bind.mainGetAsyncStatus();
  while (status == ' ') {
    await Future.delayed(const Duration(milliseconds: 100));
    status = await bind.mainGetAsyncStatus();
  }
  if (status.isEmpty) return null;
  if (status == 'server_not_support') {
    return 'Die ID kann nur ein Admin im Web-Panel ändern.';
  }
  return translate(status);
}

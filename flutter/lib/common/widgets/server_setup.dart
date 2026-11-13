// SimpleDesk: the client is set up once for one server, from its domain or IP address.
// Until then the home page shows only the "Server einrichten" screen.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

/// True while no server is set up.
final serverSetupNeeded = RxBool(!bind.mainIsServerSetUp());

/// [child], or the setup screen while no server is set up.
Widget serverSetupGate(Widget child) =>
    Obx(() => serverSetupNeeded.value ? const ServerSetupPage() : child);

/// [child], hidden while no server is set up (the tabs on mobile).
Widget hiddenDuringServerSetup(Widget child) =>
    Obx(() => serverSetupNeeded.value ? const SizedBox.shrink() : child);

/// Asks before "Client zurücksetzen" and says what it clears. [onDone] runs after the reset.
void resetClientDialog({VoidCallback? onDone}) {
  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      close();
      await resetClient();
      onDone?.call();
    }

    return CustomAlertDialog(
      title: const Text('Client zurücksetzen?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('Danach richtest du den Server neu ein. Gelöscht werden:'),
          SizedBox(height: 8),
          Text('• die Server-Einstellungen (Adresse, Schlüssel, Proxy)\n'
              '• deine Anmeldung\n'
              '• gespeicherte Adressbücher und Geräte\n'
              '• das permanente Passwort'),
          SizedBox(height: 8),
          Text(
              'Die ID dieses Geräts bleibt gleich, damit die IT es wiederfindet.'),
        ],
      ),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        dialogButton('Zurücksetzen',
            onPressed: submit,
            buttonStyle: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white)),
      ],
      onCancel: close,
    );
  });
}

/// Clears the server settings, the login, the cached address books and devices and the
/// permanent password, then shows the setup screen again. The device ID stays.
Future<void> resetClient() async {
  // Sign out at the old server while its address is still set.
  if (gFFI.userModel.isLogin) {
    await gFFI.userModel.logOut();
  }
  await bind.mainResetClient();
  await gFFI.userModel.reset(resetOther: true);
  bind.mainLoadRecentPeers();
  bind.mainLoadFavPeers();
  bind.mainLoadLanPeers();
  serverSetupNeeded.value = true;
}

class ServerSetupPage extends StatefulWidget {
  const ServerSetupPage({Key? key}) : super(key: key);

  @override
  State<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends State<ServerSetupPage> {
  final _controller = TextEditingController(text: bind.mainGetDefaultServer());
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await bind.mainSetUpServer(address: _controller.text);
    if (!mounted) return;
    if (res.isEmpty) {
      serverSetupNeeded.value = false;
      return;
    }
    setState(() {
      _busy = false;
      _error = _errorText(res);
    });
  }

  static String _errorText(String code) {
    switch (code) {
      case 'invalid':
        return 'Bitte gib nur eine Domain (zum Beispiel remote.example.de) oder eine IP-Adresse ein, ohne Port.';
      case 'not-allowed':
        return 'Dieser Server ist für SimpleDesk nicht freigegeben. Frag die IT nach der richtigen Adresse.';
      case 'unreachable':
        return 'Server nicht erreichbar. Prüfe die Adresse und deine Internetverbindung.';
      case 'not-simpledesk':
        return 'Das ist kein SimpleDesk-Server.';
      default:
        return 'Der Server konnte nicht eingerichtet werden.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.dns_outlined, size: 48, color: hint),
              const SizedBox(height: 16),
              Text(
                'Server einrichten',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Gib die Adresse deines SimpleDesk-Servers ein. Du bekommst sie von der IT.',
                textAlign: TextAlign.center,
                style: TextStyle(color: hint),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Server-Adresse (Domain oder IP)',
                  errorText: _error,
                  errorMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Server einrichten'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

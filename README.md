# SimpleDesk

SimpleDesk ist eine Software für Fernwartung. Sie ist ein Fork von RustDesk und steht unter derselben Lizenz (AGPL-3.0).

Der Client spricht nur mit unserem eigenen Server. Er nimmt keinen Kontakt zu Servern von RustDesk auf.

## Repos

| Repo | Inhalt |
|---|---|
| [simpledesk](https://github.com/SimpleDesk-Org/simpledesk) | Client (Flutter und Rust) |
| [simpledesk-server](https://github.com/SimpleDesk-Org/simpledesk-server) | ID-Server, Relay und Web-Panel |
| [simpledesk-common](https://github.com/SimpleDesk-Org/simpledesk-common) | Gemeinsamer Code von Client und Server (`libs/hbb_common`) |
| [simpledesk-build-deps](https://github.com/SimpleDesk-Org/simpledesk-build-deps) | Kopien von Dateien, die der Build lädt, mit sha256 |

Bibliotheken, die RustDesk angepasst hat, liegen als Forks in [SimpleDesk-Org](https://github.com/SimpleDesk-Org).

## Bauen

Der Client wird mit GitHub Actions gebaut:

- `.github/workflows/simpledesk-ci.yml`: Build und Tests unter Linux
- `.github/workflows/simpledesk-windows.yml`: Windows x86_64

## Lizenz

AGPL-3.0, siehe [LICENCE](LICENCE).
SimpleDesk beruht auf RustDesk, Copyright © Purslane Tech Pte. Ltd. und die Mitwirkenden von RustDesk.

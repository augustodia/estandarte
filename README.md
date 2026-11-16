# Ultimato

Jogo de estratégia de conquista de territórios para jogar entre celulares, tablets e PCs: na mesma rede, sem servidor, ou online. Cliente em **Flutter** (Web + Windows/Linux nativos), com as regras num motor único em Go compartilhado com o servidor (`backend-estandarte`).

> **Sobre o nome:** o jogo se chamava Estandarte. O nome que o jogador vê agora é **Ultimato**; os repositórios, o pacote Dart (`estandarte`), o endereço do GitHub Pages e as chaves de armazenamento continuam com o nome antigo por enquanto, para não quebrar links nem partidas salvas.

## Quartel

Toda partida usa o **Quartel**, um sistema próprio de medalhas e ordens:

- **Medalhas:** a 1ª conquista do turno dá 1, fechar um continente dá +1 e eliminar alguém dá +2. Cada jogador guarda no máximo 6, e todos veem as medalhas de todos.
- **Mobilização** (3 medalhas, sempre disponível): rende o *esforço de guerra*, 4 exércitos na rodada 2 e mais 1 a cada rodada.
- **Ordens táticas:** 3 ficam abertas para todos; cada jogador compra no máximo uma por turno e outra entra no lugar da comprada. São elas: ponte aérea (2), trincheira (2), sabotagem (2), espionagem (6) e, em partidas com ogiva, a ogiva (4).
- **Espionagem:** não entrega o objetivo do adversário. Dá um relatório com dois objetivos possíveis, um verdadeiro e um falso, que só quem comprou lê.

O extra **Cartas no lugar do Quartel**, na sala, troca tudo isso por cartas de território. As regras do Quartel ficam em `estandarte-engine/game/hq.go`.

## Arquitetura

- **Motor de regras compartilhado em Go ([estandarte-engine](https://github.com/augustodia/estandarte-engine), pasta irmã `../estandarte-engine`):**
  - **Flutter Web:** compilado para WebAssembly (`GOOS=js GOARCH=wasm` em `web/engine/estandarte.wasm` + `web/engine/wasm_exec.js`) a partir de `../estandarte-engine/cmd/wasm` e chamado via `dart:js_interop` em `lib/engine/game_engine_web.dart`.
  - **Windows Desktop nativo (sem precisar de `gcc`):** compilado em Go puro (`CGO_ENABLED=0`, `./cmd/rpc` -> `native/estandarte_engine_rpc.exe`) e conectado por socket TCP local (`ws2_32.dll` em `lib/engine/game_engine_native.dart`). Caso `gcc` (MinGW-w64) esteja instalado no `PATH`, `build_engine.ps1 -Native` também compila a biblioteca C compartilhada (`native/estandarte_engine.dll` via `./cmd/ffi`), que tem prioridade automática por FFI direto.
  - **Linux / macOS nativo:** compilável como biblioteca compartilhada C (`c-shared`, `EstandarteCall` / `EstandarteFree` em `../estandarte-engine/cmd/ffi/main.go`) e chamada via `dart:ffi` em `lib/engine/game_engine_native.dart`.
- **Geometria do mapa (`assets/map_geo.json`):** gerada uma vez a partir dos 42 territórios, 6 continentes e rotas marítimas originais (`CustomPainter` em `lib/ui/map_view.dart` com pan/zoom/pinch, relevo direcional, marcações que compensam o zoom, rótulos sem colisão e animação de ogiva/combate).
- **Névoa radioativa (`lib/game/smoke_sim.dart`):** porta da simulação *Stable Fluids* (Jos Stam) em grade, projeção de pressão, confinamento de vorticidade, expansão térmica, fluxo de ruído em duas fases, partículas, arcos elétricos, ondas de choque e interação por toque (`poke`).
- **Multiplayer e Áudio (`lib/net/`, `lib/platform/`):**
  - Cliente online WebSocket/HTTP compatível com `backend-estandarte` (`?sala=`, Salas públicas, timer, espectadores, reconexão automática).
  - Na versão **Web**, também inclui Áudio sintetizado por Web Audio API, Rede local P2P WebRTC sem servidor via QR code + conexão reserva automática em IndexedDB, leitor de QR por câmera (`BarcodeDetector` / `web/vendor/jsQR.js`) e trava de rotação em telas pequenas.
  - Em **Windows/Linux nativo**, o motor de regras e o modo Online/Local com bots já funcionam; WebRTC P2P, câmera QR e áudio seguem isolados via conditional imports para futura integração nativa.

## Pré-requisitos e estrutura local

Coloque o repositório do motor ao lado de `estandarte`:

```
estandarte/               # pasta raiz
├── estandarte/           # este repositório (branch Flutter)
├── estandarte-engine/    # motor Go compartilhado (github.com/augustodia/estandarte-engine)
├── backend-estandarte/   # opcional: servidor online
└── go.work               # opcional: workspace Go na raiz
```

## Rodar no VS Code (`F5`) — compilação automática do motor

Os arquivos `.vscode/launch.json` e `.vscode/tasks.json` (tanto na raiz quanto dentro de `estandarte/`) já estão configurados:

- **`Estandarte (Web - Chrome)`**, **`Estandarte (Web - Edge)`** e **`Estandarte (Web Server - 8080)`**: executam automaticamente o `preLaunchTask` **`Engine: Build WASM`** antes de subir o Flutter.
- **`Estandarte (Windows Desktop)`**: executa **`Engine: Build Native (Windows DLL)`** e o `windows/CMakeLists.txt` também aciona `tool/build_engine.ps1 -Native` automaticamente em qualquer `flutter run -d windows` / `flutter build windows`, copiando `estandarte_engine_rpc.exe` (e `estandarte_engine.dll`, se existir) para junto do `estandarte.exe`.

> **Importante:** no Windows Desktop, basta ter **Go**, **Flutter** e **Visual Studio (Desktop development with C++)** — não é necessário instalar `gcc`/MinGW porque `estandarte_engine_rpc.exe` é compilado com `CGO_ENABLED=0`.

## Como compilar o motor Go manualmente

### WebAssembly (Flutter Web)

No Windows (PowerShell):

```powershell
.\tool\build_engine.ps1
```

No Linux/macOS:

```bash
./tool/build_engine.sh
```

### Nativo (Windows / Linux / macOS)

Windows (`estandarte_engine_rpc.exe` sem `gcc`, mais `estandarte_engine.dll` se `gcc` estiver no `PATH`):

```powershell
.\tool\build_engine.ps1 -Native
```

Linux/macOS (requer compilador C para `c-shared`):

```bash
./tool/build_engine.sh --native
```

## Rodar e testar no terminal

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web
flutter build windows --debug
```

Testes do motor Go (no repositório irmão):

```powershell
go -C ..\estandarte-engine test ./...
```

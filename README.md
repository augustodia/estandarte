# Estandarte (Branch `Flutter`)

Reescrita completa do cliente **Estandarte** em **Flutter** (Web + estrutura pronta para Windows e Linux nativos) mantendo **100% de compatibilidade** de regras e protocolo com o servidor Go (`backend-estandarte`).

## Arquitetura

- **Motor de regras compartilhado em Go (`engine/game` + `engine/bridge`):**
  - **Flutter Web:** compilado para WebAssembly (`GOOS=js GOARCH=wasm` em `web/engine/estandarte.wasm` + `web/engine/wasm_exec.js`) e chamado via `dart:js_interop` em `lib/engine/game_engine_web.dart`.
  - **Windows / Linux / Desktop nativo:** compilável como biblioteca compartilhada C (`c-shared`, `EstandarteCall` / `EstandarteFree` em `engine/cmd/ffi/main.go`) e chamada via `dart:ffi` em `lib/engine/game_engine_native.dart`.
- **Geometria do mapa (`assets/map_geo.json`):** gerada uma vez a partir dos 42 territórios, 6 continentes e rotas marítimas originais (`CustomPainter` em `lib/ui/map_view.dart` com pan/zoom/pinch, relevo direcional, marcações que compensam o zoom, rótulos sem colisão e animação de ogiva/combate).
- **Névoa radioativa (`lib/game/smoke_sim.dart`):** porta da simulação *Stable Fluids* (Jos Stam) em grade, projeção de pressão, confinamento de vorticidade, expansão térmica, fluxo de ruído em duas fases, partículas, arcos elétricos, ondas de choque e interação por toque (`poke`).
- **Multiplayer e Áudio (`lib/net/`, `lib/platform/`):**
  - Cliente online WebSocket/HTTP compatível com `backend-estandarte` (`?sala=`, Salas públicas, timer, espectadores, reconexão automática).
  - Na versão **Web**, também inclui Áudio sintetizado por Web Audio API, Rede local P2P WebRTC sem servidor via QR code + conexão reserva automática em IndexedDB, leitor de QR por câmera (`BarcodeDetector` / `vendor/jsQR.js`) e trava de rotação em telas pequenas.
  - Em **Windows/Linux nativo**, o motor de regras por FFI e as interfaces de plataforma já estão isolados via conditional imports, prontos para ligar pacotes nativos futuros (ex.: `flutter_webrtc` e áudio nativo).

## Como compilar o motor Go

### WebAssembly (Flutter Web)

No Windows (PowerShell):

```powershell
.\tool\build_engine.ps1
```

No Linux/macOS:

```bash
./tool/build_engine.sh
```

### Biblioteca nativa (Windows / Linux) — requer compilador C (`gcc`/`clang`/MinGW)

```powershell
.\tool\build_engine.ps1 -Native
```

```bash
./tool/build_engine.sh --native
```

## Rodar e testar o app Flutter

```bash
flutter pub get
flutter analyze
flutter test
flutter build web
```

Testes do motor Go:

```bash
go -C engine test ./...
```

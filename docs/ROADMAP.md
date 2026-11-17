# Roadmap do Ultimato — Estado Atual vs. Próximos Passos

Este documento consolida a evolução do **Ultimato** nos três repositórios ([estandarte](file:///f:/Projetos/estandarte/estandarte), [backend-estandarte](file:///f:/Projetos/estandarte/backend-estandarte) e [estandarte-engine](file:///f:/Projetos/estandarte/estandarte-engine)).

---

## Resumo Executivo: O que já temos pronto hoje

| Frente | Status | Onde está no código |
| :--- | :--- | :--- |
| **Identidade "Ultimato" + UI Tática** | **Concluído** | `lib/ui/theme.dart`, `home_screen.dart`, `rooms_screen.dart`, `lobby_screen.dart`, `game_screen.dart` |
| **Motor de regras unificado em Go (`estandarte-engine`)** | **Concluído** | Compartilhado entre backend online, WASM Web e RPC Windows |
| **Quartel + Espionagem 2.0 + Cartas opcionais** | **Concluído** | `estandarte-engine/game/hq.go` e `quartel_modal.dart` |
| **Tutorial jogável (5 passos no mapa)** | **Concluído** | `startTutorial` em `app_controller.dart` |
| **Partida Rápida + Salas Online + Senha + Host LAN & Relay (`#CODE`)** | **Concluído** | `backend-estandarte/internal/server/` (`room.go`, `relay.go`, `hub.go`) e `app_controller.dart` |
| **Desafio Diário + Quinta Histórica + Ranking do Dia** | **Concluído (Modo Aberto)** | `daily.go`, `daily_challenge.dart`, `daily_screen.dart`, `game_screen.dart` |
| **Laboratório de Mecânicas + Telemetria (Dia 1)** | **Estrutura pronta** | `metrics.go` (`MetricsSink`), `lib/net/telemetry.dart` e `backend-estandarte/docs/METRICS.md` |

---

## Fase 1 — Identidade, Desafios Diários e Laboratório de Mecânicas

### Já implementado
- [x] Rebrand **Ultimato**, tema visual Grand Strategy e atalho unificado de **Mesa Local** (com criação e entrada por IP/QR no mesmo fluxo).
- [x] **Host Relay por código de 5 letras (`?relay=1`) + Host LAN (`dart:io`) + Senha opcional** nas salas.
- [x] **Desafios Diários & Crônica Histórica das Quintas-feiras sincronizados com o servidor (`/daily`)**:
  - Quintas-feiras rotacionam **10 Crônicas Históricas canônicas** (*Dia D 1944*, *Batalha da Grã-Bretanha 1940*, *Corredor dos Estreitos 1453*, *Ilhas do Pacífico 1942*, *Virada no Volga 1942*, *Coalizão Continental 1805*, *Portões das Termópilas 480 a.C.*, *Travessia dos Alpes 218 a.C.*, *Armada do Índico 1509*, *Crise dos Mísseis 1962*).
  - Demais dias da semana geram desafios táticos com temas próprios por dia (*Ofensiva Relâmpago*, *Operação Assimetria*, *Equilíbrio de Quartel*, *Cerco & Contra-Ataque / Teatro Instável*, *Operação Pinça*, *Grande Campanha*), **7 clusters iniciais**, **7 Doutrinas**, **7 Mutações**, 4 arquétipos de objetivo, modo **Marechal** e sistema de **1–3 Estrelas**, **Códice Histórico** e **Meta Semanal flexível (4/7 dias)**.
- [x] **Ranking Diário sincronizado (`/daily/start`, `/daily/submit`, `/daily/ranking`)** + relatório tático copiável.
- [x] **Métricas anônimas do Laboratório de Mecânicas desde o Dia 1**:
  - Cliente (`Telemetry.track`) e servidor (`MetricsSink` / `MemoryRingSink` + `/metrics` + `/metrics/summary` + `METRICS_LOG=1`) prontos sem exigir banco acoplado agora. Ver detalhes em [backend-estandarte/docs/METRICS.md](file:///f:/Projetos/estandarte/backend-estandarte/docs/METRICS.md).

### O que falta nesta fase
- [ ] Ligar `MetricsSink` a um armazenamento persistente (PostgreSQL / ClickHouse / Axiom) quando quiser guardar histórico de longo prazo além da janela em RAM / logs.
- [ ] Proteger `GET /metrics/summary` com chave administrativa antes de escalar tráfego público.
- [ ] Registro formal da marca **Ultimato** (INPI).

---

## Fase 2 — Criação de Contas, Persistência e "Fila Nunca Vazia"

> [!IMPORTANT]
> **Política atual dos Desafios & Ranking (Aberto para testes):**
> Por enquanto, o **Desafio Diário, Quinta Histórica e Ranking** operam **abertos sem login/conta** (usando apelido + identificador anônimo local `estandarte.anonId`) para facilitar testes rápidos, validação de mecânicas e coleta de dados do Laboratório.
> **Ao implementar Criação de Contas**, os endpoints de desafio e ranking devem passar a exigir **sessão autenticada (usuário logado)** para:
> - pontuar no Ranking oficial e evitar duplicidade/spoof de nomes;
> - sincronizar Códice Histórico, Estrelas e Meta Semanal entre dispositivos (PC Windows, Web e celular);
> - vincular recompensas cosméticas permanentes (brasões/insígnias de Quintas Históricas) à conta.

### O que falta fazer nesta fase
- [ ] **Banco de dados no Backend (PostgreSQL ou SQLite/Turso):**
  - Persistir ranking diário/histórico permanente, progresso do Códice, contas e partidas assíncronas sobrevivendo a deploys/restarts do Render.
- [ ] **Criação de Contas + Autenticação (Google / Apple / E-mail + migração de convidado):**
  - Vincular `clientId` (`estandarte.anonId`) existente à nova conta na primeira autenticação sem perder o Códice já conquistado.
  - Exigir token autenticado em `/daily/submit`, matchmaking ranqueado e futuras mecânicas competitivas/cosméticas.
- [ ] **Modo por Correspondência (Assíncrono — 24h por turno)** e **Lista de Amigos / Emotes Táticos**.

---

## Fase 3 — Competitivo, Fair Play e Replays

- [ ] **Dados Verificáveis (*Provably Fair* — Commit-Reveal)** com publicação de hash da semente.
- [ ] **Filas Ranqueadas (1v1 e FFA 3–6) com TrueSkill / Glicko-2 e Patentes**.
- [ ] **Replays determinísticos compartilháveis** (aproveitando que `estandarte-engine` é reproduzível a partir de `seed + setup + actions`).
- [ ] **Ranking Global & Sazonal das Quintas Históricas** (somando estrelas acumuladas por temporada entre jogadores logados).

---

## Fase 4 — Monetização Ética (Sem Pay-to-Win, Sem Loot Box)

- [ ] **Pacote único "Comandante"** (estatísticas avançadas, replays ilimitados, regras extras/mapas extras).
- [ ] **Cosméticos diretos via Pix** (skins de peças, temas de mapa, efeitos de Ogiva/Ponte Aérea) e **Passe de Temporada cosmético**.

---

## Fase 5 — Expansão, Novos Mapas e Lojas Nativas

- [ ] **Múltiplos mapas** (24 territórios Blitz, 42 clássico, 60 geopolítico).
- [ ] **Modos extras:** Névoa de Guerra (*Fog of War*) e 2v2 em duplas.
- [ ] **Publicação nas lojas:** Google Play, App Store e Steam (`audio`/`sound_native`).

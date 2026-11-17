# Roadmap do Ultimato — Estado Atual vs. Próximos Passos

Este documento consolida a evolução do **Ultimato** nos três repositórios ([estandarte](file:///f:/Projetos/estandarte/estandarte), [backend-estandarte](file:///f:/Projetos/estandarte/backend-estandarte) e [estandarte-engine](file:///f:/Projetos/estandarte/estandarte-engine)). Atualizado em 17/11/2026.

---

## Resumo Executivo: O que já temos pronto hoje

| Frente | Status | Onde está no código |
| :--- | :--- | :--- |
| **Identidade "Ultimato" + UI Tática** | **Concluído** | `lib/ui/theme.dart`, `home_screen.dart`, `rooms_screen.dart`, `lobby_screen.dart`, `game_screen.dart` |
| **Motor de regras unificado em Go (`estandarte-engine`)** | **Concluído** | Compartilhado entre backend online, WASM Web e RPC Windows |
| **Quartel + Espionagem 2.0 + Cartas opcionais** | **Concluído** | `estandarte-engine/game/hq.go` e `quartel_modal.dart` |
| **Tutorial jogável (5 passos no mapa)** | **Concluído** | `startTutorial` em `app_controller.dart` |
| **Partida Rápida + Salas Online + Senha + Host LAN & Relay (`#CODE`)** | **Concluído** | `backend-estandarte/internal/server/` (`room.go`, `relay.go`, `hub.go`) e `app_controller.dart` |
| **Desafio Diário + Quinta Histórica + Ranking do Dia** | **Concluído (ranking das contas, no banco)** | `daily.go`, `daily_store.go`, `daily_challenge.dart`, `daily_screen.dart`, `game_screen.dart` |
| **Contas (e-mail confirmado, nome único, esqueci a senha)** | **Concluído** | `backend-estandarte/internal/accounts/`, `account_http.go`, `lib/net/account_api.dart`, `lib/ui/account_sheet.dart` |
| **Banco de dados (Postgres no Neon)** | **Concluído** | Contas, sessões, códigos, ranking do dia e progresso (`internal/accounts/pg.go`, `daily_store.go`) |
| **Progresso do desafio na conta** | **Concluído** | Estrelas por dia, meta semanal e Códice: `/account/progress` e `syncProgress` em `app_controller.dart` |
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
- [ ] Ligar `MetricsSink` ao Postgres (já existe) para guardar o histórico além da janela em RAM / logs.
- [x] `GET /metrics/summary` só com a chave de administrador `METRICS_KEY`.
- [ ] Registro formal da marca **Ultimato** (INPI).

---

## Fase 2 — Criação de Contas, Persistência e "Fila Nunca Vazia"

> [!IMPORTANT]
> **Política atual:** online (partida rápida, salas, assistir, mesa por código pela internet) e o **ranking do
> desafio** exigem conta. O nome online é sempre o **nome de usuário da conta** (único; o servidor impõe). Mesa
> local, rede de casa e QR seguem sem conta, com nome livre. O desafio pode ser jogado sem conta, mas só entra no
> ranking com ela.

### Já implementado
- [x] **Banco de dados (Postgres no Neon, grátis):** contas, sessões, códigos de e-mail, ranking do dia (`daily_entries`) e progresso (`account_progress`), sobrevivendo a deploys/restarts do Render.
- [x] **Contas por e-mail:** cadastro com e-mail confirmado por código (Brevo), nome de usuário único (ignora maiúsculas, acentos e letras parecidas), entrar por e-mail ou nome, trocar nome e e-mail, **esqueci a senha / trocar senha** por código.
- [x] **Migração de convidado:** ao entrar numa conta pela primeira vez, as estrelas, a meta semanal e o Códice jogados como convidado vão para a conta (fica o melhor de cada dia/crônica) e passam a valer em qualquer aparelho.
- [x] `/daily/submit` exige token: o ranking é das contas (selo de verificado com e-mail confirmado).

### O que falta fazer nesta fase
- [ ] **Entrar com Google / Apple** (menos atrito no cadastro).
- [ ] **Modo por Correspondência (Assíncrono — 24h por turno)** e **Lista de Amigos / Emotes Táticos**.
- [ ] Recompensas cosméticas permanentes (brasões/insígnias das Quintas Históricas) ligadas à conta.

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

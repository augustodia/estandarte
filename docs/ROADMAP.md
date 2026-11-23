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
- [x] Métricas no Postgres: eventos por 90 dias, contagem diária sem prazo e teto para não encher o banco grátis.
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
- [x] **Correspondência (24 h por jogada):** partidas de dias, guardadas no Postgres (`async_games`), com e-mail de
  "sua vez", prazo vencido passando a vez e bot assumindo depois de três prazos seguidos. Lista própria (sua vez,
  vez dos outros, sala de espera, encerradas), convite por link `?partida=CÓDIGO`.
- [x] **Início reorganizado pelo ritmo:** AGORA (partida rápida e salas), NO SEU TEMPO (correspondência) e NA MESA
  (local, sem internet); conta num selo no canto, tutorial e regras no rodapé.

### O que falta fazer nesta fase
- [ ] **Entrar com Google / Apple** (menos atrito no cadastro).
- [x] **Amigos:** pedir amizade pelo nome de usuário, ver quem está jogando ou com o jogo aberto, desafiar por
  correspondência com um toque e convidar amigos da sala de espera (convite na lista e por e-mail).
- [x] **Emotes táticos:** oito recados prontos (sem texto livre, nada a moderar) nas partidas online, por
  correspondência, na rede de casa e no relay; um a cada 3 s, quem assiste só vê, e dá para silenciar os dos outros.
- [ ] Notificação no aparelho (push) além do e-mail de "sua vez".
- [x] **Brasões das Quintas Históricas:** cada crônica dá um brasão (arte própria) no metal da melhor campanha
  (bronze, prata, ouro) e três insígnias marcam a coleção. A conta escolhe um para aparecer ao lado do nome na sala,
  na partida, nos amigos e no ranking; o servidor confere contra o Códice da conta.

---

## Fase 3 — Competitivo, Fair Play e Replays

- [x] **Dados verificáveis (commit-reveal):** compromisso SHA-256 da semente no começo, contribuição de cada jogador na
  chave dos dados, semente revelada no fim; o app confere e refaz a partida.
- [x] **Desafio verificável:** as regras e as estrelas do desafio rodam no motor; o app joga com a semente que o
  servidor entrega e manda a partida gravada; o servidor refaz e grava o resultado *dele* no ranking e no Códice (só
  a campanha conferida libera brasão). Limite: o app conhece a semente, então um app alterado pode prever os dados.
- [x] **Fila ranqueada — Duelo (1v1):** Glicko-2, patentes de Recruta a Marechal, temporadas de 2 meses (nota puxada
  para o meio na virada), regras fixas (turno de 60 s, Quartel e eventos, sem ogivas e sem pactos), sem espectadores e
  sem bots. Abandono (sair, cair por mais de 90 s, 3 prazos seguidos, não aparecer) perde por desistência do servidor
  e dá castigo na fila (5 min → 30 min → 24 h). Contas com e-mail confirmado e mais de 24 h; mesma rede não se enfrenta.
- [ ] **Batalha ranqueada (FFA de 4)**, quando houver demanda na fila (amigos/mesmo IP nunca na mesma mesa).
- [x] **Replays compartilháveis** das partidas online e por correspondência (`?replay=CÓDIGO`, 60 dias): tocar, pausar,
  passo a passo, de turno em turno e em 1×, 2× ou 4×.
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

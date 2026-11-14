# Estandarte

Jogo de estratégia por turnos para 2 a 6 jogadores: distribua exércitos, conquiste territórios e cumpra seu objetivo secreto antes dos outros. Roda no navegador do celular (iOS e Android) como PWA instalável e **não tem backend**: os aparelhos se conectam direto entre si por WebRTC, pareados por QR code.

**Jogar:** https://augustodia.github.io/estandarte/

## Como conectar os aparelhos

1. O anfitrião toca em **Criar partida** e depois em **Convidar por QR**.
2. O convidado abre o jogo, toca em **Entrar em partida** e lê o QR do anfitrião (a câmera do celular também abre o link).
3. O celular do convidado mostra um QR de resposta; o anfitrião aponta a câmera para ele (a leitura é automática).

   O segundo QR existe porque uma conexão WebRTC precisa de dados dos dois lados (endereço e impressão digital do certificado de cada aparelho). Sem servidor para levar a resposta de volta, ela volta pela câmera.
4. Repita para cada convidado e toque em **Iniciar partida**.

Quando o navegador pedir a câmera, permita. Além de ler os QR codes, a permissão faz o navegador informar o IP local real do aparelho; sem ela ele usa um nome mDNS que outros celulares da rede nem sempre resolvem, e a conexão não abre.

Também dá para jogar várias pessoas no mesmo aparelho e completar a mesa com bots.

Os bots leem o próprio objetivo e o tabuleiro: priorizam os continentes de que precisam, defendem as fronteiras dos que já têm, distribuem o reforço por várias frentes, calculam a chance real de cada ataque (tabela exata dos dados) e param antes de se esvaziar. Com pactos ligados, propõem e avaliam propostas.

### Reconexão

**Volta automática, sem QR.** Enquanto um convidado está conectado, o anfitrião deixa pronta uma conexão reserva para ele: o convidado guarda um certificado fixo no aparelho e os dois combinam, pelo canal que já existe, as credenciais da próxima conexão. Se o convidado cair (tela bloqueada, página recarregada, Wi-Fi oscilou), ele abre essa reserva sozinho em poucos segundos e volta para o mesmo lugar. A cada volta uma nova reserva é combinada. Isso não funciona quando o anfitrião reinicia o jogo, quando a rede dele muda ou em navegadores que não aceitam a técnica; nesses casos vale o QR, como abaixo.

Se um convidado cair (tela bloqueada, app fechado, página recarregada), o anfitrião vê o botão **Reconectar** na barra do jogo e gera um novo QR. O convidado toca em **Reconectar à partida** na tela inicial, lê o QR e volta para o mesmo lugar, com suas cartas e seu objetivo. O anfitrião também pode trocar um jogador ausente por um bot no menu ☰, e retomar uma partida salva pela tela inicial.

### Estabilidade da conexão

- O convidado repete o "olá" inicial até o anfitrião responder, porque a primeira mensagem pode se perder se chegar antes de o canal abrir do outro lado.
- O anfitrião pergunta a cada 3 s se cada convidado está vivo. Quem fica 9 s sem responder aparece como "sem resposta", sem ser derrubado: se a rede voltar, o aviso some sozinho. O convidado faz o mesmo em relação ao anfitrião.
- Cada pergunta leva o número da última jogada. Se o convidado estiver defasado, pede o estado de novo; o mesmo acontece ao desbloquear a tela ou voltar para o app.
- Se não houver nenhuma rede (nem Wi-Fi, nem hotspot), o convite avisa em vez de gerar um QR que nunca conectaria.

### Sem internet

Depois do primeiro acesso o jogo fica em cache (a tela inicial mostra "Pronto para jogar sem internet") e não precisa mais de rede externa: basta todos estarem no mesmo Wi-Fi ou no hotspot de um dos celulares.

- No iPhone, o app instalado na tela de início e o Safari têm caches separados. Sem internet, abra o app instalado e use **Entrar em partida** em vez da câmera do sistema.
- Redes com isolamento entre clientes (comum em Wi-Fi público) bloqueiam a conexão direta.
- Em redes diferentes a conexão depende de STUN público e pode falhar em algumas operadoras de 4G/5G. Não há servidor TURN.

## Regras em resumo

- **Reforço:** metade dos seus territórios em exércitos (mínimo 3) + bônus de continentes dominados por inteiro.
- **Ataque:** a partir da 2ª rodada, até 3 dados contra até 3 da defesa; empate favorece a defesa.
- **Cartas:** conquistou no turno, ganha uma carta; 3 iguais ou 3 diferentes viram exércitos (4, 6, 8, 10, 12, 15, +5…). Com 5 cartas a troca é automática no início do turno; com menos, um botão troca a melhor trinca com um toque.
- **Remanejamento:** ao fim do turno, cada exército pode andar uma vez para um território vizinho seu.
- **Vitória:** cumprir o objetivo secreto (dominar continentes, somar territórios ou eliminar uma cor).
- **Equilíbrio por número de jogadores:** a meta de "somar territórios" é 24 (ou 18 com 2 exércitos em cada) com 4 a 6 jogadores, 29 (ou 23) com 3 e 32 (ou 26) com 2. Na distribuição inicial, quem joga depois na ordem recebe exércitos a mais (10 por posição com 2 jogadores, 4 com 3, 1 com 4 a 6), para compensar a vantagem de atacar primeiro. Valores ajustados em milhares de partidas simuladas.

O mapa é simplificado de propósito: Europa, América Central e as ilhas da Ásia e da Oceania são ampliadas, arquipélagos viram blocos únicos e ilhotas e baías pequenas somem, para tudo ficar fácil de ver e tocar. No celular, o mapa fica melhor com o aparelho deitado; use pinça para dar zoom e arraste para mover. Cada território fica na cor de quem o domina; cada continente é contornado por uma linha na sua cor, afastada da costa, e separado dos vizinhos por um canal escuro.

## Regras extras (opcionais)

Ligadas pelo anfitrião na sala, na seção recolhível **Regras extras**, antes de começar. Desligadas, a partida é a clássica.

- **Eventos de rodada:** da 2ª rodada em diante, de vez em quando uma rodada começa com um evento surpresa, que vale para todos até ela acabar. Depois de um evento vem sempre ao menos uma rodada calma; em rodada calma a chance de sair um novo é de 45%, nunca passam mais de 3 calmas seguidas e o mesmo evento não sai duas vezes seguidas. Os eventos: Tempestade (no máximo 2 dados contra um continente), Cessar-fogo (um continente não pode ser atacado; nenhum dos dois cai num continente inteiro de um só jogador), Mar revolto (rotas marítimas fechadas), Recrutamento (+2 no reforço), Escassez (−2 no reforço, mínimo 3), Trincheiras (+1 no maior dado da defesa) e Ofensiva (+1 no maior dado do ataque). O evento em vigor fica ao lado do anel de jogada.
- **Pactos:** na sua vez, toque em **Propor pacto** na barra de baixo e escolha o jogador. Proponha a outro jogador um pacto de não agressão de 2 rodadas (uma proposta por turno). O outro responde na hora, mesmo fora da vez. Enquanto o pacto vale, o jogo recusa ataques entre os dois. Cada jogador só pode ter um pacto por vez, e os mesmos dois esperam 2 rodadas depois do fim para fazer outro. Romper antes só no início do próprio turno, antes de reforçar, ao custo de metade do reforço daquele turno (no mínimo 3), e todos são avisados. Com dois jogadores em jogo os pactos acabam.
- **Ogiva nuclear:** no reforço, em vez de trocar 3 cartas por exércitos, o jogador pode lançar a ogiva em qualquer território inimigo.
  - O alvo perde o dobro do que a troca valeria (troca de 8 destrói 16), sempre sobrando 1 exército, e não muda de dono. Não há sorteio.
  - Quem lança entrega as 3 cartas, recebe 75% dos exércitos da troca e joga o resto do turno normalmente (reforça, ataca em outros lugares, remaneja).
  - O território atingido fica radioativo, sob névoa, até a vez voltar a quem lançou: ninguém pode atacá-lo, nem quem lançou. O dono joga normalmente (reforça, ataca a partir dele, recebe o bônus do continente). Quando a névoa some, quem lançou é o primeiro a poder atacar ali.
  - Só existe uma névoa no mapa por vez.
  - A primeira troca de cada jogador é sempre normal e, depois de uma ogiva, a troca seguinte dele também.
  - O lançamento ocupa um degrau da escada de trocas (4, 6, 8, 10, 12, 15, +5…): a próxima troca de qualquer jogador vale o degrau seguinte.
  - O pacto de quem lança acaba na hora; não se lança contra parceiro de pacto nem em continente sob Cessar-fogo.
  - Com 5 cartas e direito à ogiva, a troca continua obrigatória, mas o jogo deixa escolher em vez de trocar sozinho. Se o tempo acabar, faz a troca normal.
  - Bots lançam quando o que destroem cobre com folga a parte da troca de que abrem mão, de preferência contra a pilha vizinha que mais os ameaça.
  - O lançamento é uma cena para todos: alarme e borda vermelha, a câmera enquadra a rota, o míssil sobe de um território de quem lançou e desce sobre o alvo com rastro de fumaça, e a explosão acontece em câmera lenta (cerca de 4 s até o impacto). Os bots esperam a cena acabar.
  - A névoa é uma simulação de fluido de verdade (`js/smoke.js`): advecção, projeção de pressão, vorticidade e expansão térmica numa grade pequena, com relevo iluminado, brilho do solo, partículas levadas pelo escoamento e descargas elétricas. Roda num canvas 2D comum, entre a camada do terreno e a dos marcadores, e baixa a qualidade sozinha em aparelho fraco. A explosão tem mira de chegada, clarão, bola de fogo, onda de choque que empurra os marcadores vizinhos e fagulhas.
  - Essas regras saíram de um laboratório com cerca de 480 mil partidas simuladas e 46 variações. Duas conclusões guiaram a escolha: proibir quem lança de atacar no turno torna a ogiva um mau negócio em qualquer configuração (ficar um turno sem atacar custa mais do que a troca), e limitar o dano a uma fração do alvo também. Na versão adotada, quem tem a ogiva vence de 3% a 9% mais do que quem não tem, e ela aparece cerca de 2 vezes por partida.

## Controles

- **Reforço:** toque num território seu, ajuste a quantidade com − e + (ou "Máx") e toque em "Colocar". Tocar de novo no mesmo território soma 1.
- **Ataque:** toque direto no inimigo (a origem passa a ser o seu vizinho com mais exércitos) ou toque antes na origem; linhas mostram os alvos possíveis. Escolha de 1 a 3 dados com − e + e toque em "Atacar", ou toque de novo no alvo. "Auto" repete o ataque com o máximo de dados até conquistar ou não poder mais.
- **Conquista e remanejamento:** − e + definem quantos exércitos mover.
- **Sempre deitado:** durante a partida a tela fica deitada mesmo com o celular em pé (ela gira 90° e você vira o aparelho); o mapa ocupa a tela e os controles ficam numa faixa no rodapé. Dá para voltar ao modo automático no menu ☰.

Encerrar os ataques e encerrar o turno pedem confirmação numa janela, para um toque sem querer não passar a vez.

## O que cada um vê durante a partida

- **Alertas no centro da tela** (somem em 1 s) só para o que é seu: "Sua vez!", "Ataque!", "Remanejamento", "Conquistou!". O que os outros fazem aparece num aviso pequeno no topo, sem cobrir o mapa.
- **Anel de jogada:** no canto inferior esquerdo do mapa. Cada fatia é um jogador, na ordem em que jogam (sentido horário a partir do topo; uma seta aponta para o meio da fatia de quem joga agora). Todas têm a mesma espessura; o comprimento de cada uma segue o número de territórios. O aro de fora é o relógio do turno, com o tempo no centro. Tocar no anel abre a lista de jogadores.
- **Vitória:** uma tela cheia na cor do vencedor, com confete, o nome dele, o objetivo que cumpriu e a classificação final; ao fechar, o mapa mostra só o domínio do vencedor aceso.
- **Destaque da jogada alheia:** o território que o jogador da vez selecionou (ou onde um bot acabou de agir) fica aceso e o resto do mapa esmaece.
- **Ações ao vivo:** quem espera vê o território que o jogador da vez selecionou e o alvo que ele está mirando, além de reforços (+N), setas de ataque e de movimento, perdas (−N) e os dados.
- **Tremor e vibração:** o mapa treme a cada ataque (mais forte em conquistas) e o aparelho vibra para atacante e defensor. A vibração depende do navegador: funciona no Android; o Safari do iPhone não oferece essa função.
- **Sons:** cada ação tem um efeito (reforço, dados, ataque, conquista, perda, sua vez, relógio acabando, vitória). Dá para desligar no menu ☰. No iPhone, a chave de silencioso também cala os sons.
- **Tempo por turno:** o anfitrião escolhe na sala (livre, 1, 2 ou 3 min). O aro do anel mostra o tempo; nos últimos 10 s ele fica vermelho e avisa. Ao zerar, os reforços restantes são colocados automaticamente e o turno passa. O relógio pausa enquanto o anfitrião reconecta alguém.

## Arquitetura

Sem build e sem dependências em tempo de execução além de duas bibliotecas de QR embutidas em `vendor/`.

| Arquivo | Papel |
| --- | --- |
| `js/game.js` | Motor de regras puro (estado serializável, `apply(estado, jogador, ação)`), visão filtrada por jogador e bot |
| `js/map.js` | Mapa-múndi: 42 territórios em 6 continentes (9, 4, 7, 6, 12 e 4), fronteiras e rotas marítimas (gerado) |
| `js/sound.js` | Efeitos sonoros sintetizados (Web Audio), sem arquivos de áudio |
| `tools/gen-map.mjs` | Gera `js/map.js` a partir do Natural Earth 1:110m: recorta os territórios, amplia regiões pequenas e simplifica as formas numa grade |
| `js/net.js` | WebRTC DataChannel e compactação do SDP para caber no QR |
| `js/main.js` | Interface, pareamento, câmera/leitor de QR, pan e zoom do mapa |
| `sw.js` | Cache offline |

O anfitrião é a autoridade: valida as ações, rola os dados e envia a cada convidado apenas o que ele pode ver (mãos e objetivos alheios ficam ocultos). Toda jogada é transacional: se for inválida, ou se deixasse o jogo num estado que quebra alguma regra (ataque na primeira rodada, território sem exército, cartas duplicadas, vez de jogador eliminado…), ela é recusada e nada muda.

## Desenvolvimento

```sh
python3 -m http.server 8765   # abra http://localhost:8765
node test/engine.test.mjs     # 300 partidas entre bots + 140 mil jogadas ao acaso checando as regras
```

Câmera e service worker exigem HTTPS (ou `localhost`).

## Créditos de terceiros

- Geografia: [Natural Earth](https://www.naturalearthdata.com/) (domínio público), via [world-atlas](https://github.com/topojson/world-atlas)
- [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) — MIT
- [jsQR](https://github.com/cozmo/jsQR) — Apache-2.0 (`vendor/jsQR.LICENSE`)

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

O mapa é simplificado de propósito: Europa, América Central e as ilhas da Ásia e da Oceania são ampliadas, arquipélagos viram blocos únicos e ilhotas e baías pequenas somem, para tudo ficar fácil de ver e tocar. No celular, o mapa fica melhor com o aparelho deitado; use pinça para dar zoom e arraste para mover. Cada território fica na cor de quem o domina; cada continente é contornado por uma linha na sua cor, afastada da costa, e separado dos vizinhos por um canal escuro.

## Regras extras (opcionais)

Ligadas pelo anfitrião na sala, antes de começar. Desligadas, a partida é a clássica.

- **Eventos de rodada:** da 2ª rodada em diante, de vez em quando uma rodada começa com um evento surpresa, que vale para todos até ela acabar. Depois de um evento vem sempre ao menos uma rodada calma; em rodada calma a chance de sair um novo é de 45%, nunca passam mais de 3 calmas seguidas e o mesmo evento não sai duas vezes seguidas. Os eventos: Tempestade (no máximo 2 dados contra um continente), Cessar-fogo (um continente não pode ser atacado), Mar revolto (rotas marítimas fechadas), Recrutamento (+2 no reforço), Escassez (−2 no reforço, mínimo 3), Trincheiras (+1 no maior dado da defesa) e Ofensiva (+1 no maior dado do ataque). O evento em vigor fica ao lado do anel de jogada.
- **Pactos:** na sua vez, proponha a outro jogador um pacto de não agressão de 3 rodadas (uma proposta por turno). O outro responde na hora, mesmo fora da vez. Enquanto o pacto vale, o jogo recusa ataques entre os dois. Romper antes só no início do próprio turno, ao custo de 3 exércitos do reforço, e todos são avisados. Com dois jogadores em jogo os pactos acabam.

## Controles

- **Reforço:** toque num território seu, ajuste a quantidade com − e + (ou "Máx") e toque em "Colocar". Tocar de novo no mesmo território soma 1.
- **Ataque:** toque direto no inimigo (a origem passa a ser o seu vizinho com mais exércitos) ou toque antes na origem; linhas mostram os alvos possíveis. Escolha de 1 a 3 dados com − e + e toque em "Atacar", ou toque de novo no alvo. "Auto" repete o ataque com o máximo de dados até conquistar ou não poder mais.
- **Conquista e remanejamento:** − e + definem quantos exércitos mover.
- **Sempre deitado:** durante a partida a tela fica deitada mesmo com o celular em pé (ela gira 90° e você vira o aparelho); o mapa ocupa a tela e os controles ficam numa faixa no rodapé. Dá para voltar ao modo automático no menu ☰.

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

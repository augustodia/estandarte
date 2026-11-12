# Estandarte

Jogo de estratégia por turnos para 2 a 6 jogadores: distribua exércitos, conquiste territórios e cumpra seu objetivo secreto antes dos outros. Roda no navegador do celular (iOS e Android) como PWA instalável e **não tem backend**: os aparelhos se conectam direto entre si por WebRTC, pareados por QR code.

**Jogar:** https://augustodia.github.io/estandarte/

## Como conectar os aparelhos

1. O anfitrião toca em **Criar partida** e depois em **Convidar por QR**.
2. O convidado abre o jogo, toca em **Entrar em partida** e lê o QR do anfitrião (a câmera do celular também abre o link).
3. O celular do convidado mostra um QR de resposta; o anfitrião toca em **Ler resposta** e aponta para ele.
4. Repita para cada convidado e toque em **Iniciar partida**.

Quando o navegador pedir a câmera, permita. Além de ler os QR codes, a permissão faz o navegador informar o IP local real do aparelho; sem ela ele usa um nome mDNS que outros celulares da rede nem sempre resolvem, e a conexão não abre.

Também dá para jogar várias pessoas no mesmo aparelho e completar a mesa com bots.

### Reconexão

Se um convidado cair (tela bloqueada, app fechado, página recarregada), o anfitrião vê o botão **Reconectar** na barra do jogo e gera um novo QR. O convidado toca em **Reconectar à partida** na tela inicial, lê o QR e volta para o mesmo lugar, com suas cartas e seu objetivo. O anfitrião também pode trocar um jogador ausente por um bot no menu ☰, e retomar uma partida salva pela tela inicial.

### Sem internet

Depois do primeiro acesso o jogo fica em cache (a tela inicial mostra "Pronto para jogar sem internet") e não precisa mais de rede externa: basta todos estarem no mesmo Wi-Fi ou no hotspot de um dos celulares.

- No iPhone, o app instalado na tela de início e o Safari têm caches separados. Sem internet, abra o app instalado e use **Entrar em partida** em vez da câmera do sistema.
- Redes com isolamento entre clientes (comum em Wi-Fi público) bloqueiam a conexão direta.
- Em redes diferentes a conexão depende de STUN público e pode falhar em algumas operadoras de 4G/5G. Não há servidor TURN.

## Regras em resumo

- **Reforço:** metade dos seus territórios em exércitos (mínimo 3) + bônus de continentes dominados por inteiro.
- **Ataque:** a partir da 2ª rodada, até 3 dados contra até 3 da defesa; empate favorece a defesa.
- **Cartas:** conquistou no turno, ganha uma carta; 3 iguais ou 3 diferentes viram exércitos (4, 6, 8, 10, 12, 15, +5…).
- **Remanejamento:** ao fim do turno, cada exército pode andar uma vez para um território vizinho seu.
- **Vitória:** cumprir o objetivo secreto (dominar continentes, somar territórios ou eliminar uma cor).

No celular, o mapa fica melhor com o aparelho deitado; use pinça para dar zoom e arraste para mover.

## Arquitetura

Sem build e sem dependências em tempo de execução além de duas bibliotecas de QR embutidas em `vendor/`.

| Arquivo | Papel |
| --- | --- |
| `js/game.js` | Motor de regras puro (estado serializável, `apply(estado, jogador, ação)`), visão filtrada por jogador e bot |
| `js/map.js` | Mapa-múndi: 46 territórios, 6 continentes, fronteiras e rotas marítimas (gerado) |
| `tools/gen-map.mjs` | Gera `js/map.js` a partir do Natural Earth 1:110m |
| `js/net.js` | WebRTC DataChannel e compactação do SDP para caber no QR |
| `js/main.js` | Interface, pareamento, câmera/leitor de QR, pan e zoom do mapa |
| `sw.js` | Cache offline |

O anfitrião é a autoridade: valida as ações, rola os dados e envia a cada convidado apenas o que ele pode ver (mãos e objetivos alheios ficam ocultos).

## Desenvolvimento

```sh
python3 -m http.server 8765   # abra http://localhost:8765
node test/engine.test.mjs     # simula 300 partidas entre bots e checa invariantes
```

Câmera e service worker exigem HTTPS (ou `localhost`).

## Créditos de terceiros

- Geografia: [Natural Earth](https://www.naturalearthdata.com/) (domínio público), via [world-atlas](https://github.com/topojson/world-atlas)
- [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) — MIT
- [jsQR](https://github.com/cozmo/jsQR) — Apache-2.0 (`vendor/jsQR.LICENSE`)

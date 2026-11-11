# Estandarte

Jogo de estratégia por turnos para 2 a 6 jogadores: distribua exércitos, conquiste territórios e cumpra seu objetivo secreto antes dos outros. Roda no navegador do celular (iOS e Android) como PWA instalável e **não tem backend**: os aparelhos se conectam direto entre si por WebRTC, pareados por QR code.

**Jogar:** https://augustodia.github.io/estandarte/

## Como conectar os aparelhos

1. Um jogador toca em **Criar partida** e depois em **Convidar por QR**.
2. O convidado aponta a câmera para o QR (ou usa **Entrar em partida** dentro do app).
3. O celular do convidado mostra um QR de resposta; o anfitrião toca em **Ler resposta** e aponta para ele.
4. Repita para cada convidado e toque em **Iniciar partida**.

Também dá para jogar várias pessoas no mesmo aparelho e completar a mesa com bots.

Dicas de rede:

- Funciona melhor com todos no mesmo Wi-Fi ou no hotspot de um dos celulares (não precisa de internet depois de o app estar instalado/em cache).
- Em redes diferentes a conexão depende de STUN público e pode falhar atrás de NAT simétrico (4G/5G de algumas operadoras). Não há servidor TURN.
- Mantenha a tela ligada. Se alguém cair, o anfitrião abre ☰ e gera um novo QR para aquele jogador.
- A partida fica salva no aparelho do anfitrião e pode ser retomada pela tela inicial.

## Regras em resumo

- **Reforço:** metade dos seus territórios em exércitos (mínimo 3) + bônus de continentes dominados por inteiro.
- **Ataque:** a partir da 2ª rodada, até 3 dados contra até 3 da defesa; empate favorece a defesa.
- **Cartas:** conquistou no turno, ganha uma carta; 3 iguais ou 3 diferentes viram exércitos (4, 6, 8, 10, 12, 15, +5…).
- **Remanejamento:** ao fim do turno, cada exército pode andar uma vez para um território vizinho seu.
- **Vitória:** cumprir o objetivo secreto (dominar continentes, somar territórios ou eliminar uma cor).

## Arquitetura

Sem build e sem dependências em tempo de execução além de duas bibliotecas de QR embutidas em `vendor/`.

| Arquivo | Papel |
| --- | --- |
| `js/game.js` | Motor de regras puro (estado serializável, `apply(estado, jogador, ação)`), visão filtrada por jogador e bot |
| `js/map.js` | Mapa: 42 territórios, 6 continentes, adjacências e rotas marítimas |
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

- [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) — MIT
- [jsQR](https://github.com/cozmo/jsQR) — Apache-2.0 (`vendor/jsQR.LICENSE`)

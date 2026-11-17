# Sistema visual: Centro de Operações

O mapa tem cor; a interface não. A cor de matiz é das facções. A interface é grafite neutro e tem um único tom de ação.

## Regras

- **Um botão claro por tela.** `EstButtonVariant.primary` (osso, `AppColors.action`) é sempre a próxima jogada. O resto é contorno (`normal`), texto (`ghost`) ou perigo (`warn`).
- **Sem dourado na interface.** O amarelo é de uma facção. O metal (`AppColors.medal`) só aparece em medalhas e no Quartel.
- **Sem degradê e sem brilho de bisel.** Superfícies são chapadas. A única sombra é `AppColors.edgeShadows`, para o que flutua sobre o mapa (janelas, cartões soltos).
- **Exército = insígnia.** Cada facção tem forma e cor (`Factions`): triângulo, círculo, quadrado, losango, hexágono, cruz. A forma resolve daltonismo e leitura com o mapa afastado.
- **Celular deitado primeiro.** `estCompact(context)` (lado menor < 500) reduz botões (36/30), cabeçalhos de janela (44) e linhas (44).

## Tokens (`lib/ui/theme.dart`)

| Papel | Token | Valor |
|---|---|---|
| Fundo | `AppColors.deep` | `#0B0F14` |
| Painel | `AppColors.panel` | `#12171E` |
| Ativo / hover | `AppColors.panel2` | `#1A2029` |
| Linha | `AppColors.line` | `#262E39` |
| Contorno de controle | `AppColors.glassBorder` | `#3A4452` |
| Texto | `ink` / `mute` / `faint` | `#E8ECF1` / `#9AA4B2` / `#7D8796` |
| Ação | `AppColors.action` | `#F2EEE6` |
| Medalha | `AppColors.medal` | `#C9A45C` |
| Perigo | `AppColors.bad` | `#FF6B5E` |
| Ogiva | `AppColors.rad` | `#C8FF3E` |

Facções (exibição, `lib/core/palette.dart`): `#E0483E` `#3D7FE3` `#2E9E62` `#E9B530` `#8E5BD6` `#9AA6B4`.

**Tipos:** Barlow Condensed (títulos, rótulos em caixa alta, números tabulares) e Barlow (texto). Escala: 11 · 12 · 13 · 15 · 18 · 22 · 28. Use `AppText.title`, `AppText.label` e `AppText.number`.

**Raios:** 2 (selos, etiquetas), 4 (controles), 8 (painéis), em `Radii`. **Espaço:** múltiplos de 4, em `Space`.

## Fotos das telas

O CI fotografa início, sala, partida e janelas em 844×390, 1280×800 e 390×844 a cada push fora da `main` e publica na branch `ci-screens` (`shots/<branch>/`). Para rodar local: copie a biblioteca nativa do motor para `native/` e rode `SCREENS=1 flutter test test/screens_test.dart`.

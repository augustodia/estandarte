/// Cores de exibição das facções, na ordem do motor (Vermelho, Azul, Verde, Amarelo, Roxo, Cinza).
///
/// O motor continua mandando as cores dele em `constants.colors`; o aplicativo troca só o tom exibido, para que as
/// facções se separem também em claridade (daltonismo) e não briguem com a interface. As insígnias de cada facção
/// ficam em `ui/theme.dart` (`Factions`).
const factionDisplayHex = ['#E0483E', '#3D7FE3', '#2E9E62', '#E9B530', '#8E5BD6', '#9AA6B4'];

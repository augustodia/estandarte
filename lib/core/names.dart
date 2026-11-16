// Clean user-entered names and prevent duplicate or homoglyph-spoofed names,
// matching backend-estandarte / original js/names.js semantics.

final _stripCtrlRe = RegExp(
  r'[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF\uFFFD]',
);
final _leadingMarkRe = RegExp(r'^[\u0300-\u036F]+');
final _multiSpaceRe = RegExp(r'\s+');
final _alphaNumRe = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _botLikeRe = RegExp(r'^bot\d*$');

const Map<String, String> _fold = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'а': 'a', 'α': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'е': 'e', 'ε': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'і': 'i', 'ι': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'о': 'o', 'ο': 'o', '0': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'υ': 'u',
  'ç': 'c', 'с': 'c',
  'ñ': 'n',
  'ý': 'y', 'у': 'y',
  'р': 'p', 'ρ': 'p',
  'х': 'x', 'χ': 'x',
  'ј': 'j',
  'ѕ': 's',
  'ԁ': 'd',
  'κ': 'k',
  'ν': 'v',
  'τ': 't',
  'һ': 'h',
  'ԛ': 'q',
  'ԝ': 'w',
};

String cleanName(String? value, [int maxLen = 14]) {
  var s = value ?? '';
  s = s.replaceAll(_stripCtrlRe, '');
  s = s.replaceAll(_leadingMarkRe, '');
  s = s.replaceAll(_multiSpaceRe, ' ').trim();
  final runes = s.runes.toList();
  if (runes.length <= maxLen) return s;
  return String.fromCharCodes(runes.take(maxLen)).trim();
}

String nameKey(String? value) {
  final lower = (value ?? '').toLowerCase();
  final buf = StringBuffer();
  for (final r in lower.runes) {
    final ch = String.fromCharCode(r);
    final mapped = _fold[ch] ?? ch;
    if (_alphaNumRe.hasMatch(mapped)) {
      buf.write(mapped);
    }
  }
  return buf.toString();
}

String uniqueName<T>(
  String? rawName,
  List<T> seats,
  String Function(T seat) getName, {
  T? self,
  bool isBot = false,
}) {
  var name = rawName ?? '';
  final k = nameKey(name);
  if (name.isEmpty || k.isEmpty || (!isBot && _botLikeRe.hasMatch(k))) {
    name = 'Convidado';
  }
  bool taken(String candidate) {
    final ck = nameKey(candidate);
    return seats.any((s) => !identical(s, self) && nameKey(getName(s)) == ck);
  }

  if (!taken(name)) return name;
  final baseRunes = name.runes.toList();
  for (var i = 2;; i++) {
    final suf = ' $i';
    final takeCount = (14 - suf.length).clamp(0, baseRunes.length);
    final base = String.fromCharCodes(baseRunes.take(takeCount)).trim();
    final candidate = '$base$suf';
    if (!taken(candidate)) return candidate;
  }
}

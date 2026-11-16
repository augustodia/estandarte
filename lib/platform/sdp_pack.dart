import 'dart:convert';
import 'dart:typed_data';

const int _maxCands = 5;

String b64uEncode(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

Uint8List b64uDecode(String s) {
  var norm = s.replaceAll('-', '+').replaceAll('_', '/');
  while (norm.length % 4 != 0) {
    norm += '=';
  }
  return base64Decode(norm);
}

String packSdp({required String type, required String sdp}) {
  final fpMatch = RegExp(r'a=fingerprint:sha-256 ([0-9A-Fa-f:]+)').firstMatch(sdp);
  final ufragMatch = RegExp(r'a=ice-ufrag:(\S+)').firstMatch(sdp);
  final pwdMatch = RegExp(r'a=ice-pwd:(\S+)').firstMatch(sdp);
  if (fpMatch == null || ufragMatch == null || pwdMatch == null) {
    throw FormatException('SDP sem os campos esperados');
  }
  final fp = fpMatch.group(1)!;
  final ufrag = ufragMatch.group(1)!;
  final pwd = pwdMatch.group(1)!;

  final setupRaw = RegExp(r'a=setup:(\w+)').firstMatch(sdp)?.group(1) ?? 'actpass';
  final setup = const {'actpass': 'p', 'active': 'a', 'passive': 's'}[setupRaw] ?? 'p';

  final cands = <({int rank, String c})>[];
  final seen = <String>{};
  final candRe = RegExp(r'a=candidate:\S+ 1 (\w+) \d+ (\S+) (\d+) typ (\w+)');
  for (final m in candRe.allMatches(sdp)) {
    final proto = m.group(1)!.toLowerCase();
    final ip = m.group(2)!;
    final port = m.group(3)!;
    final typ = m.group(4)!;
    if (proto != 'udp' || (typ != 'host' && typ != 'srflx')) continue;
    if (RegExp(r'^fe80:', caseSensitive: false).hasMatch(ip)) continue;
    final v6 = ip.contains(':');
    final mdns = ip.endsWith('.local');
    final rank = typ == 'host' ? (mdns ? 2 : (v6 ? 3 : 0)) : (v6 ? 4 : 1);
    final c = '${typ[0]},$ip,$port';
    if (seen.add(c)) {
      cands.add((rank: rank, c: c));
    }
  }
  cands.sort((a, b) => a.rank.compareTo(b.rank));

  final fpBytes = fp.split(':').map((h) => int.parse(h, radix: 16)).toList();
  final fpB = b64uEncode(fpBytes);
  final candStr = cands.take(_maxCands).map((e) => e.c).join(';');
  return ['1', '${type[0]}$setup', ufrag, pwd, fpB, candStr].join('~');
}

({String type, String sdp}) unpackSdp(String code) {
  final parts = code.trim().split('~');
  if (parts.length < 5) {
    throw FormatException('Código inválido');
  }
  final v = parts[0];
  final ts = parts[1];
  final ufrag = parts[2];
  final pwd = parts[3];
  final fpB = parts[4];
  final cs = parts.length > 5 ? parts[5] : '';
  if (v != '1' || fpB.isEmpty || ts.length < 2) {
    throw FormatException('Código inválido');
  }
  final type = ts[0] == 'o' ? 'offer' : 'answer';
  final setup = const {'p': 'actpass', 'a': 'active', 's': 'passive'}[ts[1]];
  if (setup == null) {
    throw FormatException('Código inválido');
  }
  final fp = b64uDecode(fpB)
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
  final lines = <String>[
    'v=0',
    'o=- 4611731400430051336 2 IN IP4 127.0.0.1',
    's=-',
    't=0 0',
    'a=group:BUNDLE 0',
    'm=application 9 UDP/DTLS/SCTP webrtc-datachannel',
    'c=IN IP4 0.0.0.0',
    'a=ice-ufrag:$ufrag',
    'a=ice-pwd:$pwd',
    'a=fingerprint:sha-256 $fp',
    'a=setup:$setup',
    'a=mid:0',
    'a=sctp-port:5000',
    'a=max-message-size:262144',
  ];
  if (cs.isNotEmpty) {
    final cands = cs.split(';');
    for (var i = 0; i < cands.length; i++) {
      final seg = cands[i].split(',');
      if (seg.length < 3) continue;
      final t = seg[0];
      final ip = seg[1];
      final port = seg[2];
      lines.add(
        t == 'h'
            ? 'a=candidate:${i + 1} 1 udp ${2122260223 - i} $ip $port typ host'
            : 'a=candidate:${i + 1} 1 udp ${1686052607 - i} $ip $port typ srflx raddr 0.0.0.0 rport 0',
      );
    }
    lines.add('a=end-of-candidates');
  }
  return (type: type, sdp: '${lines.join('\r\n')}\r\n');
}

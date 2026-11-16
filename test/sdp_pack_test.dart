import 'package:estandarte/platform/sdp_pack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('packSdp and unpackSdp roundtrip essential WebRTC fields and candidates', () {
    const sampleOffer = '''
v=0
o=- 12345 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0
m=application 9 UDP/DTLS/SCTP webrtc-datachannel
c=IN IP4 0.0.0.0
a=ice-ufrag:abcd1234
a=ice-pwd:secretPassword0123456789
a=fingerprint:sha-256 00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF
a=setup:actpass
a=mid:0
a=candidate:1 1 udp 2122260223 192.168.1.42 54321 typ host
a=candidate:2 1 udp 1686052607 203.0.113.9 54321 typ srflx raddr 0.0.0.0 rport 0
a=candidate:3 1 udp 100 fe80::1 54321 typ host
''';

    final packed = packSdp(type: 'offer', sdp: sampleOffer);
    expect(packed.startsWith('1~op~abcd1234~'), true);
    expect(packed.contains('fe80::1'), false);

    final unpacked = unpackSdp(packed);
    expect(unpacked.type, 'offer');
    expect(unpacked.sdp, contains('a=ice-ufrag:abcd1234'));
    expect(unpacked.sdp, contains('a=ice-pwd:secretPassword0123456789'));
    expect(unpacked.sdp, contains('a=setup:actpass'));
    expect(unpacked.sdp, contains('00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF'));
    expect(unpacked.sdp, contains('192.168.1.42 54321 typ host'));
    expect(unpacked.sdp, contains('203.0.113.9 54321 typ srflx'));
    expect(unpacked.sdp, contains('a=end-of-candidates'));
  });
}

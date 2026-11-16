import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'game_engine.dart';

typedef _CallNative = Pointer<Utf8> Function(Pointer<Utf8> op, Pointer<Utf8> payload);
typedef _CallDart = Pointer<Utf8> Function(Pointer<Utf8> op, Pointer<Utf8> payload);
typedef _FreeNative = Void Function(Pointer<Utf8> ptr);
typedef _FreeDart = void Function(Pointer<Utf8> ptr);

typedef _WsaStartupNative = Int32 Function(Uint16 wVersionRequested, Pointer<Uint8> lpWSAData);
typedef _WsaStartupDart = int Function(int wVersionRequested, Pointer<Uint8> lpWSAData);
typedef _SocketNative = IntPtr Function(Int32 af, Int32 type, Int32 protocol);
typedef _SocketDart = int Function(int af, int type, int protocol);
typedef _ConnectNative = Int32 Function(IntPtr s, Pointer<Uint8> name, Int32 namelen);
typedef _ConnectDart = int Function(int s, Pointer<Uint8> name, int namelen);
typedef _SendNative = Int32 Function(IntPtr s, Pointer<Uint8> buf, Int32 len, Int32 flags);
typedef _SendDart = int Function(int s, Pointer<Uint8> buf, int len, int flags);
typedef _RecvNative = Int32 Function(IntPtr s, Pointer<Uint8> buf, Int32 len, Int32 flags);
typedef _RecvDart = int Function(int s, Pointer<Uint8> buf, int len, int flags);
typedef _CloseSocketNative = Int32 Function(IntPtr s);
typedef _CloseSocketDart = int Function(int s);

class NativeEngineBackend implements EngineBackend {
  DynamicLibrary? _lib;
  _CallDart? _call;
  _FreeDart? _free;

  Process? _rpcProc;
  int _sock = -1;
  _SendDart? _send;
  _RecvDart? _recv;
  _CloseSocketDart? _closeSocket;

  @override
  Future<void> init() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final libName = Platform.isWindows
        ? 'estandarte_engine.dll'
        : Platform.isMacOS
            ? 'libestandarte_engine.dylib'
            : 'libestandarte_engine.so';
    final dllCandidates = [
      '$exeDir${Platform.pathSeparator}$libName',
      '$exeDir${Platform.pathSeparator}lib${Platform.pathSeparator}$libName',
      'native${Platform.pathSeparator}$libName',
      libName,
    ];
    DynamicLibrary? loaded;
    Object? lastErr;
    for (final c in dllCandidates) {
      try {
        loaded = DynamicLibrary.open(c);
        break;
      } catch (e) {
        lastErr = e;
      }
    }
    if (loaded != null) {
      _lib = loaded;
      _call = _lib!.lookupFunction<_CallNative, _CallDart>('EstandarteCall');
      _free = _lib!.lookupFunction<_FreeNative, _FreeDart>('EstandarteFree');
      return;
    }

    if (Platform.isWindows) {
      final rpcCandidates = [
        '$exeDir${Platform.pathSeparator}estandarte_engine_rpc.exe',
        '$exeDir${Platform.pathSeparator}lib${Platform.pathSeparator}estandarte_engine_rpc.exe',
        'native${Platform.pathSeparator}estandarte_engine_rpc.exe',
        'estandarte_engine_rpc.exe',
      ];
      String? rpcPath;
      for (final c in rpcCandidates) {
        if (File(c).existsSync()) {
          rpcPath = c;
          break;
        }
      }
      if (rpcPath != null) {
        await _initRpcWindows(rpcPath);
        return;
      }
    }

    throw StateError(
      'Motor nativo ($libName${Platform.isWindows ? ' ou estandarte_engine_rpc.exe' : ''}) não encontrado ($lastErr). '
      'Compile com tool/build_engine.ps1 -Native (Windows) ou tool/build_engine.sh --native.',
    );
  }

  Future<void> _initRpcWindows(String rpcPath) async {
    final ws2 = DynamicLibrary.open('ws2_32.dll');
    final wsaStartup = ws2.lookupFunction<_WsaStartupNative, _WsaStartupDart>('WSAStartup');
    final socketFn = ws2.lookupFunction<_SocketNative, _SocketDart>('socket');
    final connectFn = ws2.lookupFunction<_ConnectNative, _ConnectDart>('connect');
    _send = ws2.lookupFunction<_SendNative, _SendDart>('send');
    _recv = ws2.lookupFunction<_RecvNative, _RecvDart>('recv');
    _closeSocket = ws2.lookupFunction<_CloseSocketNative, _CloseSocketDart>('closesocket');

    final wsaData = calloc<Uint8>(512);
    try {
      final rc = wsaStartup(0x0202, wsaData);
      if (rc != 0) {
        throw StateError('WSAStartup falhou: $rc');
      }
    } finally {
      calloc.free(wsaData);
    }

    final proc = await Process.start(rpcPath, const []);
    _rpcProc = proc;
    final portCompleter = Completer<int>();
    final errBuf = StringBuffer();

    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        if (!portCompleter.isCompleted && line.startsWith('PORT=')) {
          final p = int.tryParse(line.substring(5).trim());
          if (p != null && p > 0) {
            portCompleter.complete(p);
          }
        }
      },
      onDone: () {
        if (!portCompleter.isCompleted) {
          portCompleter.completeError(
            StateError('Motor RPC encerrou antes de informar a porta. $errBuf'),
          );
        }
      },
      onError: (Object e, StackTrace st) {
        if (!portCompleter.isCompleted) {
          portCompleter.completeError(e, st);
        }
      },
    );
    proc.stderr.transform(utf8.decoder).listen((chunk) {
      if (!portCompleter.isCompleted) errBuf.write(chunk);
    });

    final port = await portCompleter.future.timeout(const Duration(seconds: 5));
    final sock = socketFn(2, 1, 6);
    if (sock == -1) {
      proc.kill();
      throw StateError('Falha ao abrir socket TCP para motor RPC');
    }

    final addr = calloc<Uint8>(16);
    try {
      final bytes = addr.asTypedList(16);
      bytes.fillRange(0, 16, 0);
      bytes[0] = 2; // AF_INET
      bytes[1] = 0;
      bytes[2] = (port >> 8) & 0xFF;
      bytes[3] = port & 0xFF;
      bytes[4] = 127;
      bytes[5] = 0;
      bytes[6] = 0;
      bytes[7] = 1;

      final connRc = connectFn(sock, addr, 16);
      if (connRc != 0) {
        _closeSocket?.call(sock);
        proc.kill();
        throw StateError('Falha ao conectar ao motor RPC em 127.0.0.1:$port (rc=$connRc)');
      }
      _sock = sock;
    } finally {
      calloc.free(addr);
    }
  }

  @override
  String call(String op, String payload) {
    final dllCall = _call;
    final dllFree = _free;
    if (dllCall != null && dllFree != null) {
      final opPtr = op.toNativeUtf8();
      final payPtr = payload.toNativeUtf8();
      Pointer<Utf8> resPtr = nullptr;
      try {
        resPtr = dllCall(opPtr, payPtr);
        return resPtr.toDartString();
      } finally {
        calloc.free(opPtr);
        calloc.free(payPtr);
        if (resPtr != nullptr) {
          dllFree(resPtr);
        }
      }
    }

    final sendFn = _send;
    final recvFn = _recv;
    if (_sock == -1 || sendFn == null || recvFn == null) {
      throw StateError('Motor nativo não inicializado.');
    }

    final msgBytes = utf8.encode('$op\n$payload');
    final frame = Uint8List(4 + msgBytes.length);
    ByteData.sublistView(frame).setUint32(0, msgBytes.length, Endian.little);
    frame.setRange(4, frame.length, msgBytes);
    _sendAll(sendFn, _sock, frame);

    final lenBytes = _recvExact(recvFn, _sock, 4);
    final resLen = ByteData.sublistView(lenBytes).getUint32(0, Endian.little);
    if (resLen == 0) return '';
    final resBytes = _recvExact(recvFn, _sock, resLen);
    return utf8.decode(resBytes);
  }

  static void _sendAll(_SendDart sendFn, int sock, Uint8List data) {
    final ptr = calloc<Uint8>(data.length);
    try {
      ptr.asTypedList(data.length).setAll(0, data);
      var offset = 0;
      while (offset < data.length) {
        final n = sendFn(sock, ptr + offset, data.length - offset, 0);
        if (n <= 0) {
          throw StateError('Erro ao enviar para motor RPC (send=$n)');
        }
        offset += n;
      }
    } finally {
      calloc.free(ptr);
    }
  }

  static Uint8List _recvExact(_RecvDart recvFn, int sock, int length) {
    final ptr = calloc<Uint8>(length);
    try {
      var offset = 0;
      while (offset < length) {
        final n = recvFn(sock, ptr + offset, length - offset, 0);
        if (n <= 0) {
          throw StateError('Erro ao ler do motor RPC (recv=$n)');
        }
        offset += n;
      }
      return Uint8List.fromList(ptr.asTypedList(length));
    } finally {
      calloc.free(ptr);
    }
  }

  void dispose() {
    if (_sock != -1) {
      _closeSocket?.call(_sock);
      _sock = -1;
    }
    _rpcProc?.kill();
    _rpcProc = null;
  }
}

EngineBackend createEngineBackend() => NativeEngineBackend();

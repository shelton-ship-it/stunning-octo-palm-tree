import 'dart:typed_data';

/// chacha20_segment.dart — porte linha-a-linha do algoritmo REAL usado em
/// workers/decrypt.worker.ts (site, @noble/ciphers `chacha20(key, nonce,
/// cipher, undefined, 1)` — RFC 8439, contador inicial = 1, SEMPRE
/// reiniciado a 1 em CADA chunk, porque cada chunk tem o seu próprio
/// nonce de 12 bytes).
///
/// Usado SÓ para downloads offline (GET /content/:id/download) — o único
/// caminho de dados desta app que decripta em Dart. VOD usa WebView (o
/// ShakaPlayer real decripta) e canais não têm DRM nenhum.
///
/// Formato "chunk-v2" (igual, confirmado no worker real):
///   [4 bytes LE: nChunks]  (0 ou >=100000 → segmento vazio)
///   por chunk: [12 bytes nonce][4 bytes LE: length][corpo cifrado]
class ChaCha20Segment {
  /// hex → bytes (drm_key_hex do backend, 32 bytes / 64 chars hex).
  static Uint8List hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      out[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return out;
  }

  /// Decripta um segmento .bin inteiro (todos os chunks concatenados,
  /// já sem os cabeçalhos) — usar para init.bin e para cada segNNNNN.bin.
  static Uint8List decryptSegment(Uint8List data, Uint8List key) {
    if (data.length < 4) return Uint8List(0);
    final bd = ByteData.sublistView(data);
    final nChunks = bd.getUint32(0, Endian.little);
    if (nChunks == 0 || nChunks >= 100000) return Uint8List(0);

    final chunks = <Uint8List>[];
    var pos = 4;
    for (var i = 0; i < nChunks; i++) {
      if (pos + 16 > data.length) break;
      final nonce = data.sublist(pos, pos + 12);
      final chBd = ByteData.sublistView(data, pos + 12, pos + 16);
      final len = chBd.getUint32(0, Endian.little);
      pos += 16;
      if (pos + len > data.length) break;
      final cipher = data.sublist(pos, pos + len);
      pos += len;
      chunks.add(_chacha20(key, nonce, cipher, counter: 1));
    }

    final total = chunks.fold<int>(0, (s, c) => s + c.length);
    final out = Uint8List(total);
    var off = 0;
    for (final c in chunks) {
      out.setRange(off, off + c.length, c);
      off += c.length;
    }
    return out;
  }

  // ── RFC 8439 ChaCha20 (implementação directa, sem dependências) ───────

  static const _c0 = 0x61707865, _c1 = 0x3320646e, _c2 = 0x79622d32, _c3 = 0x6b206574;

  static int _rotl32(int v, int n) => ((v << n) | (v >> (32 - n))) & 0xFFFFFFFF;

  static void _quarterRound(Uint32List s, int a, int b, int c, int d) {
    s[a] = (s[a] + s[b]) & 0xFFFFFFFF; s[d] ^= s[a]; s[d] = _rotl32(s[d], 16);
    s[c] = (s[c] + s[d]) & 0xFFFFFFFF; s[b] ^= s[c]; s[b] = _rotl32(s[b], 12);
    s[a] = (s[a] + s[b]) & 0xFFFFFFFF; s[d] ^= s[a]; s[d] = _rotl32(s[d], 8);
    s[c] = (s[c] + s[d]) & 0xFFFFFFFF; s[b] ^= s[c]; s[b] = _rotl32(s[b], 7);
  }

  static Uint8List _block(Uint8List key, Uint8List nonce, int counter) {
    final kv = ByteData.sublistView(key);
    final nv = ByteData.sublistView(nonce);
    final state = Uint32List(16);
    state[0] = _c0; state[1] = _c1; state[2] = _c2; state[3] = _c3;
    for (var i = 0; i < 8; i++) {
      state[4 + i] = kv.getUint32(i * 4, Endian.little);
    }
    state[12] = counter & 0xFFFFFFFF;
    state[13] = nv.getUint32(0, Endian.little);
    state[14] = nv.getUint32(4, Endian.little);
    state[15] = nv.getUint32(8, Endian.little);

    final working = Uint32List.fromList(state);
    for (var i = 0; i < 10; i++) {
      _quarterRound(working, 0, 4, 8, 12);
      _quarterRound(working, 1, 5, 9, 13);
      _quarterRound(working, 2, 6, 10, 14);
      _quarterRound(working, 3, 7, 11, 15);
      _quarterRound(working, 0, 5, 10, 15);
      _quarterRound(working, 1, 6, 11, 12);
      _quarterRound(working, 2, 7, 8, 13);
      _quarterRound(working, 3, 4, 9, 14);
    }

    final out = Uint8List(64);
    final outBd = ByteData.sublistView(out);
    for (var i = 0; i < 16; i++) {
      outBd.setUint32(i * 4, (working[i] + state[i]) & 0xFFFFFFFF, Endian.little);
    }
    return out;
  }

  /// XOR do keystream com `data` — simétrico (serve para cifrar e decifrar).
  /// `counter` é o bloco inicial (1, igual ao site) e incrementa a cada
  /// bloco de 64 bytes DENTRO do mesmo chunk.
  static Uint8List _chacha20(Uint8List key, Uint8List nonce, Uint8List data, {required int counter}) {
    final out = Uint8List(data.length);
    var blockCounter = counter;
    for (var offset = 0; offset < data.length; offset += 64) {
      final ks = _block(key, nonce, blockCounter);
      final end = (offset + 64 < data.length) ? offset + 64 : data.length;
      for (var i = offset; i < end; i++) {
        out[i] = data[i] ^ ks[i - offset];
      }
      blockCounter++;
    }
    return out;
  }
}

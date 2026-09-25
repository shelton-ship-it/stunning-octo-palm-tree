import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// ecdh_keygen.dart — pendência #6 (player nativo sem WebView).
///
/// GET /api/content/:id/stream exige um `clientPubKey` — o backend importa-o
/// via WebCrypto (`crypto.subtle.importKey('raw', bytes, {name:'ECDH',
/// namedCurve:'P-256'}, false, [])`, ver routes/content.js linha ~194 e
/// serverECDH em [[default]].js), o que VALIDA de facto que é um ponto EC
/// P-256 válido — não dá para mandar bytes aleatórios.
///
/// IMPORTANTE (confirmado no código do backend): a chave devolvida
/// (`drm_key_hex`) já vem em CLARO na resposta JSON — é a CHACHA_KEY global
/// do servidor, não um segredo derivado por-sessão. O "ECDH" serve só para
/// o servidor validar/registar a chave pública do cliente (telemetria/
/// anti-abuso), não para cifrar a resposta. Por isso este cliente nativo
/// NÃO precisa de calcular nenhum segredo partilhado (deriveBits) — só
/// precisa de gerar um par de chaves EC P-256 válido e exportar a chave
/// pública no mesmo formato "raw" (0x04 || X(32 bytes) || Y(32 bytes)) que
/// `crypto.subtle.exportKey('raw', ...)` produz no site
/// (ShakaPlayer.tsx → performECDH), depois base64 simples (igual ao
/// `btoa(String.fromCharCode(...))` do site).
Future<String> generateEcdhClientPubKeyB64() async {
  final algorithm = Ecdh.p256(length: 256);
  final keyPair = await algorithm.newKeyPair();
  final publicKey = await keyPair.extractPublicKey();

  final raw = Uint8List(65);
  raw[0] = 0x04; // ponto não comprimido — mesmo formato do WebCrypto 'raw'
  raw.setRange(1, 33, _pad32(publicKey.x));
  raw.setRange(33, 65, _pad32(publicKey.y));
  return base64Encode(raw);
}

/// As coordenadas X/Y de uma chave P-256 têm sempre 32 bytes; alguns
/// backends de curva elíptica devolvem o array sem os zeros à esquerda
/// (big-endian "minimal"), o que corromperia o formato raw esperado pelo
/// servidor. Preenche à esquerda com zeros até 32 bytes.
Uint8List _pad32(List<int> bytes) {
  if (bytes.length == 32) return Uint8List.fromList(bytes);
  if (bytes.length > 32) return Uint8List.fromList(bytes.sublist(bytes.length - 32));
  final out = Uint8List(32);
  out.setRange(32 - bytes.length, 32, bytes);
  return out;
}

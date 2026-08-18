import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

// `ECPrivateKey` re-exportieren, damit Aufrufer (server.dart), die dieses
// Modul mit einem Präfix importieren (`as web_push`), den Rückgabetyp von
// [vapidPrivateKeyFromBase64Url] auch als `web_push.ECPrivateKey`
// benennen können, ohne selbst zusätzlich pointycastle importieren zu
// müssen.
export 'package:pointycastle/export.dart' show ECPrivateKey;

/// Reine Dart-Implementierung von RFC 8291 (Web Push Message Encryption)
/// und RFC 8292 (VAPID), Byte für Byte nach den beiden RFCs umgesetzt.
///
/// Bewusst OHNE die Pakete `webcrypto`/`webpush_encryption`: beide hängen
/// (Stand heute) direkt oder transitiv von `webcrypto` ab, das intern
/// Native-Build-Hooks nutzt - diese sind mit `dart compile exe` NICHT
/// kompatibel (der Server wird laut Dockerfile als eigenständige
/// AOT-Executable gebaut, siehe dortigen Kommentar). `pointycastle` ist
/// reines Dart ohne native Abhängigkeiten und funktioniert deshalb
/// zuverlässig in dieser Build-Pipeline.

final ECDomainParameters _p256 = ECDomainParameters('prime256v1');

SecureRandom _newSecureRandom() {
  final rand = FortunaRandom();
  final seedSource = Random.secure();
  final seeds = Uint8List.fromList(List<int>.generate(32, (_) => seedSource.nextInt(256)));
  rand.seed(KeyParameter(seeds));
  return rand;
}

Uint8List _bigIntToBytes(BigInt n, int length) {
  final out = Uint8List(length);
  var v = n;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return out;
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _hmacSha256(Uint8List key, Uint8List data) {
  final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
  return hmac.process(data);
}

/// HKDF-Expand (RFC 5869), aber nur für ein einzelnes Block (reicht hier
/// immer aus, da wir nie mehr als 32 Bytes Ausgabe brauchen).
Uint8List _hkdfExpandOneBlock(Uint8List prk, Uint8List info, int length) {
  final input = BytesBuilder()
    ..add(info)
    ..addByte(0x01);
  final block = _hmacSha256(prk, input.toBytes());
  return Uint8List.sublistView(block, 0, length);
}

/// Baut aus einem base64url-kodierten rohen Private-Key-Skalar (32 Bytes)
/// ein pointycastle-`ECPrivateKey` für die P-256-Kurve.
ECPrivateKey vapidPrivateKeyFromBase64Url(String base64url) {
  final bytes = base64Url.decode(_padBase64(base64url));
  return ECPrivateKey(_bytesToBigInt(bytes), _p256);
}

String _padBase64(String s) {
  final mod = s.length % 4;
  if (mod == 0) return s;
  return s + '=' * (4 - mod);
}

/// Signiert [signingInput] (die ASCII-Bytes von
/// "base64url(header).base64url(payload)") nach ES256/JWS - liefert die
/// rohe 64-Byte R‖S-Signatur (kein DER), wie von VAPID/RFC 8292 verlangt.
Uint8List signEs256(ECPrivateKey privateKey, Uint8List signingInput) {
  final signer = ECDSASigner(SHA256Digest())
    ..init(true, ParametersWithRandom(PrivateKeyParameter(privateKey), _newSecureRandom()));
  final signature = signer.generateSignature(signingInput) as ECSignature;
  final rBytes = _bigIntToBytes(signature.r, 32);
  final sBytes = _bigIntToBytes(signature.s, 32);
  return Uint8List.fromList([...rBytes, ...sBytes]);
}

/// Baut ein komplettes VAPID-JWT (RFC 8292) für die gegebene [audience]
/// (Schema + Host des Push-Endpunkts, z. B. "https://fcm.googleapis.com")
/// und signiert es mit dem gegebenen privaten VAPID-Schlüssel.
String buildVapidJwt({
  required ECPrivateKey privateKey,
  required String audience,
  required String subject,
}) {
  final header = {'typ': 'JWT', 'alg': 'ES256'};
  final now = DateTime.now().toUtc();
  final exp = now.add(const Duration(hours: 12));
  final payload = {
    'aud': audience,
    'exp': exp.millisecondsSinceEpoch ~/ 1000,
    'sub': subject,
  };
  final headerB64 = _b64urlJson(header);
  final payloadB64 = _b64urlJson(payload);
  final signingInput = '$headerB64.$payloadB64';
  final signature = signEs256(privateKey, Uint8List.fromList(utf8.encode(signingInput)));
  final sigB64 = base64Url.encode(signature).replaceAll('=', '');
  return '$signingInput.$sigB64';
}

String _b64urlJson(Map<String, Object?> map) {
  final bytes = utf8.encode(jsonEncode(map));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Verschlüsselt [plaintext] nach RFC 8291 für einen Push-Abonnenten.
/// [subscriberPublicKeyBytes] ist der rohe (base64url-dekodierte) `p256dh`-
/// Wert (65 Bytes), [subscriberAuthSecret] der rohe `auth`-Wert (16 Bytes)
/// aus der PushSubscription des Browsers. Gibt den fertigen
/// "aes128gcm"-Body zurück (Salt + Record-Header + Chiffretext inkl. Tag) -
/// kann unverändert als HTTP-Body an den Push-Dienst gesendet werden.
Uint8List encryptWebPush({
  required Uint8List subscriberPublicKeyBytes,
  required Uint8List subscriberAuthSecret,
  required Uint8List plaintext,
}) {
  // Ephemeres ECDH-Schlüsselpaar - nur für diese eine Nachricht gültig.
  final keyGen = ECKeyGenerator()
    ..init(ParametersWithRandom(ECKeyGeneratorParameters(_p256), _newSecureRandom()));
  final pair = keyGen.generateKeyPair();
  final asPublic = pair.publicKey as ECPublicKey;
  final asPrivate = pair.privateKey as ECPrivateKey;
  final asPublicBytes = asPublic.Q!.getEncoded(false);

  final subscriberPoint = _p256.curve.decodePoint(subscriberPublicKeyBytes)!;
  final subscriberPublicKey = ECPublicKey(subscriberPoint, _p256);
  final agreement = ECDHBasicAgreement()..init(asPrivate);
  final ecdhSecret = _bigIntToBytes(agreement.calculateAgreement(subscriberPublicKey), 32);

  // RFC 8291 §3.4: IKM für RFC 8188 aus ECDH-Secret + Auth-Secret ableiten.
  final prkKey = _hmacSha256(subscriberAuthSecret, ecdhSecret);
  final keyInfo = BytesBuilder()
    ..add(utf8.encode('WebPush: info'))
    ..addByte(0x00)
    ..add(subscriberPublicKeyBytes)
    ..add(asPublicBytes);
  final ikm = _hkdfExpandOneBlock(prkKey, keyInfo.toBytes(), 32);

  // RFC 8188 (aes128gcm): zufälliges Salt, daraus CEK und Nonce ableiten.
  final saltSource = Random.secure();
  final salt = Uint8List.fromList(List<int>.generate(16, (_) => saltSource.nextInt(256)));
  final prk = _hmacSha256(salt, ikm);
  final cekInfo = BytesBuilder()
    ..add(utf8.encode('Content-Encoding: aes128gcm'))
    ..addByte(0x00);
  final cek = _hkdfExpandOneBlock(prk, cekInfo.toBytes(), 16);
  final nonceInfo = BytesBuilder()
    ..add(utf8.encode('Content-Encoding: nonce'))
    ..addByte(0x00);
  final nonce = _hkdfExpandOneBlock(prk, nonceInfo.toBytes(), 12);

  // Ein einzelnes Padding-Trennzeichen (0x02 = "letzter/einziger Record",
  // RFC 8188 §2) an den Klartext anhängen - es wird immer nur ein Record
  // pro Nachricht verschickt.
  final padded = BytesBuilder()
    ..add(plaintext)
    ..addByte(0x02);

  final gcm = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(cek), 16 * 8, nonce, Uint8List(0)));
  final ciphertext = gcm.process(padded.toBytes());

  // Body-Format nach RFC 8188 §2.1: Salt(16) + Record-Size(4, big-endian)
  // + KeyID-Länge(1) + KeyID (= unser öffentlicher Schlüssel, 65 Bytes) +
  // Chiffretext (inkl. angehängtem 16-Byte GCM-Tag).
  final recordSize = ByteData(4)..setUint32(0, 4096, Endian.big);
  final body = BytesBuilder()
    ..add(salt)
    ..add(recordSize.buffer.asUint8List())
    ..addByte(asPublicBytes.length)
    ..add(asPublicBytes)
    ..add(ciphertext);
  return body.toBytes();
}

Uint8List decodeBase64UrlField(String value) => base64Url.decode(_padBase64(value));

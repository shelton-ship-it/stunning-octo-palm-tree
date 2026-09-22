# Pixgo — App Flutter (Android)

Reconstrução nativa do site Pixgo (`pixel.zip`, Next.js) em Flutter/Dart —
mesma linguagem/framework do projecto anterior (`pg-sp`), mas fielmente
alinhada ao contrato real dos backends `api.pixgo.qzz.io` (pixel_service) e
`pixel.pixgo.qzz.io` (api-core). Ver `[[pixgo-android-rebuild]]` e
`[[streamvault-pixgo]]` para o histórico completo da migração.

> Este README substitui uma versão anterior que descrevia uma arquitectura
> de decriptação ChaCha20 nativa (servidor HTTP local `127.0.0.1` via
> `shelf` + `chacha20.dart`) que **nunca chegou a ser usada** — o
> `pubspec.yaml` já documentava a decisão real (WebView para o `/embed/watch`
> real do site) antes desta rodada, e os ficheiros `chacha20.dart`/
> `decrypt_proxy_server.dart` nunca existiram no repositório. Este README
> estava desatualizado; foi reescrito para reflectir o código actual.

## Estrutura

```
lib/
  core/           theme.dart (cores exactas de globals.css), router.dart (go_router)
  models/         User, AppPlan, ContentItem, ChannelItem, DownloadItem
  services/       api_client.dart (Dio + cookie jar persistente + refresh de token),
                  channels_source.dart (parsing M3U client-side, igual a
                  channels-source.ts), downloads_service.dart
  providers/      auth_provider.dart (Riverpod, equivalente a store/auth.ts), locale_provider.dart
  screens/        um ecrã por rota do site original (auth/, main/)
  widgets/        content_card.dart, pixel_chatbot.dart, disclaimer_gate.dart
  l10n/           app_localizations.dart (lê assets/i18n/{pt,en,es}.json — os
                  MESMOS 774 chaves do site)
android/          projecto Android nativo (gradle, manifest, ícones)
.github/workflows/build_apk.yml   compila o APK automaticamente
```

## Hosts reais (sem ENVs novas — já eram do stack)

| Constante (`api_client.dart`) | Default | Serve |
|---|---|---|
| `kApiBase`      | `https://api.pixgo.qzz.io`   | catálogo, conteúdo, stream, canais (gate/heartbeat), progresso, minha lista, planos (leitura), login alternativo |
| `kApiCoreBase`  | `https://pixel.pixgo.qzz.io` | gateway de pagamento, ZumboPay, device code TV |
| `kWebBase`      | `https://pixgo.qzz.io`       | WebView do player VOD (`/embed/watch/:id`) |
| `kHubBase`      | `https://app.pixgo.qzz.io`   | WebView do checkout Hotmart |
| `kUploadBase`   | `https://copyright.pixgo.qzz.io` | upload/denúncia/suporte/chatbot |

Todas configuráveis via `--dart-define` se precisares de apontar para outro
ambiente; nenhuma delas é uma ENV nova — são os mesmos domínios já em
produção (ver mapa da Fase 1).

## Decisões técnicas importantes

### 1. Player VOD — WebView do `/embed/watch/:id` real
O site cifra segmentos com ChaCha20 e o handshake ECDH exige um ponto P-256
válido (`serverECDH()`); reimplementar isso em Dart foi tentado e
abandonado antes desta rodada (ver histórico em `[[streamvault-pixgo]]`).
A solução adoptada, mais fiel e sem inventar nada: `watch_screen.dart`
carrega uma `WebView` apontada para `$kWebBase/embed/watch/:id` — a página
real do site, que renderiza o componente `<ShakaPlayer>` **sem nenhuma
alteração à sua lógica** (handshake ECDH, decriptação ChaCha20 e heartbeat
120s são todos feitos pelo próprio componente, tal como no browser). A
ponte `PixgoBridge` (JS ↔ Dart) repassa progresso, fim de episódio, limite
de tempo esgotado (429) e sessão substituída (409).

### 2. TV ao vivo — nativo (sem WebView)
Sem DRM (streams IPTV públicos), por isso é `video_player`/Chewie directo.
A LISTA de canais é 100% client-side (`channels_source.dart`, porte fiel de
`channels-source.ts`: busca `playlist.m3u`+`logos.json` no jsDelivr,
parsing M3U, dedupe por nome, cache 30 min) — o backend **não** tem
endpoint de listagem (`/channels`, `/channels/categories`, `/channels/search`
não existem; a versão anterior deste projecto assumia-os e nunca
funcionou). O backend só entra no gate (`GET /channels/:id` → `{ok:true}`)
antes de tocar e no heartbeat (`POST /channels/:id/heartbeat` a cada 120s,
mesma cota diária do VOD) — implementado em `watch_screen.dart`.

### 3. Pagamentos — dois gateways reais, decididos no servidor
`GET /api/payments/gateway?plan=<id>` (api-core) decide Hotmart ou ZumboPay
pelo país (nunca no cliente). Hotmart é um widget JS puro — só corre no
domínio real do hub, por isso `checkout_screen.dart` abre uma `WebView`
para `$kHubBase/main/plans/checkout?plan=<id>` com o cookie `pixgo_session`
sincronizado primeiro (mesma sessão, sem novo login), e detecta a chegada
nas Thank-You Pages reais (`/main/plans/checkout/success|pending|analysis`).
ZumboPay é API pura (MZ, M-Pesa) e está implementado 100% nativo — mesmos
estados/validação/polling (3s, timeout 5min) do `ZumboPayCheckout.tsx`
real. A lógica USDT/Polygon que existia antes foi removida do backend numa
rodada anterior e **não** foi trazida para cá.

### 4. Cookies — jar persistente partilhado
`cookie_jar` + `dio_cookie_manager`, um único jar persistido em disco e
partilhado entre `api.pixgo.qzz.io` e `pixel.pixgo.qzz.io`. Necessário para
o cookie `pv_did` (identidade de dispositivo, host-only — sem isto o
backend via cada pedido como "dispositivo novo", disparando o cap de
5 dispositivos/IP/dia) e para `pixgo_session` (Domain=.pixgo.qzz.io,
partilhado automaticamente entre os dois hosts pelo mesmo jar).

### 5. Downloads offline (`lib/services/downloads_service.dart`)
O site usa IndexedDB (metadata + segmentos cifrados). Aqui `sqflite` para
metadata e ficheiros no filesystem para os segmentos — equivalente
funcional, sem alterar o contrato de `GET /content/:id/download`.

### 6. i18n
Delegate leve (`lib/l10n/app_localizations.dart`, dot-notation) que lê os
mesmos 3 ficheiros JSON do site (774 chaves cada). A versão anterior deste
projecto tinha cópias desactualizadas (295 chaves) — causa directa de
títulos/textos em falta; substituídas pelas reais.

### 7. Chatbot
`widgets/pixel_chatbot.dart` — não existia nesta app antes. Mesmo contrato
de rede do `PixelChatbot.tsx` real (`POST {UPLOAD}/chat {message, history}`,
resposta `res.reply`) e o mesmo comportamento de saudação única por
dispositivo.

### 8. Estado (Zustand → Riverpod)
`store/auth.ts` → `lib/providers/auth_provider.dart`. Mesma lógica de
refresh automático de token em 401 (`ApiClient._req`).

## Como compilar
Push para `main` (ou *workflow_dispatch*) — `.github/workflows/build_apk.yml`
compila e publica o APK como artefacto + Release.

Localmente (se tiveres Flutter instalado — **este ambiente não tem SDK
Flutter/Dart/Android, por isso nenhuma parte deste projecto foi compilada
ou testada aqui**; validação real só pelo GitHub Actions):
```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=https://api.pixgo.qzz.io
```

## Assinatura do APK
Sem `key.properties`, o build assina em modo debug. Para produção, os
secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` já são o contrato existente do
workflow (nenhuma ENV nova).

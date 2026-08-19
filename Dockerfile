# syntax=docker/dockerfile:1

# --- Stage 1: Flutter-Web-Build ---------------------------------------------
# Enthält das komplette Flutter-SDK (mehrere hundert MB) - wird aber nie
# ausgeliefert, nur die fertigen statischen Web-Dateien landen im Endimage.
FROM ghcr.io/cirruslabs/flutter:stable AS flutter-build

WORKDIR /app
COPY . .

# Falls der web/-Ordner (noch) nicht existiert, wird er hier ergänzt, ohne
# lib/ anzufassen.
RUN flutter create --platforms=web --org de.dennis . \
  && flutter pub get \
  && flutter build web --release

# --- Stage 2: Server-Build ---------------------------------------------------
# Reines Dart (kein Flutter nötig) - wird zu einer einzigen ausführbaren
# Datei kompiliert.
FROM dart:stable AS server-build

WORKDIR /server
COPY server/ .
RUN dart pub get
RUN dart compile exe bin/server.dart -o /server_bin

# --- Stage 3: Runtime --------------------------------------------------------
# Bewusst Debian (nicht Alpine!): von "dart compile exe" erzeugte
# Programme sind gegen glibc gelinkt, das gibt es unter Alpine/musl nicht.
FROM debian:bookworm-slim AS runtime

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=server-build /server_bin /app/server
COPY --from=flutter-build /app/build/web /app/web

ENV WEB_DIR=/app/web
ENV DATA_DIR=/data
ENV PORT=8080

VOLUME ["/data"]
EXPOSE 8080

CMD ["/app/server"]

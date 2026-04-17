# syntax=docker/dockerfile:1

# Stage 1: build Flutter web
FROM ghcr.io/cirruslabs/flutter:stable AS build-env

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get --no-example

COPY . .

# Pode ser sobrescrito no Dokploy em Build Args.
ARG API_BASE_URL=https://api.fitmatch.page

RUN flutter build web --release \
    --base-href=/ \
    --dart-define=API_BASE_URL=${API_BASE_URL} \
    --dart-define=FLUTTER_WEB_CANVASKIT_URL=https://cdn.jsdelivr.net/npm/canvaskit-wasm@0.39.0/bin/

# Stage 2: Nginx para servir SPA
FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build-env /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

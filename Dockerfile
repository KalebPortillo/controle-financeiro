# syntax=docker/dockerfile:1
# check=error=true

# Multi-stage build:
#   1. frontend-builder  → npm build → dist/
#   2. backend-builder   → bundle install + bootsnap precompile
#   3. runtime           → slim image com app + frontend dist em /rails/public
#
# Build context é a raiz do repo (--context .), permite ver backend/ + frontend/.

# Versões. Declarados antes do primeiro FROM para serem visíveis em todos os stages.
ARG RUBY_VERSION=3.3.5

# ---------- 1. Frontend ----------
FROM node:22-slim AS frontend-builder

WORKDIR /frontend

COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

COPY frontend/ ./

# DSN injetado em build time (variável VITE_*).
# Em CI, KAMAL passa --build-arg VITE_SENTRY_DSN=... (vem do GHA secret).
ARG VITE_SENTRY_DSN=""
ENV VITE_SENTRY_DSN=${VITE_SENTRY_DSN}

RUN npm run build

# ---------- 2. Backend base ----------
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS backend-base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# ---------- 3. Backend build ----------
FROM backend-base AS backend-builder

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY backend/vendor/ ./vendor/
COPY backend/Gemfile backend/Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY backend/ ./

RUN bundle exec bootsnap precompile -j 1 app/ lib/

# ---------- 4. Runtime ----------
FROM backend-base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --chown=rails:rails --from=backend-builder "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=backend-builder /rails /rails
COPY --chown=rails:rails --from=frontend-builder /frontend/dist/ /rails/public/

USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Thruster ouve na 80 e proxy pro Puma na 3000. CF Tunnel aponta pra host port.
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]

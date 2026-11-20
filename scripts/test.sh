#!/bin/sh
# luacheck + busted in a throwaway container (no lua on the host)
set -e
cd "$(dirname "$0")/.."
docker build -q -t bookbindery-lua - >/dev/null <<'DOCKER'
FROM debian:stable-slim
RUN apt-get update && apt-get install -y --no-install-recommends luajit luarocks lua5.1 liblua5.1-dev build-essential ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*
RUN luarocks install busted && luarocks install luacheck && luarocks install lua-cjson
DOCKER
run() {
    docker run --init --rm -v "$1:/w" -w /w bookbindery-lua sh -c 'luacheck . && find bookbindery.koplugin patches -name "*.lua" 2>/dev/null | while read -r f; do luajit -b "$f" /dev/null || exit 1; done && busted'
}
run "$PWD"

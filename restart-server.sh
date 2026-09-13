#!/usr/bin/env bash
# Reinicia o servidor deepsproxy limpando todos os processos antigos.
cd /home/lz-panhard14/Imagens/deepproxy
fuser -k 3000/tcp 2>/dev/null || true
pkill -f "tsx src/index.ts" 2>/dev/null || true
pkill -f "loader.mjs src/index.ts" 2>/dev/null || true
sleep 2
rm -f deepseek_profile/SingletonLock deepseek_profile/SingletonCookie deepseek_profile/SingletonSocket
setsid nohup node node_modules/.bin/tsx src/index.ts > /tmp/dsserver.log 2>&1 < /dev/null & disown
sleep 8
tail -2 /tmp/dsserver.log

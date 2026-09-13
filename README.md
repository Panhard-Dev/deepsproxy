# DeepsProxy

Proxy API local compatível com **OpenAI** que roteia requisições para os modelos do **DeepSeek** (`chat.deepseek.com`) usando automação de navegador via Playwright. Feito para rodar na sua máquina e ser usado por qualquer cliente/SDK OpenAI-compatible (IDEs, agentes CLI, etc.).

```
Cliente (SDK OpenAI / agente) ──HTTP──▶ DeepsProxy ──Playwright──▶ chat.deepseek.com
```

---

## ✨ Destaques

- **100% compatível com OpenAI** — `/v1/chat/completions`, `/v1/models`, `/health`, autenticação por API key opcional e streaming SSE no formato `chat.completion.chunk`.
- **Tool calling robusto** — parser de tool calls resiliente a: streams fragmentados, JSON malformado, tags faltando, `</tool_call>` dentro de strings, nomes fuzzy (`getWeather` → `get_weather`), chamadas sem tags e JSON duplamente escapado.
- **Normalizador DSML** — quando o modelo vaza o formato interno de tool call dele (`<｜｜DSML｜｜ invoke ...>`) como texto, o proxy converte para `tool_calls` estruturado automaticamente, em tempo de stream.
- **Contexto configurável e honesto** — limite de contexto definido por configuração (`CONTEXT_TOKENS`), nunca "adivinhado" por tentativa-e-erro. Falhas de rede **nunca** derrubam o limite (sem envenenamento de telemetria).
- **Truncamento inteligente** — quando o histórico excede o limite, mensagens antigas são descartadas com aviso explícito, preservando **sempre** os pares `assistant(tool_calls) + tool` (unidades atômicas) e o system prompt.
- **Rejeição limpa de input gigante** — prompt acima do limite retorna `400 context_length_exceeded` no formato OpenAI, sem queimar tentativas de navegador.
- **Sessão persistente** — login uma única vez pelo navegador; a sessão fica salva em `deepseek_profile/`.
- **Suite de testes de verdade** — 95 testes cobrindo o parser (streams fragmentados, recuperação de JSON, cap de chamadas, chamadas sem wrapper, etc.).

---

## 📋 Pré-requisitos

| Dependência | Versão mínima |
|-------------|---------------|
| Node.js | v20.x |
| npm | v9.x |
| Chromium do Playwright | `npx playwright install chromium` |

---

## 🚀 Instalação

```bash
git clone https://github.com/Panhard-Dev/deepsproxy.git
cd deepsproxy
npm install
npx playwright install chromium
```

## 🔐 Login (primeira vez)

```bash
npm run login
```

Abre um **navegador visível** no `chat.deepseek.com`. Faça login normalmente (verificação humana incluída, se aparecer), e quando estiver na tela do chat, **feche a janela**. A sessão fica salva em `deepseek_profile/` e persiste entre reinícios.

Se o servidor estiver rodando e travar o perfil, use o script de limpeza:

```bash
bash clean-and-login.sh
```

Ele encerra processos antigos, remove os locks do perfil e abre o login de novo.

## ⚙️ Configuração

Crie um `.env` na raiz (veja `.env.example`):

```env
# Porta do servidor (default: 3000)
PORT=3000

# Chave de API para proteger endpoints (opcional — remova para desativar)
API_KEY=sua-chave-secreta-aqui

# Configurações Playwright
PLAYWRIGHT_HEADLESS=true
PLAYWRIGHT_TIMEOUT=30000

# Logging
LOG_LEVEL=info

# Limite de contexto em tokens (o proxy NUNCA encurta o histórico
# por baixo disso sem avisar; truncamento só acima disso)
CONTEXT_TOKENS=1000000
```

| Variável | Descrição | Default |
|----------|-----------|---------|
| `PORT` | Porta HTTP do servidor | `3000` |
| `API_KEY` | Chave exigida via `Authorization: Bearer` ou `X-API-Key` | *(sem auth)* |
| `PLAYWRIGHT_HEADLESS` | Executar o navegador em modo headless | `true` |
| `PLAYWRIGHT_TIMEOUT` | Timeout de operações do Playwright (ms) | `30000` |
| `CONTEXT_TOKENS` | Janela de contexto em tokens (≈ 3.5 chars/token) | `64000` |
| `DEEPSEEK_TOOL_OPEN` / `DEEPSEEK_TOOL_CLOSE` | Tags canônicas de tool call | `<tool_call>` / `</tool_call>` |
| `TOOLCALL_DEBUG` | `1` habilita logs de debug do parser | *(off)* |

## ▶️ Executando

```bash
npm start          # produção (headless)
npm run dev        # desenvolvimento com hot-reload
bash restart-server.sh   # reinicia limpo (mata processos antigos e locks)
```

---

## 📡 API

### `GET /health`

```json
{ "status": "ok" }
```

### `GET /v1/models`

Lista os modelos expostos:

| ID | Modelo real | Modo |
|----|-------------|------|
| `deepseek-v4-flash` | Flash | normal |
| `deepseek-v4-flash-thinking` | Flash | raciocínio |
| `deepseek-v4.1-flash` | Flash | normal (alias) |
| `deepseek-v4.1-flash-thinking` | Flash | raciocínio (alias) |
| `deepseek-v4-pro` | Pro/Expert | normal |
| `deepseek-v4-pro-thinking` | Pro/Expert | raciocínio |

O roteamento é pelo nome: contém `thinking` → ativa o modo de raciocínio; contém `pro` → usa o modelo Expert; caso contrário → Flash.

### `POST /v1/chat/completions`

Request no formato OpenAI padrão:

```json
{
  "model": "deepseek-v4-flash",
  "messages": [{ "role": "user", "content": "Olá!" }],
  "tools": [{
    "type": "function",
    "function": {
      "name": "get_weather",
      "description": "Obter previsão do tempo",
      "parameters": { "type": "object", "properties": { "location": { "type": "string" } }, "required": ["location"] }
    }
  }],
  "tool_choice": "auto",
  "stream": true
}
```

Resposta com tool call (`finish_reason: "tool_calls"`, `arguments` como string JSON):

```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [{
        "index": 0,
        "id": "call_xxx",
        "type": "function",
        "function": { "name": "get_weather", "arguments": "{\"location\":\"São Paulo\"}" }
      }]
    },
    "finish_reason": "tool_calls"
  }]
}
```

Para continuar a conversa, devolva o resultado como mensagem `role: "tool"` com o `tool_call_id` correspondente (formato OpenAI padrão).

### Como usar em clientes

```bash
curl http://localhost:3000/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"Olá!"}]}'
```

Em SDKs OpenAI, aponte o `baseURL` para `http://localhost:3000/v1`.

---

## 🔧 Tool calling — o que o proxy tolera

O proxy injeta as ferramentas declaradas pelo cliente no prompt e interpreta a resposta do modelo. Formatos aceitos:

- `<tool_call>{"name": "...", "arguments": {...}}</tool_call>` (canônico, incluindo variações `tool_calls`/`tool` e case-insensitive)
- **Vazamento DSML** do formato interno do DeepSeek (`<｜｜DSML｜｜ invoke name="...">` com `<parameter>`), convertido em tempo real
- JSON malformado: chaves/aspas faltando, arrays não fechados, JSON duplamente escapado
- Nomes fuzzy: `readFile` → `read_file` (caso único no schema)
- Chamadas sem tags (JSON cru no texto) e múltiplas chamadas por turno
- Tag de fechamento dentro de strings de argumentos (não trunca)

> **Importante:** as ferramentas são executadas **pelo cliente** (teu agente), não pelo proxy. O proxy só traduz o protocolo. Se um comando é bloqueado pelo modo de permissão do teu agente, é lá que se resolve.

---

## 🧪 Testes

```bash
npm test
```

95 testes cobrindo o parser de tool calls e a recuperação de JSON: streams fragmentados (até 1 char por chunk), tags dentro de strings, nomes fuzzy, tags faltando, chamadas sem wrapper, cap por turno, JSON duplamente escapado e mais.

---

## 🛠️ Scripts

| Comando | Descrição |
|---------|-----------|
| `npm start` | Servidor em produção |
| `npm run dev` | Desenvolvimento com hot-reload |
| `npm run login` | Login visível no navegador e persistência da sessão |
| `npm test` | Suite de testes |
| `npm run build` | Compila TypeScript para `dist/` |
| `bash restart-server.sh` | Reinício limpo do servidor |
| `bash clean-and-login.sh` | Limpa processos/locks e abre o login |

---

## 🔍 Troubleshooting

- **`Failed to create a ProcessSingleton`**: o perfil do navegador está em uso. Encerre o servidor (`bash restart-server.sh` ou `fuser -k 3000/tcp`) e remova `deepseek_profile/Singleton*` antes do login.
- **Porta 3000 ocupada por código antigo**: `fuser -k 3000/tcp` mata quem segura a porta (o processo filho do tsx sobrevive a pkill comum).
- **Agente "perde o contexto"**: procure linhas `[Compression]` no log do servidor — elas mostram exatamente o que foi mantido/descartado. Com `CONTEXT_TOKENS` alto, a compressão só entra acima do limite configurado.
- **`400 context_length_exceeded`**: o prompt (mesmo truncado) excede `CONTEXT_TOKENS`. Aumente o valor no `.env` ou reduza a conversa.
- **Tool call não chega estruturado**: verifique se o cliente está declarando as `tools` no request e rode o servidor com `TOOLCALL_DEBUG=1` para ver o parser em ação.

---

## 📄 Licença

Distribuído sob a licença MIT — veja [LICENSE](LICENSE).

---

## ⚠️ Disclaimer

> Este projeto é fornecido estritamente para fins educacionais e de pesquisa.

Automatização de serviços de terceiros pode violar os termos de uso da plataforma. O usuário é integralmente responsável pelo uso deste software, incluindo conformidade com leis, regulamentos e contratos de serviço aplicáveis. **Use por sua conta e risco.**

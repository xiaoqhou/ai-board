# Hermes + OpenCode Observability Integration Plan

## 1. Architecture Overview

The system has two independent components that both need LLM observability:

```
Local Machine (WSL/NixOS)                 Codespace (Linux)
┌──────────────────────────┐     ┌────────────────────────────┐
│  Hermes Agent            │     │  OpenCode Server (port 4096)│
│  ┌────────────────────┐  │     │  ┌──────────────────────┐  │
│  │ langfuse plugin    │  │     │  │ Built-in OTel Exporter│  │
│  │ (Python langfuse   │──┼─────┼──│ (OTLP HTTP)          │  │
│  │  SDK)              │  │     │  │                      │  │
│  └────────────────────┘  │     │  │ Big-Pickle LLM calls │  │
│                          │     │  └──────────────────────┘  │
└──────────────────────────┘     └────────────────────────────┘
           │                                │
           │          Langfuse Cloud         │
           └─────────── or Self-Host ────────┘
                               │
                    ┌──────────▼──────────┐
                    │    Langfuse         │
                    │  (OTLP receiver)    │
                    │  /api/public/otel   │
                    └─────────────────────┘
```

**Data flow:**
- **Hermes Agent** → Python `langfuse` SDK → Langfuse REST API (generations, spans, traces)
- **OpenCode** → OpenTelemetry OTLP HTTP → Langfuse OTLP endpoint (standard OTel spans with AI SDK attributes)

---

## 2. Hermes Agent Side (Already Working)

### 2.1 Existing Langfuse Plugin

Hermes Agent has a built-in langfuse plugin at `~/.hermes/hermes-agent/plugins/observability/langfuse/`.

**Plugin structure:**
```
plugins/observability/langfuse/
├── plugin.yaml          # Plugin manifest
├── __init__.py          # Plugin implementation
└── ...
```

**Hooks used by the plugin:**
| Hook | Purpose |
|---|---|
| `pre_llm_call` | Opens a Langfuse generation span before each LLM call |
| `post_llm_call` | Closes generation with token usage, cost, finish_reason |
| `pre_tool_call` | Starts tool observation with sanitized args |
| `post_tool_call` | Closes tool observation with result |
| `on_session_end` | Flushes traces |

### 2.2 Required Configuration

Set these in `~/.hermes/.env`:

```bash
# Langfuse credentials (Hermes-prefixed vars take priority)
HERMES_LANGFUSE_PUBLIC_KEY=pk-lf-xxxxx
HERMES_LANGFUSE_SECRET_KEY=sk-lf-xxxxx
HERMES_LANGFUSE_BASE_URL=https://cloud.langfuse.com

# Fallback (standard Langfuse vars)
LANGFUSE_PUBLIC_KEY=pk-lf-xxxxx
LANGFUSE_SECRET_KEY=sk-lf-xxxxx
LANGFUSE_BASE_URL=https://cloud.langfuse.com
```

Enable the plugin:

```bash
hermes plugins enable observability/langfuse
```

### 2.3 What Hermes Traces

- Each agent turn → one Langfuse trace
- Each LLM API call → one `generation` observation per turn
- Each tool invocation → one `tool` observation
- Session metadata → grouped via Langfuse session attributes
- Token counts, model IDs, latency, cost

---

## 3. OpenCode Side (Codespace)

### 3.1 Built-in OpenTelemetry Infrastructure

OpenCode (v1.14.35+) already has full OTel support with zero code changes required. Key files:

| File | Purpose |
|---|---|
| `packages/core/src/effect/observability.ts` | OTel SDK setup, OTLP exporter, context manager |
| `packages/opencode/src/session/llm.ts` | Passes `experimental_telemetry` to AI SDK `streamText()` |
| `packages/opencode/src/config/config.ts` | Config schema with `experimental.openTelemetry` flag |

**Existing OTel dependencies** (in `packages/opencode/package.json`):
```json
"@opentelemetry/api": "1.9.0",
"@opentelemetry/context-async-hooks": "2.6.1",
"@opentelemetry/exporter-trace-otlp-http": "0.214.0",
"@opentelemetry/sdk-trace-base": "2.6.1",
"@opentelemetry/sdk-trace-node": "2.6.1",
"@effect/opentelemetry": "catalog:"
```

### 3.2 How OpenCode Sends LLM Requests

All LLM calls go through **Vercel AI SDK** (`ai` package) via `streamText()`:

```
session/llm.ts:run()
  └─ streamText({
       model: wrapLanguageModel({ model: language, middleware: [...] }),
       messages: [...],
       tools: {...},
       experimental_telemetry: {
         isEnabled: cfg.experimental?.openTelemetry,
         functionId: "session.llm",
         tracer: telemetryTracer,  // Effect OTel tracer with session.id
         metadata: { userId, sessionId },
       },
     })
```

The model `big-pickle` is resolved through OpenCode's provider system (`packages/opencode/src/provider/provider.ts`), which uses `@ai-sdk/openai-compatible` or a custom provider to communicate with the model API.

### 3.3 OTel Exporter Configuration

The observability layer (`packages/core/src/effect/observability.ts`) creates:

1. **Trace exporter** — `OTLPTraceExporter` sending to `{OTEL_EXPORTER_OTLP_ENDPOINT}/v1/traces`
2. **Context manager** — `AsyncLocalStorageContextManager` for proper async context propagation
3. **Resource tags** — service name, version, deployment environment

**Activation logic:**
```typescript
const base = Flag.OTEL_EXPORTER_OTLP_ENDPOINT  // reads OTEL_EXPORTER_OTLP_ENDPOINT env var
export const enabled = !!base
// If OTEL_EXPORTER_OTLP_ENDPOINT is not set, telemetry layer is a no-op
```

### 3.4 AI SDK Span Attributes Emitted

When `experimental_telemetry` is enabled, the Vercel AI SDK automatically emits spans with these attributes:

| Attribute | Example |
|---|---|
| `ai.model.provider` | `openai-compatible` |
| `ai.model.id` | `opencode/big-pickle` |
| `ai.usage.promptTokens` | 1250 |
| `ai.usage.completionTokens` | 340 |
| `ai.usage.totalTokens` | 1590 |
| `ai.response.text` | (output text) |
| `ai.prompt.messages` | (JSON messages) |
| `ai.telemetry.metadata.userId` | `agent-codespace` |
| `ai.telemetry.metadata.sessionId` | `ses_xxx` |
| `ai.toolCall.toolName` | `read`, `bash`, `write` |
| Duration, temperature, topP, maxTokens | various |

### 3.5 Required Configuration for OpenCode

**Step 1: Enable OTel in config**

Edit `/workspaces/ai-codebox/.devcontainer/opencode.jsonc`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "opencode/big-pickle",
  "server": {
    "port": 4096,
    "hostname": "127.0.0.1"
  },
  "permission": "allow",
  "experimental": {
    "openTelemetry": true
  }
}
```

**Step 2: Set OTel environment variables**

```bash
# Langfuse OTLP endpoint (choose based on your Langfuse deployment)
# EU region:
export OTEL_EXPORTER_OTLP_ENDPOINT="https://cloud.langfuse.com/api/public/otel"

# US region:
# export OTEL_EXPORTER_OTLP_ENDPOINT="https://us.cloud.langfuse.com/api/public/otel"

# Self-hosted:
# export OTEL_EXPORTER_OTLP_ENDPOINT="http://your-langfuse:3000/api/public/otel"

# Auth header (base64 of "public_key:secret_key")
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(echo -n 'pk-lf-xxxxx:sk-lf-xxxxx' | base64 -w0)"

# Required for Langfuse OTLP ingestion versioning
export OTEL_EXPORTER_OTLP_HEADERS="${OTEL_EXPORTER_OTLP_HEADERS},x-langfuse-ingestion-version=4"

# Optional: resource attributes
export OTEL_RESOURCE_ATTRIBUTES="service.name=opencode-codespace,service.version=1.14.35,deployment.environment.name=production"
```

**Step 3: Restart OpenCode server**

```bash
# Stop existing server, then restart
opencode serve &
```

---

## 4. OpenLLMetry Integration Options

### 4.1 Option A: Direct OTel → Langfuse (Recommended)

**Skip OpenLLMetry entirely.** OpenCode's built-in OTel infrastructure already exports to any OTLP endpoint. Langfuse accepts OTel spans directly and maps them to its data model.

**Pros:**
- No code changes to OpenCode
- No additional dependencies
- Uses OpenCode's well-tested observability layer
- Works with the pre-installed Nix binary

**Cons:**
- AI SDK v3-v6 emits `ai.*` prefixed attributes (not `gen_ai.*` semantic conventions)
- Langfuse may not parse all `ai.*` attributes into its native models without `gen_ai.*` conventions

**Mitigation:** Langfuse's OTel ingestion explicitly handles `ai.*` prefixed spans from the Vercel AI SDK. It maps `ai.usage.promptTokens` → input tokens, `ai.usage.completionTokens` → output tokens, `ai.model.id` → model name, etc.

### 4.2 Option B: OpenCode Plugin with OpenLLMetry SDK (Advanced)

For richer span naming and `gen_ai.*` semantic conventions, create an OpenCode plugin that wraps the AI SDK with OpenLLMetry instrumentation.

**Approach:**
1. Create a plugin package that imports `@traceloop/node-server-sdk` before AI SDK modules
2. The plugin hooks into `"chat.params"` or `"experimental.chat.messages.transform"` to add custom telemetry
3. Configures OpenLLMetry to export to Langfuse

**Hook points** (from `@opencode-ai/plugin` SDK):
```typescript
export interface Hooks {
  "chat.params"?: (input: ChatParams) => Promise<void>  // Modify LLM parameters before sending
  "chat.headers"?: (input: ChatHeaders) => Promise<void> // Modify HTTP headers
  event?: (input: { event: Event }) => Promise<void>     // Listen to session events
}
```

**Sample plugin:**
```typescript
import * as traceloop from "@traceloop/node-server-sdk";
import type { Plugin } from "@opencode-ai/plugin";

// Initialize OpenLLMetry (must happen before AI SDK modules are loaded)
traceloop.initialize({
  appName: "opencode",
  apiEndpoint: process.env.OTEL_EXPORTER_OTLP_ENDPOINT,
  headers: { Authorization: `Basic ${...}` },
});

const plugin: Plugin = (input) => {
  return {
    "chat.params": async ({ params }) => {
      // OpenLLMetry auto-instruments AI SDK calls
      // Additional metadata can be added here
    },
  };
};

export default plugin;
```

**Pros:**
- Full `gen_ai.*` semantic conventions
- Custom span enrichment
- No modification to OpenCode core

**Cons:**
- Requires packaging npm plugin and loading it
- `@traceloop/node-server-sdk` must be initialized before AI SDK — initialization order matters
- Additional dependency

### 4.3 Option C: AI SDK v7 GenAIOpenTelemetryIntegration

If OpenCode upgrades to AI SDK v7+, use `@ai-sdk/otel` with `GenAIOpenTelemetryIntegration` for native `gen_ai.*` semantic conventions.

```typescript
import { registerTelemetryIntegration } from "ai";
import { GenAIOpenTelemetryIntegration } from "@ai-sdk/otel";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";

registerTelemetryIntegration(new GenAIOpenTelemetryIntegration());

// OTLP exporter already configured via observability.ts
```

**Status:** Not currently applicable — OpenCode is on AI SDK v6 (uses `experimental_telemetry`). Upgrade would require changes to OpenCode itself.

---

## 5. Integration Roadmap

### Phase 1: Direct OTel → Langfuse (Immediate)

| Task | Details |
|---|---|
| Create Langfuse account | Sign up at https://langfuse.com |
| Get API keys | Generate `pk-lf-xxx` (public) and `sk-lf-xxx` (secret) |
| Configure Hermes Agent | Set `HERMES_LANGFUSE_*` in `~/.hermes/.env`, enable plugin |
| Configure OpenCode codespace | Set env vars and update `opencode.jsonc` |
| Verify traces | Check Langfuse dashboard for spans from both sides |
| Set up alerts | Configure Langfuse latency/cost alerts if desired |

### Phase 2: Structured Observability (Medium-term)

| Task | Details |
|---|---|
| Create OpenCode plugin | Wrap `@traceloop/node-server-sdk` for enhanced span attributes |
| Link Hermes ↔ Codebox | Propagate trace context from Hermes API calls to codespace spans |
| Custom dashboards | Build Langfuse dashboards showing end-to-end agent performance |
| Cost tracking | Configure model pricing in Langfuse for accurate cost attribution |

### Phase 3: Advanced (Optional)

| Task | Details |
|---|---|
| Self-hosted Langfuse | Deploy Langfuse on your own infrastructure |
| Evaluations | Use Langfuse evaluation pipelines on traced data |
| Prompt management | Centralize prompts via Langfuse prompt management |

---

## 6. Key Code References (OpenCode)

| Component | GitHub Path |
|---|---|
| LLM call entry point | `packages/opencode/src/session/llm.ts` |
| OTel observability layer | `packages/core/src/effect/observability.ts` |
| OTel in CLI run | `packages/opencode/src/cli/cmd/run/otel.ts` |
| Config schema | `packages/opencode/src/config/config.ts` |
| Provider registry | `packages/opencode/src/provider/provider.ts` |
| Model ID types | `packages/opencode/src/provider/schema.ts` |
| Plugin SDK | `packages/plugin/src/index.ts` |
| Plugin host integration | `packages/opencode/src/plugin/` |
| Bootstrap runtime (wires OTel) | `packages/opencode/src/effect/bootstrap-runtime.ts` |
| Effect runtime (wires OTel) | `packages/core/src/effect/runtime.ts` |

---

## 7. Troubleshooting

### OpenCode side

| Symptom | Check |
|---|---|
| No traces in Langfuse | Is `OTEL_EXPORTER_OTLP_ENDPOINT` set? Check `opencode debug config` shows `experimental.openTelemetry: true` |
| 401 Unauthorized | Auth header format: `base64("pk-lf-xxx:sk-lf-xxx")` |
| 404 Not Found | Langfuse OTel endpoint is `/api/public/otel/v1/traces`. OpenCode sends to `{base}/v1/traces` — ensure base includes `/api/public/otel` |
| No spans with gen_ai.* | AI SDK v6 emits `ai.*` attributes. This is expected and Langfuse handles them. |

### Hermes Agent side

| Symptom | Check |
|---|---|
| Plugin not loaded | Run `hermes plugins list` — is `observability/langfuse` enabled? |
| No traces | Check `~/.hermes/.env` has the correct `HERMES_LANGFUSE_*` values |
| Import errors | Run `pip install langfuse` in the Hermes environment |

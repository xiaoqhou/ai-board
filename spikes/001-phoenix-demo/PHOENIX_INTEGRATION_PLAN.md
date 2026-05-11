# OpenCode LLM Token Usage → Phoenix Collector Integration Plan

## 1. Current State (What Works Already)

### Phoenix Collector
- Phoenix collector intended to run at `localhost:4317` (gRPC OTLP) with Web UI at `localhost:16006`
- Streamlit dashboard skeleton at `~/spikes/001-phoenix-demo/dashboard.py` — placeholder, not yet wired to Phoenix

### OpenCode
- OpenCode server runs at `localhost:4096` with model `opencode/big-pickle`
- Exposes `GET /session/{id}/message` — each assistant message includes `info.tokens`:
  ```
  info.tokens = { total: 1234, input: 1000, output: 234, reasoning: 50, cache: 200 }
  ```
- No OTLP export configured today; no spans emitted to Phoenix

### Hermes Agent
- Hermes Agent (the orchestrator) uses `minimax-m2.5-free` for its own LLM calls
- No OTel instrumentation currently — no spans emitted to Phoenix

### Summary Table

| Component | LLM Model | Status |
|-----------|-----------|--------|
| Phoenix Collector | — | Running at localhost:4317 / Web UI at 16006 |
| OpenCode | `opencode/big-pickle` | No OTLP export, token data in REST API |
| Hermes Agent | `minimax-m2.5-free` | No OTel instrumentation |
| Dashboard | — | Skeleton exists, not wired to Phoenix |

---

## 2. Overall Approach (Two Parts)

```
Part A ───────────────────────────────────────────────────────
OpenCode Token Collector Script
  Polls OpenCode REST API → builds OTel spans → exports via OTLP gRPC → Phoenix

Part B ───────────────────────────────────────────────────────
Hermes Agent OTel Instrumentation
  Python OTel SDK auto-instrumentation → exports via OTLP gRPC → Phoenix

Output ───────────────────────────────────────────────────────
Phoenix Web UI (localhost:16006) ← unifies spans from both agents
Streamlit Dashboard ← queries Phoenix for live token usage charts
```

### Why Two Parts?

- **Part A (Python script)** avoids modifying OpenCode's Node.js server. The script polls the existing REST API — zero changes to OpenCode internals.
- **Part B (Hermes Agent)** is pure Python, so we use standard `opentelemetry-python` instrumentation directly in the agent's LLM call path.

---

## 3. Part A — OpenCode Token Collector Script

### 3.1 Concept

A lightweight Python script that:
1. Polls OpenCode's session list (`GET /session`)
2. For each active/recent session, fetches messages (`GET /session/{id}/message`)
3. Finds assistant messages with `info.tokens`
4. Converts each into an OTel span (LLM span semantic conventions)
5. Exports spans via gRPC OTLP to `localhost:4317`

### 3.2 File to Create

**`~/spikes/001-phoenix-demo/opencode_collector.py`**

### 3.3 Pseudocode / Module Outline

```python
# opencode_collector.py
#
# Dependencies: opentelemetry-api, opentelemetry-sdk, opentelemetry-exporter-otlp-proto-grpc
#               httpx (for OpenCode REST API calls)

import httpx
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

# ── Config ──────────────────────────────────────────────────
OPENCODE_BASE = "http://localhost:4096"
PHOENIX_GRPC  = "http://localhost:4317"
POLL_INTERVAL = 5  # seconds

# ── OTel Setup ──────────────────────────────────────────────
provider = TracerProvider(resource=Resource.create({
    "service.name": "opencode-collector",
    "llm.model_id": "opencode/big-pickle",
    "llm.provider": "opencode",
}))
exporter = OTLPSpanExporter(endpoint=PHOENIX_GRPC, insecure=True)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# ── Session IDs known (tracked in memory) ───────────────────
# set of session IDs already processed
_seen_sessions: set[str] = set()

def fetch_recent_sessions() -> list[dict]:
    """GET /session → list of session metadata."""
    resp = httpx.get(f"{OPENCODE_BASE}/session")
    resp.raise_for_status()
    return resp.json()

def fetch_messages(session_id: str) -> list[dict]:
    """GET /session/{id}/message → list of messages."""
    resp = httpx.get(f"{OPENCODE_BASE}/session/{session_id}/message")
    resp.raise_for_status()
    return resp.json()

def extract_token_usage(msg: dict) -> dict | None:
    """Return {total, input, output, reasoning, cache} or None."""
    info = msg.get("info") or {}
    tokens = info.get("tokens")
    if tokens and isinstance(tokens, dict):
        return tokens
    return None

def build_span(session_id: str, msg: dict, tokens: dict):
    """Create and return an OTel span for a single assistant LLM call."""
    with tracer.start_as_current_span("llm.call") as span:
        span.set_attribute("llm.model_id", "opencode/big-pickle")
        span.set_attribute("llm.provider", "opencode")
        span.set_attribute("llm.token.total", tokens.get("total", 0))
        span.set_attribute("llm.token.input", tokens.get("input", 0))
        span.set_attribute("llm.token.output", tokens.get("output", 0))
        span.set_attribute("llm.token.reasoning", tokens.get("reasoning", 0))
        span.set_attribute("llm.token.cache", tokens.get("cache", 0))
        span.set_attribute("session.id", session_id)
        span.set_attribute("llm.response.id", msg.get("id", ""))
        # Duration could be computed if message timestamps are available
        return span

def poll_loop():
    """Main loop: fetch sessions → fetch messages → emit spans."""
    while True:
        sessions = fetch_recent_sessions()
        for sess in sessions:
            sid = sess.get("id") or sess.get("sessionId")
            if not sid or sid in _seen_sessions:
                continue
            messages = fetch_messages(sid)
            for msg in messages:
                tokens = extract_token_usage(msg)
                if tokens:
                    build_span(sid, msg, tokens)
            _seen_sessions.add(sid)
        time.sleep(POLL_INTERVAL)
```

### 3.4 Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Poll vs. WebSocket | Poll (5s) | OpenCode REST API is simple; no WebSocket for message events |
| OTLP transport | gRPC | Phoenix recommends gRPC for lower overhead; HTTP fallback if gRPC unavailable |
| Session tracking | In-memory set | Lightweight; for production, use a persistent offset (file/DB) |
| Span naming | `llm.call` | Aligns with OpenTelemetry gen-ai semantic conventions |
| Batch export | BatchSpanProcessor | Default; avoids flooding Phoenix on burst |

### 3.5 Installation

```bash
pip install opentelemetry-api \
            opentelemetry-sdk \
            opentelemetry-exporter-otlp-proto-grpc \
            httpx
```

### 3.6 Running

```bash
python ~/spikes/001-phoenix-demo/opencode_collector.py
```

---

## 4. Part B — Hermes Agent OTel Instrumentation

### 4.1 Concept

Add OpenTelemetry instrumentation directly into Hermes Agent's Python LLM call path. Hermes Agent makes HTTP calls to the `minimax-m2.5-free` API — we instrument the HTTP client or the LLM wrapper function.

### 4.2 File to Create / Modify

- **Create:** `~/.hermes/hermes-agent/plugins/observability/opentelemetry/__init__.py`
- **Create:** `~/.hermes/hermes-agent/plugins/observability/opentelemetry/plugin.yaml`

### 4.3 Plugin Structure

```
~/.hermes/hermes-agent/plugins/observability/opentelemetry/
├── plugin.yaml
└── __init__.py
```

**`plugin.yaml`:**
```yaml
name: opentelemetry
description: Export LLM call spans to Phoenix via OTLP
hooks:
  - pre_llm_call
  - post_llm_call
```

**`__init__.py` — Pseudocode:**
```python
# ── OTel Setup ──────────────────────────────────────────────
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

provider = TracerProvider(resource=Resource.create({
    "service.name": "hermes-agent",
    "llm.model_id": "minimax-m2.5-free",
    "llm.provider": "minimax",
}))
provider.add_span_processor(BatchSpanProcessor(
    OTLPSpanExporter(endpoint="http://localhost:4317", insecure=True)
))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# ── Hooks ───────────────────────────────────────────────────
_current_span = None

def pre_llm_call(params: dict) -> None:
    global _current_span
    span = tracer.start_span("llm.call")
    span.set_attribute("llm.model_id", "minimax-m2.5-free")
    span.set_attribute("llm.provider", "minimax")
    # Optionally record prompt length / message count
    span.set_attribute("llm.request.messages", len(params.get("messages", [])))
    _current_span = span

def post_llm_call(result: dict) -> None:
    global _current_span
    if _current_span is None:
        return
    # Extract token usage from result
    usage = result.get("usage") or {}
    _current_span.set_attribute("llm.token.total", usage.get("total_tokens", 0))
    _current_span.set_attribute("llm.token.input", usage.get("prompt_tokens", 0))
    _current_span.set_attribute("llm.token.output", usage.get("completion_tokens", 0))
    _current_span.set_attribute("llm.response.finish_reason", result.get("finish_reason", ""))
    _current_span.end()
    _current_span = None
```

### 4.4 Hermes Agent Hook API (Assumed Interface)

Based on the existing Langfuse plugin:
- `pre_llm_call(params)` → called before each LLM HTTP request with params dict
- `post_llm_call(result)` → called after response with result dict including `usage`, `finish_reason`
- The hook signature should be verified against the actual Hermes plugin SDK

### 4.5 Enabling

```bash
hermes plugins enable observability/opentelemetry
```

### 4.6 Dependencies

```bash
pip install opentelemetry-api \
            opentelemetry-sdk \
            opentelemetry-exporter-otlp-proto-grpc
```

---

## 5. Files to Create / Modify (Summary)

| # | File | Action | Purpose |
|---|------|--------|---------|
| 1 | `~/spikes/001-phoenix-demo/opencode_collector.py` | **Create** | Polls OpenCode REST API, emits OTel spans to Phoenix |
| 2 | `~/.hermes/hermes-agent/plugins/observability/opentelemetry/plugin.yaml` | **Create** | Plugin manifest for Hermes Agent OTel plugin |
| 3 | `~/.hermes/hermes-agent/plugins/observability/opentelemetry/__init__.py` | **Create** | Plugin implementation: OTel setup + hooks |
| 4 | `~/spikes/001-phoenix-demo/dashboard.py` | **Modify** | Wire Streamlit dashboard to Phoenix queries |
| 5 | `~/spikes/001-phoenix-demo/requirements.txt` | **Create** | Python dependencies for collector + dashboard |

---

## 6. Validation Steps

### 6.1 Verify Phoenix is Running

```bash
# Check Phoenix Web UI
curl -s http://localhost:16006 | head -5

# Check gRPC OTLP endpoint
grpcurl -plaintext localhost:4317 list
# Expect: opentelemetry.proto.collector.trace.v1.TraceService
```

### 6.2 Validate Part A (OpenCode Collector)

```bash
# 1. Start the collector
python ~/spikes/001-phoenix-demo/opencode_collector.py &

# 2. Trigger an OpenCode LLM call (via API)
curl -X POST http://localhost:4096/api/chat \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"say hi"}]}'

# 3. Wait 5-10s for poll cycle, then check Phoenix
#    → Phoenix Web UI at http://localhost:16006 should show a span
#    → Span attributes should include llm.token.total, llm.token.input, etc.

# 4. Check collector logs for errors
```

### 6.3 Validate Part B (Hermes Agent)

```bash
# 1. Enable the plugin
hermes plugins enable observability/opentelemetry

# 2. Run a Hermes agent task
hermes run "say hello"

# 3. Check Phoenix Web UI for spans from service "hermes-agent"
#    → Span attributes should include llm.token.* for minimax-m2.5-free
```

### 6.4 Validate Dashboard

```bash
streamlit run ~/spikes/001-phoenix-demo/dashboard.py
# → Should show token usage charts aggregated from both agents
```

### 6.5 Unified View in Phoenix

After both parts are running:
- **Service: `opencode-collector`** → spans for `opencode/big-pickle` LLM calls
- **Service: `hermes-agent`** → spans for `minimax-m2.5-free` LLM calls
- Phoenix trace view shows both in a single project/dataset

---

## 7. Open Questions

1. **Hermes Agent hook interface** — What exactly is the `params` dict shape in `pre_llm_call`, and the `result` dict shape in `post_llm_call`? Need to verify against actual Hermes plugin SDK source.

2. **Plugin directory location** — Is `~/.hermes/hermes-agent/plugins/` the correct path, or does Hermes use a different plugin discovery mechanism?

3. **OpenCode session list API** — Does `GET /session` return recent sessions, or just active ones? Do we need `GET /session?limit=50` or similar? What's the session lifecycle?

4. **Message timestamps** — Does `GET /session/{id}/message` return timestamps per message? Needed for accurate span duration computation.

5. **gRPC vs HTTP OTLP** — Does the Phoenix collector (localhost:4317) exclusively use gRPC, or does it also accept HTTP OTLP on a different port? Check: Phoenix typically uses 4317 (gRPC) and 4318 (HTTP).

6. **Hermes Agent token usage** — Does `minimax-m2.5-free` return standard `usage` fields (`prompt_tokens`, `completion_tokens`, `total_tokens`)? Need to verify the response schema.

7. **Seen sessions persistence** — If the collector restarts, should it re-process old sessions? Currently in-memory set means a restart = re-process all sessions visible at that time. Acceptable for prototyping.

8. **Span naming convention** — Use `llm.call` or follow the OpenTelemetry Semantic Conventions for GenAI (`gen_ai.content_prompt`, `gen_ai.completion`, etc.)? Phoenix may map `gen_ai.*` attributes better than custom `llm.*` ones.

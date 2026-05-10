# OpenLLMetry (Traceloop) Research Summary

## 1. What is OpenLLMetry?

OpenLLMetry is an **open-source observability project** (Apache 2.0, built and maintained by **Traceloop**) that provides tracing and monitoring for LLM applications. It is built **on top of OpenTelemetry (OTel)** and emits standard OTLP data, meaning it can connect to **any OpenTelemetry-compatible backend** without vendor lock-in.

**GitHub:** https://github.com/traceloop/openllmetry

### Key Concepts

- **Non-intrusive tracing** — auto-instruments LLM calls, vector DB calls, and framework operations with a single init call
- **Standard OTLP** — exports OpenTelemetry trace data; works with any OTLP-compatible backend
- **SDKs available** for Python, TypeScript/Node.js, Go (beta), Ruby (beta)
- **No vendor lock-in** — you can export to Traceloop Cloud, self-hosted backends (Jaeger, Grafana Tempo), or managed observability platforms (Datadog, Honeycomb, New Relic, etc.)

## 2. How It Works

OpenLLMetry works by:

1. **Auto-instrumenting** popular LLM SDKs (OpenAI, Anthropic, etc.), vector DBs (Pinecone, Chroma, Qdrant, etc.), and frameworks (LangChain, LlamaIndex, etc.) via OpenTelemetry instrumentation packages
2. **Creating spans** for each LLM call, retrieval operation, or chain step — capturing prompts, completions, token usage, latency, and metadata
3. **Exporting spans** via OTLP protocol to a configured backend (Traceloop Cloud, OTEL Collector, or directly to a compatible platform)
4. **Optional manual annotations** using `@workflow`, `@task`, `@agent`, `@tool` decorators to enrich traces with higher-level application structure

### Architecture

```
Your App (LLM calls, chains, agents)
    |
    v
Traceloop SDK (auto-instrumentation)
    |
    v
OTLP Exporter (HTTP/gRPC)
    |
    +---> Traceloop Cloud
    +---> OpenTelemetry Collector ---> Any backend (Jaeger, Tempo, Datadog, etc.)
    +---> Direct to backend (Honeycomb, New Relic, LangSmith, etc.)
```

## 3. Installation & Basic Usage

### Python

```bash
pip install traceloop-sdk
```

Minimal setup:

```python
from traceloop.sdk import Traceloop

Traceloop.init()  # auto-instruments all supported LLM/framework calls
```

With configuration:

```python
from traceloop.sdk import Traceloop

Traceloop.init(
    app_name="my-llm-app",
    disable_batch=True,        # for local development
)
```

### TypeScript / Node.js

```bash
npm install @traceloop/node-server-sdk
```

```typescript
import * as traceloop from "@traceloop/node-server-sdk";

traceloop.initialize({
    appName: "my-llm-app",
    disableBatch: true,  // for local development
});
```

> **Important:** The SDK must be imported before importing any LLM modules (OpenAI, LangChain, etc.) for auto-instrumentation to work.

### Go (beta)

```bash
go get github.com/traceloop/go-server-sdk
```

## 4. Manual Annotations (Workflows, Tasks, Agents, Tools)

For richer traces beyond auto-instrumentation, use decorators:

```python
from traceloop.sdk import Traceloop
from traceloop.sdk.decorators import workflow, task, agent, tool

Traceloop.init(app_name="joke_service")

@task(name="create_joke")
def create_joke():
    # LLM call is auto-instrumented
    return client.chat.completions.create(...)

@task(name="translate_joke")
def translate_joke(joke: str):
    return client.chat.completions.create(...)

@workflow(name="joke_pipeline", version=2)
def joke_workflow():
    joke = create_joke()
    return translate_joke(joke)
```

For agents:

```python
@agent(name="research_agent")
def research_agent(query: str):
    # agent logic
    search_tool(query)
    return llm_call(query)

@tool(name="web_search")
def search_tool(query: str):
    # tool implementation
    ...
```

In TypeScript:

```typescript
import * as traceloop from "@traceloop/node-server-sdk";

class MyService {
    @traceloop.workflow({ name: "joke_creation" })
    async createJoke() {
        // ...
    }
}

// Or without decorators:
await traceloop.withWorkflow({ name: "my_workflow" }, async () => {
    // ...
});
```

## 5. Supported Backends (Export Destinations)

The SDK routes traces via two env vars: `TRACELOOP_BASE_URL` (OTLP endpoint) and `TRACELOOP_HEADERS` (auth headers).

### Traceloop Cloud (default)

```bash
export TRACELOOP_API_KEY=your_api_key
# No need to set BASE_URL — defaults to https://api.traceloop.com
```

### LangSmith

```bash
export TRACELOOP_BASE_URL=https://api.smith.langchain.com/otel
export TRACELOOP_HEADERS="x-api-key=<LANGSMITH_API_KEY>"
```

### OpenTelemetry Collector (generic)

```bash
export TRACELOOP_BASE_URL=https://<otel-collector-hostname>:4318
```

Then configure the collector to forward to any backend (Jaeger, Tempo, etc.).

### Jaeger (self-hosted)

Run Jaeger with OTLP receiver:

```bash
docker run -d --name jaeger \
  -p 4317:4317 -p 4318:4318 -p 16686:16686 \
  jaegertracing/all-in-one:latest
```

```bash
export TRACELOOP_BASE_URL=http://localhost:4318
```

### Datadog

```bash
# Via Datadog Agent (requires OTLP HTTP receiver enabled)
export TRACELOOP_BASE_URL=http://<datadog-agent-hostname>:4318

# Or via OTEL Collector
export TRACELOOP_BASE_URL=https://<otel-collector>:4318
```

### Honeycomb

```bash
export TRACELOOP_BASE_URL=https://api.honeycomb.io
export TRACELOOP_HEADERS="x-honeycomb-team=<YOUR_API_KEY>"
```

### New Relic

```bash
export TRACELOOP_BASE_URL=https://otlp.nr-data.net:443
export TRACELOOP_HEADERS="api-key=<YOUR_NEWRELIC_LICENSE_KEY>"
```

### Grafana Cloud Tempo

```bash
export TRACELOOP_BASE_URL=https://otlp-gateway-<zone>.grafana.net/otlp
export TRACELOOP_HEADERS="Authorization=Basic%20<base64(stack_id:api_key)>"
```

### Dynatrace / Splunk / Instana / Highlight

All supported via the OTEL Collector or direct OTLP endpoints.

### Summary Table

| Backend | TRACELOOP_BASE_URL | Auth Method |
|---------|-------------------|-------------|
| Traceloop Cloud | `https://api.traceloop.com` (default) | `TRACELOOP_API_KEY` |
| LangSmith | `https://api.smith.langchain.com/otel` | Header `x-api-key` |
| Jaeger | `http://localhost:4318` | None (local) |
| Datadog | `http://<agent>:4318` | None (agent-side) |
| Honeycomb | `https://api.honeycomb.io` | Header `x-honeycomb-team` |
| New Relic | `https://otlp.nr-data.net:443` | Header `api-key` |
| Grafana Tempo | `https://otlp-gateway-<zone>.grafana.net/otlp` | Basic Auth |
| OTEL Collector | `https://<collector>:4318` | Configurable |

## 6. Framework Integrations

OpenLLMetry auto-instruments the following frameworks (Python & TS):

| Framework | Python | TypeScript |
|-----------|--------|------------|
| LangChain | ✅ | ✅ |
| LlamaIndex | ✅ | ✅ |
| CrewAI | ✅ | ❌ |
| Haystack | ✅ | ❌ |
| LiteLLM | ✅ | ❌ |
| LangGraph | ✅ | ❌ |
| OpenAI Agents | ✅ | ❌ |
| Agno | ✅ | ❌ |
| AWS Strands | ✅ | ❌ |
| Burr | ✅ | ❌ |
| MCP | ✅ | ❌ |

### LLM Providers Instrumented

OpenAI, Azure OpenAI, Anthropic, Google Gemini, Vertex AI, Amazon Bedrock, Amazon SageMaker, Cohere, Mistral AI, Ollama, Groq, HuggingFace, IBM watsonx, Aleph Alpha, Replicate, Together AI, WRITER.

### Vector DBs Instrumented

Chroma DB, Pinecone, Qdrant, Weaviate, Milvus, pgvector, LanceDB, Marqo, Elasticsearch.

### Example: LangChain

```python
from langchain.chains import LLMChain
from langchain_community.chat_models import ChatOpenAI
from traceloop.sdk import Traceloop

Traceloop.init(app_name="langchain_app")

# All chains are automatically traced
chain = LLMChain(llm=ChatOpenAI(), prompt=prompt)
result = chain.run("Hello")
```

### Example: LlamaIndex

```python
from llama_index.core import VectorStoreIndex
from traceloop.sdk import Traceloop

Traceloop.init(app_name="llamaindex_rag")

# All queries are automatically traced
index = VectorStoreIndex.from_documents(documents)
response = index.as_query_engine().query("What is X?")
```

### Using Without the SDK (Standalone Instrumentations)

If you already use OpenTelemetry, you can install individual instrumentation packages:

```bash
pip install opentelemetry-instrumentation-openai
pip install opentelemetry-instrumentation-langchain
pip install opentelemetry-instrumentation-chromadb
```

```python
from opentelemetry.instrumentation.openai import OpenAIInstrumentor

OpenAIInstrumentor().instrument()
```

## 7. Configuration Options

| Env Variable | Default | Description |
|-------------|---------|-------------|
| `TRACELOOP_API_KEY` | — | API key for Traceloop Cloud |
| `TRACELOOP_BASE_URL` | `https://api.traceloop.com` | OTLP endpoint |
| `TRACELOOP_HEADERS` | — | Custom HTTP headers for auth |
| `TRACELOOP_TRACE_CONTENT` | `true` | Log prompts/completions in spans |
| `TRACELOOP_TELEMETRY` | `true` | Anonymous usage telemetry |

## 8. Architecture Principles

- **Based on OpenTelemetry** — uses standard OTLP HTTP/gRPC protocol, standard span attributes, and semantic conventions
- **Extends OTel with GenAI conventions** — adds LLM-specific span attributes (prompt, completion, token counts, model name, temperature, etc.)
- **Zero vendor lock-in** — because it emits standard OTel data, you can switch backends at any time by changing env vars
- **Cost**: SDK is free (Apache 2.0). Traceloop Cloud has a free tier (50k spans/month). Self-hosted backends cost only infrastructure.

## 9. Comparison with Alternatives

| Feature | OpenLLMetry | LangSmith | Arize Phoenix | Langfuse |
|---------|-------------|-----------|---------------|----------|
| Open Source | ✅ (Apache 2.0) | ❌ (proprietary) | ✅ | ✅ (MIT/EULA) |
| Backend Agnostic | ✅ (OTLP) | ❌ (LangSmith only) | ❌ (Phoenix only) | ❌ (Langfuse only) |
| Auto-Instrumentation | ✅ | Partial | ✅ | ✅ |
| Framework Support | 10+ | LangChain-centric | 5+ | 5+ |
| Pricing | Free SDK + cloud free tier | $39/seat | Free self-hosted | Free tier + paid |

## 10. Full Python Example

```python
import os
from openai import OpenAI
from traceloop.sdk import Traceloop
from traceloop.sdk.decorators import workflow, task

Traceloop.init(app_name="demo_app", disable_batch=True)

client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])

@task(name="generate_joke")
def generate_joke(topic: str):
    return client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": f"Tell me a joke about {topic}"}],
    ).choices[0].message.content

@task(name="rate_joke")
def rate_joke(joke: str):
    return client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": f"Rate this joke 1-10: {joke}"}],
    ).choices[0].message.content

@workflow(name="joke_workflow")
def tell_joke(topic: str):
    joke = generate_joke(topic)
    rating = rate_joke(joke)
    return f"{joke}\n\nRating: {rating}"

if __name__ == "__main__":
    print(tell_joke("OpenTelemetry"))
```

## 11. Key Takeaways

- **One line to start**: `Traceloop.init()` is all you need for auto-instrumentation
- **Built on OpenTelemetry**: standard OTLP output = works with any OTel-compatible backend
- **No lock-in**: switch between Traceloop Cloud, LangSmith, Datadog, Jaeger, etc. by changing env vars
- **Rich annotations**: `@workflow`, `@task`, `@agent`, `@tool` decorators for structured traces
- **Broad ecosystem**: supports 16+ LLM providers, 8+ vector DBs, 10+ frameworks
- **Languages**: Python (mature), TypeScript (mature), Go/Ruby (beta)

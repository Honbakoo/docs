# ADR-0005 — REST stateless, OpenAPI 3.1, erros e idempotência

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `API_SPECIFICATION.md` §1, §4.3 e §4.4

## Contexto

A API era descrita em prosa. Sem contrato executável, frontend e backend divergem; sem modelo de erro e idempotência, retries de rede duplicam comentários, reações e uploads.

## Como o mercado faz

- **Stripe:** REST, OpenAPI, erros tipados, `Idempotency-Key`, webhooks assinados e versionamento.
- **GitHub:** REST + GraphQL, cursores, rate limit headers e versionamento por mídia.
- **MangaDex:** API REST pública, documentação e limites de uso.
- **Apps de chat:** WebSocket para tempo real.

## O que copiamos

- REST stateless sobre HTTP/2 ou HTTP/3.
- **OpenAPI 3.1** como fonte de verdade, com lint e diff de breaking changes no CI.
- Envelope de erro único (`code`, `message`, `details`, `request_id`).
- `Idempotency-Key` em mutações críticas.
- Headers de rate limit (`X-RateLimit-*`, `Retry-After`).
- Webhooks assinados para billing/ingest.

## O que não copiamos

- GraphQL como API pública.
- WebSocket para comentários/notificações.
- gRPC público no MVP.
- Erros ad hoc por endpoint.

## Decisão

1. `api/openapi.yaml` é o contrato; a prosa em `API_SPECIFICATION.md` explica o racional.
2. Toda mutação `POST` crítica aceita `Idempotency-Key`; replay devolve a mesma resposta por 24h.
3. Toda resposta inclui `request_id` (corpo de erro e header `X-Request-Id`).
4. Versionamento por path (`/api/v1`); breaking change exige `/v2` ou período de depreciação.
5. Webhooks usam HMAC e tabela `webhook_events` para deduplicação.

## Consequências

- **Positivas:** clientes previsíveis, retries seguros, contrato testável, integração mais simples.
- **Negativas:** disciplina de spec e CI; idempotência exige storage com TTL.
- **Operacionais:** spec quebrada bloqueia merge; clientes gerados precisam ser regenerados.

## Gatilho de revisão

- Necessidade de agregação complexa por cliente (avaliar BFF/GraphQL interno, sem substituir a API pública).
- Requisito de tempo real (avaliar SSE antes de WebSocket).

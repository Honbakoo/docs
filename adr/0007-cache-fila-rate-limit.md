# ADR-0007 — Cache, fila e rate limit: in-process vs Redis/Asynq

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `ARCHITECTURE.md` §7.1, §8.2 e §8.3; `API_SPECIFICATION.md` §4.1

## Contexto

Cache, fila e rate limit são necessários em qualquer escala, mas Redis + Asynq + workers não cabem com folga em 512MB. O projeto precisa dos dois mundos sem duplicar a API.

## Como o mercado faz

- **SaaS típico:** Redis obrigatório para cache/sessão/rate limit; Sidekiq/Celery/Asynq para jobs.
- **Self-hosted pequeno:** cache em memória, fila no processo, rate limit local.
- **Grandes plataformas:** Redis Cluster, Kafka, filas gerenciadas.

## O que copiamos

- Redis/KeyDB no `scale` para cache compartilhado, contadores e rate limit.
- Asynq no `scale` para jobs com retry/visibilidade.
- Token bucket/GCRA e headers `X-RateLimit-*`.
- `singleflight` + cache curto com jitter contra thundering herd.
- `GETDEL`/Lua para flush atômico de views.

## O que não copiamos

- Redis obrigatório no `budget`.
- Kafka ou fila distribuída no MVP.
- Lock distribuído para tudo (só onde há efeito colateral duplicável).

## Decisão

1. Interfaces `Cache`, `Queue` e `RateLimiter` no domínio.
2. `budget`: `ristretto`, worker pool in-process, token bucket em memória.
3. `scale`: Redis/KeyDB, Asynq, rate limit compartilhado.
4. `singleflight` é por processo; no `scale` é complementado por cache Redis de 5–30s com jitter.
5. **Circuit Breaker no Cache/Redis (Anti-Cascading Failure):** No perfil `scale`, chamadas ao Redis têm timeout rígido de 50ms. Se o Redis falhar ou estiver inacessível, o Circuit Breaker abre, a aplicação faz fallback transparente para busca direta no PostgreSQL (degradada porém viva) e o rate-limiting comuta temporariamente para memória local, impedindo que a queda do Redis derrube o site.
6. Flush de views usa `GETDEL` + `UPSERT` em `manga_view_daily` e lock de job.

## Consequências

- **Positivas:** custo mínimo no budget, caminho de escala claro, sem Kafka.
- **Negativas:** cache/fila in-process não sobrevivem a restart e não são compartilhados; duas implementações para testar.
- **Operacionais:** no budget, reinício perde contadores de view ainda não flushados; o shutdown gracioso mitiga.

## Gatilho de revisão

- Budget com mais de uma réplica.
- Necessidade de jobs duráveis/retry no budget.
- Rate limit precisar ser global no budget.

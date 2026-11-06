# ADR-0003 — Perfil dual `budget`/`scale` e dependências opcionais

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `ARCHITECTURE.md` §1, §7.1; `API_SPECIFICATION.md` §4.1

## Contexto

O público-alvo inclui operadores em VPS de 1 vCPU / 512MB–1GB. Ao mesmo tempo, o projeto precisa escalar horizontalmente sem reescrever a arquitetura. Redis, Asynq e S3 não podem ser obrigatórios no modo barato.

## Como o mercado faz

- **Stacks SaaS típicas:** Redis obrigatório para cache/sessão/fila, S3 obrigatório, workers separados.
- **Projetos self-hosted:** SQLite + disco local, com limitações de escala.
- **Plataformas grandes:** Redis Cluster, Kafka, object storage e múltiplos serviços.

## O que copiamos

- Perfil explícito de implantação (`HONBAKOO_PROFILE=budget|scale`).
- Interfaces para `Cache`, `Queue`, `RateLimiter` e `Storage`.
- Implementações in-process no budget e Redis/Asynq/S3 no scale.
- Postgres tunado para pouca RAM no budget.

## O que não copiamos

- Redis obrigatório no budget.
- Kafka, service mesh ou Kubernetes como pré-requisito.
- Duas bases de código: o perfil é configuração, não fork.

## Decisão

1. **Topologia Unificada no `budget`:** O binário suporta execução combinada all-in-one (`--role=all`) onde API e workers rodam no mesmo processo compartilhado.
2. **Fila Durável Compartilhada no `budget` via PostgreSQL (`SKIP LOCKED`):** Em vez de canais em memória voláteis que se perdem no restart e não combinam com processos separados, o `budget` adota fila transacional durável no próprio banco de dados (`table job_queue` com `FOR UPDATE SKIP LOCKED`).
3. `scale` comuta a fila para Redis/KeyDB + Asynq, storage para S3/R2/B2 e workers distribuídos em nós separados.
4. `CACHE_DRIVER=memory|redis` e `STORAGE_DRIVER=local|s3` são as chaves de troca.
5. O contrato HTTP é idêntico nos dois perfis; muda a implementação de infraestrutura, não a API.

## Consequências

- **Positivas:** custo mínimo real, sem perda de jobs no restart do budget, sem necessidade de Redis em 512MB de RAM, caminho de upgrade claro.
- **Negativas:** duas implementações para testar (`job_queue` Postgres vs Asynq Redis).
- **Operacionais:** CI precisa rodar a suíte nos dois perfis (ou ao menos nos pontos de interface).

## Gatilho de revisão

- Budget precisar de mais de uma réplica.
- Fila in-process deixar de ser durável o suficiente.
- Consumo de RAM do budget passar de 1GB com carga real.

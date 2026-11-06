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

1. `budget` é o padrão: cache LRU (`ristretto`), fila in-process, views em memória, rate limit em memória, storage local com `sendfile`.
2. `scale` habilita Redis/KeyDB, Asynq, S3/R2/B2 e workers distribuídos.
3. `CACHE_DRIVER=memory|redis` e `STORAGE_DRIVER=local|s3` são as chaves de troca.
4. O contrato HTTP é idêntico nos dois perfis; muda a implementação, não a API.

## Consequências

- **Positivas:** custo mínimo real, instalação de um comando, caminho de upgrade claro.
- **Negativas:** duas implementações para testar; o budget é single-node e perde cache/fila ao reiniciar.
- **Operacionais:** CI precisa rodar a suíte nos dois perfis (ou ao menos nos pontos de interface).

## Gatilho de revisão

- Budget precisar de mais de uma réplica.
- Fila in-process deixar de ser durável o suficiente.
- Consumo de RAM do budget passar de 1GB com carga real.

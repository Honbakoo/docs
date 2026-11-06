# ADR-0011 — Observabilidade, backup/restore, CI/CD e supply chain

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `ARCHITECTURE.md` §9 e §10; `API_SPECIFICATION.md` §4.5

## Contexto

O projeto é feito para operadores individuais. Sem métricas, backup testado e pipeline, o "budget mode" vira uma caixa-preta que ninguém consegue diagnosticar ou restaurar.

## Como o mercado faz

- **SaaS maduro:** Prometheus/Grafana, tracing, SLOs, backups com restore drill, CI/CD, SBOM e image scanning.
- **Projetos pequenos:** logs no stdout, backup manual, deploy por `git pull`.
- **Grandes plataformas:** observabilidade distribuída, chaos engineering, multi-region.

## O que copiamos

- Logs estruturados (`slog`) com `request_id`.
- Métricas Prometheus: latência, status, pool PG, cache hit/miss, fila, lag do flush.
- `/healthz` (liveness) e `/readyz` (readiness).
- Backup `pg_dump`/WAL + teste de restore periódico.
- CI com fmt/vet/test/race, `sqlc diff`, lint de migration, build multi-arch.
- Trivy/SBOM e imagens reproduzíveis.
- Migrations com `down` e padrão expand/contract.

## O que não copiamos

- Observabilidade como "depois".
- Deploy manual sem pipeline.
- Backup nunca testado.
- Stack de observabilidade pesada no budget (Grafana Cloud free/Loki opcional).

## Decisão

1. P1 inclui observabilidade mínima, backup/restore e CI/CD antes do primeiro deploy real.
2. Todo request tem `request_id`; todo erro o devolve.
3. Métricas são expostas em `/metrics` apenas na rede interna/admin.
4. Backup diário + WAL; restore drill trimestral documentado em runbook.
5. Migrations são versionadas, com `down` e revisão de lock.
6. Imagens passam por scan; SBOM é anexado ao release.

## Consequências

- **Positivas:** incidentes diagnosticáveis, dados recuperáveis, releases reproduzíveis.
- **Negativas:** custo de setup e disciplina; mais um passo no deploy.
- **Operacionais:** alertas precisam de thresholds reais; backup sem restore testado não conta.

## Gatilho de revisão

- Primeiro deploy em produção.
- SLO definido e violado.
- Necessidade de multi-region/DR.

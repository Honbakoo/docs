# 🗺️ Honbakoo Roadmap

> **Status:** P0 concluído nos documentos. P1 é pré-requisito do MVP; P2 só entra com gatilho.

---

## 1. Critério de prioridade

| Nível | Significado | Consequência |
| :--- | :--- | :--- |
| **P0** | quebra o modelo se implementado como estava | corrigir antes de codar |
| **P1** | bloqueia a primeira versão utilizável ou cria risco operacional alto | entra antes do MVP |
| **P2** | melhoria de produto/escala | entra depois do MVP, com gatilho |

---

## 2. P0 — concluído

- Mídia content-addressed, CDN imutável e assinatura no manifesto.
- Cursor keyset opaco; sem `LIMIT/OFFSET` público.
- `ltree` + `parent_id` para comentários.
- Constraints de capítulos, rating, histórico e VIP.
- Redis opcional no budget; API/worker separados por papel.
- API keys, retenção/LGPD e documentação operacional (este ciclo).

---

## 3. P1 — antes do MVP

| # | Entrega | Critério de aceite | Depende de |
| :--- | :--- | :--- | :--- |
| 1 | **OpenAPI 3.1 executável** | `api/openapi.yaml` lintado; contrato gera cliente; CI valida request/response | — |
| 2 | **Erros + idempotência** | envelope único; `Idempotency-Key` em mutações; replay e conflito testados | 1 |
| 3 | **Observabilidade** | `/healthz`, `/readyz`, `/metrics`; logs JSON; SLOs e alertas | 1 |
| 4 | **Backup/restore** | dump diário; restore testado mensalmente; RPO/RTO documentados | — |
| 5 | **CI/CD + supply chain** | fmt/vet/test/race; `sqlc diff`; migration `up/down`; Trivy/SBOM | 1 |
| 6 | **Testes de integração** | Testcontainers Postgres/Redis/MinIO; fluxos E2E | 1 |
| 7 | **Segurança de upload** | magic bytes, pixels, EXIF, hash, blacklist; testes de abuso | 1 |
| 8 | **API keys** | hash, escopo, expiração, revogação, auditoria | 1 |
| 9 | **Retenção/LGPD** | soft-delete + anonimização; exportação; jobs de limpeza | 3, 4 |
| 10 | **Runbooks** | incidentes, disco, Redis, billing, DMCA, vazamento | 3, 4 |

### Ordem recomendada

```text
1 OpenAPI → 2 Erros/idempotência → 3 Observabilidade → 4 Backup
   → 5 CI/CD → 6 Integração → 7 Upload → 8 API keys
   → 9 Retenção → 10 Runbooks
```

Itens 5 e 6 podem correr em paralelo com 3/4. Itens 7–10 entram antes do primeiro deploy real.

---

## 4. P2 — depois do MVP

| # | Frente | Gatilho |
| :--- | :--- | :--- |
| 1 | Busca/ranking | catálogo > 10k obras ou busca p95 > 500ms |
| 2 | Feed/notificações | retenção de leitor justificar e-mail/push |
| 3 | Moderação madura | fila de denúncias > capacidade manual |
| 4 | Billing maduro | múltiplos provedores, refund/chargeback, impostos |
| 5 | Analytics de leitura | necessidade de produto e base LGPD |
| 6 | i18n/acessibilidade | expansão para novos idiomas/RTL |
| 7 | Performance de escala | partições, PgBouncer, read replicas |
| 8 | Operação avançada | SLOs com alerting, DR, custo |
| 9 | Ingest/scrapers | contrato versionado, retries/DLQ, sandbox |
| 10 | PWA/offline | leitor web maduro |

---

## 5. Fora de escopo (deliberado)

- WebSocket público, GraphQL, microservices, Kafka.
- DRM e ads como core.
- Elasticsearch no MVP.
- Multi-region antes de SLO/DR.

Ver [`DECISIONS.md`](./DECISIONS.md) para o racional e os ADRs.

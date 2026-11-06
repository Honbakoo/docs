# 🛠️ Honbakoo Operations

> **Status:** contrato operacional. Descreve a topologia, os sinais e os runbooks que a engine deve implementar.

---

## 1. Topologia

### `PROFILE=budget` (1 VPS, 512MB–1GB)

```text
Internet → Cloudflare/Caddy → API (Go, CGO=0)
                              ├── PostgreSQL 16 (local)
                              ├── worker in-process (libvips, 1 thread)
                              ├── cache/rate-limit em memória
                              └── storage local (/var/lib/honbakoo/media)
```

- Redis **não** é obrigatório.
- Worker de imagem pode rodar como processo separado ou pool in-process.
- Backup para storage externo é obrigatório mesmo no budget.

### `PROFILE=scale`

```text
Internet → CDN/Cloudflare → Caddy/NGINX → API (N réplicas)
                                           ├── PostgreSQL gerenciado
                                           ├── Redis/KeyDB
                                           ├── Asynq workers
                                           └── R2/B2 (zero egress)
```

- API stateless; nenhuma sessão em memória.
- Workers de imagem e jobs de mídia separados da API.
- Métricas por réplica com agregação no Prometheus.

---

## 2. Configuração mínima

| Variável | Obrigatória | Observação |
| :--- | :--- | :--- |
| `HONBAKOO_PROFILE` | sim | `budget` ou `scale` |
| `DATABASE_URL` | sim | `postgres://...` com `sslmode` correto |
| `JWT_SECRET` / chave | sim | distinto por ambiente |
| `REFRESH_TOKEN_PEPPER` | sim | hash de refresh |
| `STORAGE_DRIVER` | sim | `local` ou `s3` |
| `STORAGE_PATH` | budget | diretório de mídia |
| `S3_*` | scale | endpoint, bucket, credenciais |
| `REDIS_URL` | scale | cache/fila/rate limit |
| `TRUSTED_PROXIES` | sim | CIDRs de Caddy/Cloudflare |
| `PUBLIC_BASE_URL` | sim | URLs absolutas e links de e-mail |
| `WEBHOOK_SECRET_*` | billing | por provedor |
| `MEDIA_MAX_BYTES` | não | default 5MB por imagem |
| `MEDIA_MAX_PIXELS` | não | default 50MP |

- Startup falha rápido se variável obrigatória faltar.
- Segredos nunca aparecem em log; `config.Print()` mascara.

---

## 3. Migrations

- Goose com `embed.FS`; aplicadas no startup da API sob `pg_advisory_lock`.
- **Expand/contract:** adicionar coluna/tabela → backfill → migrar código → remover legado em release posterior.
- Toda migration tem `-- +goose Down` testado.
- Migrations destrutivas exigem backup e janela; nunca `DROP` no mesmo release que remove o uso.
- `sqlc generate` e `sqlc diff` no CI; schema e queries não podem divergir.
- Falha de migration aborta o startup; readiness fica `false`.

---

## 4. Health e sinais

| Endpoint | Uso | Dependências |
| :--- | :--- | :--- |
| `GET /healthz` | liveness | nenhuma |
| `GET /readyz` | readiness | PostgreSQL, Redis (se configurado), storage |
| `GET /metrics` | Prometheus | rede interna/admin |

### Métricas mínimas

- `http_requests_total{route,status,method}`
- `http_request_duration_seconds{route}` (histograma)
- `db_pool_acquired`, `db_pool_idle`, `db_pool_wait_seconds`
- `cache_hits_total`, `cache_misses_total`
- `queue_depth`, `queue_failures_total`, `job_duration_seconds`
- `view_flush_lag_seconds`, `view_flush_failures_total`
- `media_gc_removed_total`, `media_gc_errors_total`
- `webhook_failures_total{provider}`
- `rate_limited_total{route}`

### Logs

- JSON (`slog`), `request_id`, `route`, `status`, `latency_ms`, `user_id` opcional.
- Nunca logar Authorization, cookie, refresh token, API key ou corpo de login.
- Erros 5xx com stack apenas no log interno, nunca na resposta.

---

## 5. SLOs iniciais

| SLO | Alvo | Janela |
| :--- | :--- | :--- |
| Disponibilidade da API | 99,5% | 30 dias |
| Latência p95 de leitura cacheável | < 300ms | 30 dias |
| Latência p95 de manifesto | < 500ms | 30 dias |
| Taxa de erro 5xx | < 0,5% | 30 dias |
| Sucesso de upload `complete` | > 99% | 7 dias |
| Atraso do flush de views | < 10 min | 7 dias |
| Idade do backup | < 26h | contínuo |

- Alertas: queima de error budget, `readyz` falhando, disco > 80%, pool esgotado, fila > 10 min, backup atrasado.

---

## 6. Backup e restore

### Banco

- `pg_dump` diário comprimido + WAL archiving quando disponível.
- Retenção: 7 diários + 4 semanais.
- Backup em storage diferente da VPS.
- **Restore testado mensalmente** em ambiente isolado; registrar tempo e resultado.

### Mídia

- Budget: snapshot/rsync do diretório de mídia.
- Scale: versionamento/lifecycle no bucket; R2/B2 com replicação se necessário.
- O banco é a fonte de verdade dos metadados; mídia sem referência é órfã, não o contrário.

### RPO/RTO alvo

| Cenário | RPO | RTO |
| :--- | :--- | :--- |
| Falha de disco | 24h | 4h |
| Corrupção lógica | 24h | 8h |
| Perda de região | 24h | 24h |

### Restore (runbook)

1. Provisionar PostgreSQL limpo.
2. Restaurar o dump mais recente.
3. Aplicar WAL até o ponto desejado (se disponível).
4. Rodar `goose up` para conferir versão.
5. Validar contagens-chave (`mangas`, `chapters`, `users`).
6. Subir API com tráfego desviado; validar `readyz`.
7. Reativar tráfego gradualmente.

---

## 7. Runbooks

### API 5xx / `readyz` falhando

1. Verificar `readyz` e logs por `request_id`.
2. Checar PostgreSQL (conexões, locks, disco).
3. Checar Redis (se scale) e storage.
4. Se dependência externa: responder `503` com `Retry-After` e backoff.
5. Rollback da última release se o erro coincidir com deploy.

### Disco cheio

1. Identificar maior consumidor (`du` em mídia, logs, WAL).
2. Rodar GC de mídia órfã e expirar uploads pendentes.
3. Rotacionar/comprimir logs.
4. Aumentar disco ou migrar mídia para S3/R2.
5. Nunca apagar WAL sem checkpoint seguro.

### Redis indisponível (scale)

1. Rate limit e cache degradam; API deve continuar lendo do banco.
2. Fila Asynq pausa; uploads ficam `pending`.
3. Restaurar Redis; jobs idempotentes reprocessam.
4. Se persistente, alternar para modo degradado documentado.

### Webhook de billing falhando

1. Consultar `webhook_events` por `status='failed'`.
2. Verificar assinatura e relógio do servidor.
3. Reprocessar evento idempotente; não editar `vip_until` manualmente sem auditoria.
4. Se o provedor reenviar, a unique `(provider, external_id)` evita duplicidade.

### DMCA urgente

1. `POST /admin/dmca/block` com `target_type` e `target_id`.
2. Confirmar `is_dmca_blocked = TRUE` e cache invalidado.
3. Verificar job de blacklist de hashes.
4. Registrar decisão em `audit_log` e responder ao solicitante.

### Vazamento de credencial

1. Revogar API key/refresh families afetadas.
2. Rotacionar segredo JWT/HMAC se necessário.
3. Procurar uso anômalo em logs e `audit_log`.
4. Comunicar conforme política legal.

---

## 8. Deploy e rollback

- Build reprodutível, imagem non-root, tag por commit.
- Deploy canário ou blue/green quando houver N réplicas.
- Migrations compatíveis com versão anterior (expand/contract).
- Rollback = imagem anterior + migration `down` somente se seguro; preferir forward fix.
- Smoke test pós-deploy: `/healthz`, `/readyz`, listagem, detalhe, páginas, login.

---

## 9. Capacidade e custo

| Perfil | RAM | CPU | Storage | Custo alvo |
| :--- | :--- | :--- | :--- | :--- |
| budget | 512MB–1GB | 1 vCPU | 10–50GB | US$ 3–5/mês |
| scale | 2–4GB+ | 2+ vCPU | R2/B2 | por uso, egress zero |

- Medir com k6 antes de aumentar recurso.
- `shared_buffers=128MB`, `work_mem=4MB`, `max_connections=20` no budget.
- PgBouncer só quando conexões forem o gargalo.
- Alerta de custo: storage e egress por provedor.

---

## 10. Referências

- [ADR-0003](./adr/0003-perfil-dual-budget-scale.md) — budget/scale.
- [ADR-0007](./adr/0007-cache-fila-rate-limit.md) — cache/fila/rate limit.
- [ADR-0011](./adr/0011-operacao-observabilidade-backup-ci.md) — observabilidade/backup/CI.
- [ADR-0015](./adr/0015-retencao-lgpd-ciclo-de-vida.md) — retenção e LGPD.

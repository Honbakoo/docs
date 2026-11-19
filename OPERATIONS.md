# 🛠️ Honbakoo Operations

> **Status:** contrato operacional. Descreve a topologia, os sinais e os runbooks que a engine deve implementar.

---

## 1. Topologia

### `PROFILE=budget` (1 VPS, 512MB–1GB)

```text
Internet → Cloudflare/Caddy → API (Go, CGO=0)
                              ├── PostgreSQL 16 (local)
                              ├── worker in-process (libvips, 1 thread)
                              ├── rate-limit em memória (por réplica)
                              └── storage local (/var/lib/honbakoo/media)
```

- Não há Redis: a fila é o `job_queue` durável no PostgreSQL.
- O processamento de mídia é feito no próprio processo da API (inspeção de header/CAS); não existe worker separado.
- Backup para storage externo é obrigatório mesmo no budget.

### `PROFILE=scale`

```text
Internet → CDN/Cloudflare → Caddy/NGINX → API (N réplicas stateless)
                                           ├── PostgreSQL gerenciado (+ job_queue)
                                           └── R2/B2 (zero egress)
```

- API stateless; nenhuma sessão em memória.
- Cada réplica roda o worker da fila (`job_queue`, `FOR UPDATE SKIP LOCKED`); jobs são reclamados por qualquer réplica.
- Métricas por réplica com agregação no Prometheus.

---

## 2. Configuração mínima

| Variável | Obrigatória | Observação |
| :--- | :--- | :--- |
| `HONBAKOO__SERVER__PROFILE` | não | `budget` (padrão) ou `scale`; hoje informativo |
| `HONBAKOO__DATABASE__URL` | sim | `postgres://...` com `sslmode` correto; padrão é rejeitado em produção |
| `HONBAKOO__AUTH__JWT_SECRET` | sim | 32+ bytes, distinto por ambiente |
| `HONBAKOO__STORAGE__BACKEND` | não | `local` (padrão) ou `s3` |
| `HONBAKOO__STORAGE__LOCAL_PATH` | budget | diretório de mídia local |
| `HONBAKOO__STORAGE__S3_ENDPOINT/REGION/BUCKET/ACCESS_KEY/SECRET_KEY/PUBLIC_URL` | scale | credenciais e base pública/CDN do bucket |
| `HONBAKOO__SERVER__TRUSTED_PROXIES` | sim | CIDRs de Caddy/Cloudflare |
| `HONBAKOO__SERVER__PUBLIC_URL` | sim | URLs absolutas e links de e-mail; HTTPS em produção |
| `HONBAKOO__BILLING__WEBHOOK_SECRET` | billing | 32+ bytes; segredo único, não por provedor |
| `HONBAKOO__METRICS__TOKEN` | não | obrigatório para expor `/metrics` fora de dev/test |

O segredo JWT também deriva o HMAC dos leitores anônimos e assina as capabilities de mídia protegida. Rotacioná-lo afeta a deduplicação anônima do dia corrente e invalida links de página gated em aberto (o leitor recarrega o manifesto).

- Startup falha rápido (`config.Validate`) quando uma combinação obrigatória está inválida.
- Limites de mídia são constantes do build (50 MB por upload e 50 MP por imagem), não variáveis de ambiente.
- Segredos nunca aparecem em log; valores sensíveis não são impressos na inicialização.
- A fila é durável no PostgreSQL (`job_queue` com `FOR UPDATE SKIP LOCKED`); o rate limit HTTP é in-process por réplica e falhas de login têm throttle durável em `auth_login_throttles`; não há cache de aplicação nem Redis.
- Views usam `chapter_view_events` + rollup transacional a cada 30 segundos no worker; o refresh das janelas diária/semanal/mensal roda a cada 15 minutos. `--role=api` grava eventos, mas não faz rollup.

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
| `GET /readyz` | readiness | PostgreSQL |
| `GET /metrics` | Prometheus | rede interna/admin |

### Métricas mínimas

- `honbakoo_http_requests_total{method,code,path}`
- `honbakoo_http_request_duration_seconds{method,path}` (histograma)
- `honbakoo_db_pool_connections{state}` (`total`, `idle`, `acquired`)
- `honbakoo_views_pending_events` e `honbakoo_views_oldest_pending_event_age_seconds`
- `honbakoo_views_flushed_events_total`, `honbakoo_views_flush_failures_total`, `honbakoo_views_flush_duration_seconds`
- `honbakoo_media_gc_removed_total`, `honbakoo_media_gc_failures_total`
- `honbakoo_media_variants_generated_total`, `honbakoo_media_variant_skips_total`, `honbakoo_media_variant_failures_total`
- `honbakoo_rate_limited_total{scope}`
- `honbakoo_auth_login_throttle_locked_total`

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

- Dump diário em formato custom (`pg_dump -Fc -Z 9`) via `engine/scripts/backup.sh`.
- Checksum SHA-256 ao lado de cada arquivo; retenção padrão de 7 dias (`--retention-days`).
- Cada backup gera um manifesto `honbakoo-<stamp>.manifest` com formato, ambiente, checksums, backend de storage e contagens de `users`, `mangas`, `chapters` e `media_objects`.
- O dump é validado com `pg_restore --list` antes do manifesto ser escrito; um dump ilegível não é publicado.
- Cópia externa obrigatória em produção: `BACKUP_REMOTE` (rclone) para storage diferente da VPS; `BACKUP_ALLOW_LOCAL_ONLY=1` é a exceção explícita para laboratório.
- O dump não é cifrado no cliente: use bucket privado com criptografia em repouso (R2/S3 SSE), credencial restrita e rotação. Criptografia client-side (`age`/GPG) é roadmap; se o bucket vazar, o dump é legível.
- WAL archiving/PITR quando disponível (RPO de 15–60 min).
- **Restore testado mensalmente** em ambiente isolado com `engine/scripts/restore-drill.sh`; ele chama `restore.sh` (que chama `verify-backup.sh`), compara as contagens com o manifesto e grava o resultado em `backups/restore-drills.log`. Registrar tempo e resultado.

```bash
cd engine
./scripts/backup.sh                 # dump + manifesto + mídia local + retenção
BACKUP_REMOTE=r2:honbakoo-backups ./scripts/backup.sh
./scripts/verify-backup.sh          # checksum, pg_restore --list, manifesto e tar da mídia
./scripts/restore-drill.sh --target-url postgres://... --confirm restore
                                      # restore isolado + contagens do manifesto
./scripts/restore.sh --target-url "$RESTORE_URL" --confirm restore
```

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

1. Provisionar PostgreSQL limpo e **não** apontar para produção.
2. Rodar `restore.sh` com `--target-url` explícito e `--confirm restore` (o script recusa o mesmo `HONBAKOO__DATABASE__URL` sem `--allow-same`).
3. O script verifica o checksum, restaura com `--clean --single-transaction --exit-on-error` e imprime contagens de `users`, `mangas` e `chapters`.
4. Se houver dump de mídia local, passar `--media-archive` e `--media-dir` (o diretório precisa estar vazio).
5. Aplicar WAL até o ponto desejado, se PITR estiver configurado.
6. Rodar `./bin/honbakoo --role=migrate` para conferir a versão do goose.
7. Subir a API com tráfego desviado; validar `GET /readyz`.
8. Reativar tráfego gradualmente e registrar RTO real no runbook mensal.

### Registro de testes de restore

| Data | Origem | Resultado |
| :--- | :--- | :--- |
| 2026-11-12 | Dump local + mídia de teste, restaurado em banco `honbakoo_restore_test` descartável | ✅ Checksums do dump e da mídia validados; `users=484`, `mangas=333`, `chapters=311`; goose na versão 3; mídia extraída corretamente. |

> Esses números são do ambiente local de desenvolvimento. Em produção, compare as contagens com o banco de origem antes de liberar tráfego.

---

## 7. Runbooks

### API 5xx / `readyz` falhando

1. Verificar `readyz` e logs por `request_id`.
2. Checar PostgreSQL (conexões, locks, disco).
3. Checar a fila (`job_queue`) e o storage.
4. Se dependência externa: responder `503` com `Retry-After` e backoff.
5. Rollback da última release se o erro coincidir com deploy.

### Disco cheio

1. Identificar maior consumidor (`du` em mídia, logs, WAL).
2. Rodar GC de mídia órfã e expirar uploads pendentes.
3. Rotacionar/comprimir logs.
4. Aumentar disco ou migrar mídia para S3/R2.
5. Nunca apagar WAL sem checkpoint seguro.

### Fila parada / backlog (`job_queue`)

1. Verificar `SELECT status, count(*) FROM job_queue GROUP BY status;`.
2. Jobs `processing` com `locked_until` expirado são reclamados automaticamente (lock de 5 min + heartbeat).
3. Reenfileirar jobs `failed` após corrigir a causa (ver RUNBOOKS RB-003).
4. Não há Redis/Asynq; não reinicie serviços inexistentes.

### Views atrasadas (`honbakoo_views_pending_events`)

1. Confirmar que `role=worker` (ou `all`) está rodando; `role=api` só grava eventos.
2. Comparar `oldest_pending_event_age_seconds` com o SLO de 10 min.
3. Verificar locks/throughput do PostgreSQL e `honbakoo_views_flush_failures_total`.
4. Reiniciar o worker é seguro: o flush é transacional e idempotente; eventos pendentes permanecem na tabela.
5. Nunca resetar `processed_at` sem reconstruir os agregados (ver RUNBOOKS RB-003).

### Variantes de mídia paradas

1. `SELECT count(*) FROM media_objects WHERE variants = '{}'::jsonb AND status = 'ready';`
2. Confirmar `honbakoo_media_variant_failures_total` e logs de `GenerateMissingVariants`.
3. O backfill roda a cada 2 min, lote de 50; originais acima de 24 MP/20 MB são marcados como `skipped` de propósito.
4. Não bloquear upload por variante: o original continua sendo a fonte de verdade.

### Lock de login excessivo (`honbakoo_auth_login_throttle_locked_total`)

1. Verificar picos de `honbakoo_rate_limited_total{scope="login"}` e tentativas por IP/conta.
2. O lock é por HMAC de IP + e-mail, dura 15 min e não expõe IP bruto.
3. Se o PostgreSQL estiver indisponível, o throttle falha aberto (logs de warning); o limite em memória continua.
4. Para liberar uma conta específica, remover a linha correspondente em `auth_login_throttles` somente após confirmar que não é ataque.

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

- Artefatos em `deploy/`: Compose de produção, Caddyfile, unidades systemd e exemplos de ambiente. Passo a passo em `deploy/README.md`.
- Build reprodutível, imagem non-root, tag semântica publicada por `Release` em tags `v*`.
- Deploy: `scripts/deploy.sh <tag>` puxa a imagem, roda `--role=migrate`, sobe a stack e espera `/healthz`.
- Falha de health no deploy volta para a tag anterior; a migration **não** é revertida.
- Migrations compatíveis com a versão anterior (expand/contract).
- Rollback manual = imagem anterior + `down` somente se seguro; preferir forward fix.
- Backup diário via `honbakoo-backup.timer`; drill mensal via `honbakoo-restore-drill.timer`.
- Smoke test pós-deploy: `/healthz`, `/readyz`, configuração pública e login.
- Staging usa o mesmo Compose com outro `DOMAIN`, `PUBLIC_URL`, CORS e banco.

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

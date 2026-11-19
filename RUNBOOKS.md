# 📖 Honbakoo Runbooks & Troubleshooting

> **Contrato Operacional:** Procedimentos passo a passo para resolução rápida de incidentes e operações de manutenção em instâncias `budget` e `scale`.

---

## 1. Índice de Runbooks

| Código | Incidente / Procedimento | Severidade | RTO Alvo |
| :--- | :--- | :--- | :--- |
| **RB-001** | Esgotamento de Disco na VPS (`budget`) | P1 - Alta | < 15 min |
| **RB-002** | Sobrecarga de Banco (PostgreSQL Spikes & Lock) | P1 - Alta | < 10 min |
| **RB-003** | Fila durável (`job_queue`) parada ou com backlog | P2 - Média | < 5 min |
| **RB-004** | Procedimento de Takedown Imediato DMCA | P1 - Alta | < 5 min |
| **RB-005** | Backup Manual e Teste de Restore (DR) | Rotina | < 30 min |
| **RB-006** | Rotação Emergencial de Chaves e Segredos | P0 - Crítica | < 20 min |

---

## 2. RB-001: Esgotamento de Disco na VPS (`budget`)

### Sintomas:
* Respostas da API começam a retornar `500 Internal Server Error` em uploads.
* Logs do PostgreSQL indicam `PANIC: could not write to file ... No space left on device`.

### Ação Imediata:
1. **Verificar pontos de montagem:**
   ```bash
   df -h
   du -sh /var/lib/honbakoo/media/* | sort -hr | head -n 10
   ```
2. **Executar o Garbage Collector (GC) de mídias órfãs:**
   O Honbakoo possui uma rotina CLI para identificar arquivos no storage sem referência na tabela `chapter_pages`:
   ```bash
   honbakoo-cli media gc --dry-run=false
   ```
3. **Limpar logs antigos do Docker:**
   ```bash
   truncate -s 0 /var/lib/docker/containers/*/*-json.log
   ```
4. **Se o banco estiver em estado de recuperação (WAL lotado):**
   ```bash
   docker compose exec postgres vacuumdb -U honbakoo -d honbakoo_db --full --analyze
   ```

---

## 3. RB-002: Sobrecarga no PostgreSQL (Spikes & Locks)

### Sintomas:
* Latência de endpoints `p95` salta para > 2.000ms.
* Métrica `db_pool_wait_seconds` aumenta de forma contínua.

### Diagnóstico:
1. **Identificar queries lentas ou travadas:**
   ```sql
   SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
   FROM pg_stat_activity
   WHERE (now() - pg_stat_activity.query_start) > interval '5 seconds'
     AND state != 'idle';
   ```
2. **Matar conexões bloqueantes:**
   ```sql
   SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid = <PID_BLOQUEANTE>;
   ```
3. **Verificar backlog da fila durável:**
   ```sql
   SELECT status, count(*) FROM job_queue GROUP BY status ORDER BY status;
   SELECT id, status, attempts, run_at, locked_until, last_error
   FROM job_queue
   WHERE status IN ('pending', 'processing')
   ORDER BY run_at
   LIMIT 20;
   ```
   Jobs `processing` com `locked_until` no passado voltam a ser elegíveis automaticamente no próximo `FetchNextJob`.

---

## 4. RB-003: Fila durável (`job_queue`) parada ou com backlog

### Sintomas:
* E-mails, webhooks, importações ou limpezas deixam de acontecer.
* Crescimento de linhas `pending` em `job_queue` e/ou `attempts` chegando a `max_attempts`.

### Diagnóstico:
```sql
SELECT status, count(*) FROM job_queue GROUP BY status ORDER BY status;
-- Views: backlog deve ficar perto de zero (flush a cada 30 segundos no worker).
SELECT count(*) AS pending_views, min(created_at) AS oldest
FROM chapter_view_events WHERE processed_at IS NULL;
-- NUNCA resetar processed_at para reprocessar: isso duplica views já agregadas.
-- Recuperação de contagem exige reconstruir manga_view_daily e views_all_time.
SELECT id, status, attempts, max_attempts, run_at, locked_until, last_error
FROM job_queue
WHERE status IN ('pending', 'processing')
ORDER BY run_at
LIMIT 50;
```

### Recuperação:
1. **Confirmar que a API está de pé e com o worker ativo:**
   ```bash
   curl -fsS https://<host>/readyz
   ```
   Se a API reiniciou recentemente, jobs `processing` órfãos são reclamados quando `locked_until` expira (lock de 5 min renovado por heartbeat).
2. **Reenfileirar jobs terminais com falha, após corrigir a causa:**
   ```sql
   UPDATE job_queue
   SET status = 'pending', attempts = 0, locked_until = NULL, last_error = NULL, run_at = NOW()
   WHERE status = 'failed' AND id = <JOB_ID>;
   ```
3. **Validar a drenagem:**
   ```sql
   SELECT status, count(*) FROM job_queue GROUP BY status;
   ```
   Não há Redis: a fila é o próprio PostgreSQL (`FOR UPDATE SKIP LOCKED`).
4. **Backlog de views:** `honbakoo_views_pending_events` e `honbakoo_views_oldest_pending_event_age_seconds` devem ficar próximos de zero. O `role=api` não faz rollup; confirme que `role=worker` ou `all` está rodando.
5. **Nunca** resetar `processed_at` para "reprocessar" views: os eventos já foram somados. Uma correção de agregados exige reconstruir `manga_view_daily`, `chapters.views_count` e `mangas.views_all_time` a partir de uma fonte confiável e documentar a janela afetada.

---

## 5. RB-004: Procedimento de Takedown Imediato DMCA

### Ação em Menos de 5 Minutos:
1. **Executar o comando de bloqueio legal via CLI do Honbakoo:**
   ```bash
   honbakoo-cli moderation dmca-block \
     --manga-slug="obra-notificada" \
     --reason="Notificação extrajudicial DMCA protocolo #12345" \
     --add-hashes-to-blacklist=true
   ```
2. **O que acontece instantaneamente no banco:**
   * A obra recebe `is_dmca_blocked = TRUE` e `is_published = FALSE`.
   * Todos os capítulos vinculados recebem `is_dmca_blocked = TRUE`.
   * Os hashes SHA-256 de todas as páginas são inseridos na tabela `blocked_media_hashes`.
3. **Purgar o Cache da CDN:**
   ```bash
   curl -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/purge_cache" \
     -H "Authorization: Bearer $CF_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"prefixes": ["api.honbakoo.org/api/v1/mangas/obra-notificada"]}'
   ```
4. **Resultado:**
   A obra retorna `404 Not Found` imediatamente em toda a internet e qualquer tentativa de re-upload das mesmas páginas é abortada antes de salvar no storage.

---

## 6. RB-005: Backup Manual e Teste de Restore (DR)

### Backup Manual Rápido (Dump Consistente):
```bash
cd engine

# Dump custom comprimido + checksum + mídia local (se backend=local) + retenção
./scripts/backup.sh

# Cópia externa obrigatória em produção (rclone configurado para R2/B2/Wasabi)
BACKUP_REMOTE=r2:honbakoo-backups ./scripts/backup.sh

# Verifica checksum, estrutura do dump, manifesto e arquivo de mídia
./scripts/verify-backup.sh
```

O backup gera um manifesto `honbakoo-<stamp>.manifest` com checksums, ambiente, backend e contagens. Em produção, `backup.sh` recusa rodar sem `BACKUP_REMOTE`, salvo `BACKUP_ALLOW_LOCAL_ONLY=1`. Um dump que falha em `pg_restore --list` não é publicado.

### Teste de Restauração em Ambiente Isolado:
```bash
cd engine

# Nunca use a URL de produção. O script exige confirmação explícita.
./scripts/restore.sh \
  --target-url "postgres://honbakoo_user:senha@localhost:5432/honbakoo_restore?sslmode=disable" \
  --confirm restore
```

O `restore.sh` chama `verify-backup.sh` (checksum, `pg_restore --list`, manifesto e mídia), restaura em transação única, imprime contagens de `users`/`mangas`/`chapters`/`media_objects` e, opcionalmente, restaura a mídia com `--media-archive` + `--media-dir`. Para o drill mensal use `restore-drill.sh --target-url ... --confirm restore`: ele compara as contagens restauradas com o manifesto e grava o resultado em `backups/restore-drills.log`. Depois valide `GET /readyz` e registre o tempo total.

---

## 7. RB-006: Rotação Emergencial de Chaves e Segredos

### Se o `HONBAKOO__AUTH__JWT_SECRET` for comprometido:
1. Gerar novo segredo criptográfico:
   ```bash
   openssl rand -base64 32
   ```
2. Atualizar o arquivo `.env` com a nova chave em `HONBAKOO__AUTH__JWT_SECRET`.
3. Reiniciar a API (`docker compose restart api`).
4. **Impacto:** Todos os usuários serão deslogados e precisarão fazer login novamente, invalidando 100% dos tokens vazados.

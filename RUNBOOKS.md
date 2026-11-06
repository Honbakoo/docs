# 📖 Honbakoo Runbooks & Troubleshooting

> **Contrato Operacional:** Procedimentos passo a passo para resolução rápida de incidentes e operações de manutenção em instâncias `budget` e `scale`.

---

## 1. Índice de Runbooks

| Código | Incidente / Procedimento | Severidade | RTO Alvo |
| :--- | :--- | :--- | :--- |
| **RB-001** | Esgotamento de Disco na VPS (`budget`) | P1 - Alta | < 15 min |
| **RB-002** | Sobrecarga de Banco (PostgreSQL Spikes & Lock) | P1 - Alta | < 10 min |
| **RB-003** | Falha de Conexão com Redis no modo `scale` | P2 - Média | < 5 min |
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
3. **Verificar se o buffer do Redis travou o batch flush:**
   Se o worker de agregação de views estiver disparando writes concorrentes em massa, force o intervalo do job para 15 minutos via variável:
   ```env
   VIEW_FLUSH_INTERVAL=15m
   ```

---

## 4. RB-003: Falha do Redis no modo `scale`

### Sintomas:
* `/readyz` retorna `503 Service Unavailable` com erro em `redis`.
* Rate limiter começa a rejeitar requisições ou liberar sem contagem.

### Recuperação:
1. **No modo `scale`, se o Redis cair:**
   A API Honbakoo possui fallback automático para cache em memória local (`in-memory LRU`) se a variável `REDIS_FALLBACK_LOCAL=true` estiver ativa.
2. **Reiniciar o container do Redis:**
   ```bash
   docker compose restart redis
   ```
3. **Validar latência e memória do Redis:**
   ```bash
   redis-cli -u $REDIS_URL ping
   redis-cli -u $REDIS_URL info memory
   ```

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
# Executa dump comprimido em gzip
docker compose exec -T postgres pg_dump -U honbakoo -d honbakoo_db -Fc | gzip > backup_$(date +%Y%m%d_%H%M%S).dump.gz

# Se configurado S3/B2 externo, envia automaticamente:
rclone copy backup_*.dump.gz remote_backup:honbakoo-dumps/
```

### Teste de Restauração em Ambiente Isolado:
```bash
# Descompactar e restaurar em banco de homologação/teste
gunzip -c backup_*.dump.gz | docker compose exec -T postgres pg_restore -U honbakoo -d honbakoo_test --clean --no-owner
```

---

## 7. RB-006: Rotação Emergencial de Chaves e Segredos

### Se o `JWT_SECRET` for comprometido:
1. Gerar novo segredo criptográfico:
   ```bash
   openssl rand -base64 32
   ```
2. Atualizar o arquivo `.env` com a nova chave em `JWT_SECRET`.
3. Reiniciar a API (`docker compose restart api`).
4. **Impacto:** Todos os usuários serão deslogados e precisarão fazer login novamente, invalidando 100% dos tokens vazados.

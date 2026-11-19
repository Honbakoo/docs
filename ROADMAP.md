# 🗺️ Honbakoo Roadmap

> **Status:** P0 e P1 implementados no engine (com as ressalvas indicadas). Escopo do MVP confirmado em 2026-11-12: mangá + NSFW + vídeo, ingestão manual e automática, deploy em VPS com Cloudflare R2 e OpenAPI validado com Redocly. P2 só entra com gatilho.

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
- Fila durável no PostgreSQL (`job_queue`, `FOR UPDATE SKIP LOCKED`); binário único com API + worker in-process.
- API keys, retenção/LGPD e documentação operacional (este ciclo).
- Contagem de views por evento durável + rollup em lote, com deduplicação por leitor/capítulo/dia.

---

## 3. P1 — antes do MVP

| # | Entrega | Estado | Evidência / pendência |
| :--- | :--- | :--- | :--- |
| 1 | **OpenAPI 3.1 executável** | ✅ Feito | `engine/api/openapi.yaml` cobre todas as rotas; `TestOpenAPIMatchesRouter` compara com `chi.Walk`. Redocly roda no CI com `operation-4xx-response: error`; as 19 operações sem resposta 4xx foram corrigidas. |
| 2 | **Erros + idempotência** | ✅ Feito | Erros `{error}` estáveis; `Idempotency-Key` no middleware; replay coberto. |
| 3 | **Observabilidade** | ✅ Feito | `/healthz`, `/readyz`, `/metrics` (GET, token opcional), logs JSON, request id. Métricas de backlog/flush de views, GC, variantes, rate limit e lock de login. |
| 4 | **Backup/restore** | 🟡 Parcial | `backup.sh` gera dump validado + manifesto com checksums/contagens; `verify-backup.sh`, `restore.sh` e `restore-drill.sh` checam antes de restaurar e comparam contagens. Em produção exige `BACKUP_REMOTE`. Falta agendar o dump e registrar o restore mensal no calendário operacional. |
| 5 | **CI/CD + supply chain** | ✅ Feito | GitHub Actions: gofmt, vet, build, sqlc diff, migrations up/down/up, `go test -race`, govulncheck, SBOM e Trivy. |
| 6 | **Testes de integração** | 🟡 Parcial | CI usa service PostgreSQL 16 + MinIO real + migrations reais; suíte local faz `t.Skip` sem banco. Testcontainers, Redis e E2E de navegador ainda não adotados. Piso de cobertura total: 35%. |
| 7 | **Segurança de upload** | ✅ Feito | Magic bytes, limite de pixels, SHA-256/CAS, blacklist de hash, variantes best-effort e manifesto com CDN ou endpoint protegido para mídia gated. |
| 8 | **API keys** | ✅ Feito | Hash, escopo, expiração, revogação e auditoria. API keys não acessam rotas `/auth/*` de gerenciamento de conta; escopo `admin` é exigido para rotas administrativas e escopo de grupo limita o editorial. |
| 9 | **Retenção/LGPD** | ✅ Feito | Soft-delete + anonimização, exportação e jobs de limpeza. |
| 10 | **Runbooks** | ✅ Feito | Incidentes, disco, billing, DMCA, vazamento e restore documentados. |

### Núcleo de produto entregue junto do P1

- Busca full-text, filtros (`format`, `status`, `tag`), updates e tags.
- Histórico, favoritos, rating e biblioteca.
- Admin real montado em `/api/v1/admin` (usuários, denúncias, DMCA, ban/unban).
- Editorial: `tag_ids`, reordenação transacional de páginas e import de URLs via cliente anti-SSRF.
- S3/R2/MinIO em produção e SMTP real para reset/verificação de e-mail.

### Pendências conscientes

- Verificação de idade em modo `strict` sem provedor integrado (`ErrAgeProviderUnavailable`); é bloqueador do NSFW no MVP.
- Frontend mínimo (o contrato está pronto; falta consumidor).
- Ingestão automática por fonte (o import editorial por URL e o anti-SSRF existem; faltam conectores, agendamento, retry/DLQ e provenance).
- Fluxo editorial de vídeo (schema suporta episódios; faltam upload, transcodificação/playback, autorização e progresso).
- Camada 3 (`system_settings` hot-reload) sem serviço/endpoint.
- Rate limit de login durável por HMAC(IP + e-mail); limite global distribuído ainda exige edge/WAF/Redis.
- Agendar backup diário e registrar o drill de restore mensal (o script de verificação já existe).
- Testcontainers e E2E noturno.

---

## 4. Escopo do MVP — confirmado

> Decisões registradas em 2026-11-12. Elas substituem o escopo anterior de “MVP só mangá”.

- [x] **Decisão:** NSFW entra no MVP. Exige verificação de idade em modo `strict`, moderação e páginas legais.
- [x] **Decisão:** vídeo entra no MVP. O schema suporta episódios; faltam fluxo editorial, upload, playback e progresso.
- [x] **Decisão:** ingestão manual e automática entram no MVP. O import editorial por URL continua; conectores automáticos entram no MVP.
- [x] **Decisão:** deploy em VPS com Cloudflare para DNS/CDN/WAF e Cloudflare R2 para mídia.
- [x] **Decisão:** OpenAPI validado com Redocly no CI.
- [x] **Decisão:** frontend começa ao fim da Fase 1, com contrato + ambiente local; não espera a infraestrutura de produção.

**Consequência:** verificação de idade, vídeo e ingestão deixam de ser P2/condicionais e passam a ser requisitos de MVP.

---

## 5. Plano de execução — ordem e checklists

> Regra: contrato primeiro, infraestrutura depois. O frontend não depende de WAF, PITR ou PgBouncer.
> Itens `[x]` já existem; itens `[ ]` são trabalho novo.

### Trilha A — desbloquear o frontend

#### Fase 0 — Decisões e escopo

- [x] NSFW entra no MVP.
- [x] Vídeo entra no MVP.
- [x] Ingestão manual e automática entram no MVP.
- [x] Deploy em VPS + Cloudflare + Cloudflare R2.
- [x] OpenAPI validado com Redocly.
- [x] Registrar a decisão de escopo em ADR/DECISIONS, incluindo o impacto de NSFW e vídeo no orçamento e na operação. (ADR-0017)

#### Fase 1 — Contrato executável + ambiente local

- [x] Contrato OpenAPI cobre as rotas existentes; `TestOpenAPIMatchesRouter` compara com `chi.Walk`.
- [x] Configurar `redocly.yaml` com regras para OpenAPI 3.1.
- [x] Rodar `redocly lint` no CI e falhar em erro.
- [x] Corrigir todas as violações do Redocly (schemas `nullable` migrados para `type: [T, "null"]`).
- [x] Definir geração do cliente TypeScript a partir do OpenAPI e versioná-lo no repositório do frontend (`api/client/schema.d.ts`).
- [x] CI falha quando o contrato mudar sem regenerar o cliente.
- [x] Documentar política de versionamento: `/api/v1` é aditivo; breaking change exige `/v2`.
- [x] Definir contrato de verificação de idade: estados `unverified`, `pending`, `verified`, `rejected`, `expired`, endpoints e erros.
- [x] Definir contrato de vídeo: episódio, fontes, playback, progresso e autorização VIP/NSFW.
- [x] Tornar CORS configurável por env (`HONBAKOO__SERVER__CORS_ORIGINS`), incluindo dev, staging e produção.
- [x] Expor `X-Request-ID` no CORS e no envelope de erro; documentar para suporte.
- [x] Ampliar o seed para personas determinísticas: free, VIP, idade verificada, banido e admin.
- [x] Seed de catálogo com todos os estados: draft, published, NSFW, VIP, early access, sem capítulo e capítulo vazio.
- [x] Seed de vídeo com episódio e fonte de playback (progresso inicial coberto pelo contrato).
- [x] Docker Compose de desenvolvimento com PostgreSQL + MinIO + API + seed em um comando.
- [x] Documentar `make dev` e `.env.example` sem segredos.
- [x] Smoke test de curl para auth, catálogo, leitor, mídia pública, mídia protegida e vídeo (`scripts/smoke.sh`).
- [x] Documentar o token de mídia: validade de 10 min e renovação ao refazer o manifesto.

**Marco F — frontend liberado:** contrato Redocly limpo, cliente gerado, CORS configurável, seed com personas e ambiente local de um comando. O frontend pode começar aqui, mesmo com as fases seguintes em andamento.

#### Fase 2 — Staging base

- [x] Versionar artefatos de deploy: `deploy/docker-compose.prod.yml`, `deploy/Caddyfile`, unidades systemd, `deploy/*.env.example`, `scripts/deploy.sh` e workflow `Release`.
- [ ] Provisionar VPS e usuário de deploy sem privilégios.
- [ ] Configurar DNS, TLS e proxy reverso (Caddy ou Cloudflare Tunnel).
- [ ] Configurar Cloudflare CDN/WAF e regras de cache para mídia imutável.
- [ ] Criar bucket R2, lifecycle, versionamento e credenciais restritas.
- [ ] Configurar secrets fora do repositório.
- [x] Rodar migrações automaticamente no deploy (`scripts/deploy.sh` executa `--role=migrate` antes de subir a nova imagem).
- [ ] Publicar imagem no CI e deployar staging a cada merge na branch principal.
- [ ] Configurar CORS de staging e `PUBLIC_URL`.
- [ ] Configurar SMTP sandbox.
- [ ] Criar script de seed/reset de staging.
- [ ] Smoke test pós-deploy.

**Marco S — staging disponível:** URL HTTPS estável para o frontend integrar. Ainda não é produção.

#### Fase 3 — E2E dos fluxos de tela

- [x] Teste de integração real do storage S3/MinIO no CI (grava, lê, verifica e apaga).
- [ ] Criar suíte E2E de API rodando no CI com PostgreSQL real e MinIO.
- [ ] Cobrir cadastro, login, refresh, logout, reset de senha e verificação de e-mail.
- [ ] Cobrir catálogo, busca, filtros, cursor e estados vazios.
- [ ] Cobrir leitor, progresso, histórico, favoritos, rating e biblioteca.
- [ ] Cobrir comentários, denúncias, DMCA e admin (usuários/ban).
- [ ] Cobrir mídia pública via CDN.
- [ ] Cobrir mídia protegida: token válido, expirado, renovado, `storage_key` ausente e 403.
- [ ] Criar contract tests de status, erro, cursor e idempotência.
- [ ] Publicar matriz de erros por endpoint para o frontend.
- [ ] Seed idempotente e reset entre testes.
- [ ] Corrigir lacunas encontradas; nenhuma tela sem contrato.

**Marco F2 — frontend contra API real:** E2E core verde e matriz de erros publicada.

### Trilha B — fechar o MVP

#### Fase 4 — NSFW + verificação de idade

- [ ] Escolher provedor de verificação de idade e definir custo/UX.
- [ ] Implementar `VerifyAge` no modo `strict` (hoje retorna `ErrAgeProviderUnavailable`).
- [ ] Persistir status e auditoria da verificação sem armazenar documento bruto.
- [ ] Aplicar o gate NSFW em catálogo, leitor, mídia, comentários e busca.
- [x] Revalidar status de banimento, idade e VIP em cada request de mídia protegida; token curto de 10 min.
- [ ] Cobrir NSFW no E2E: bloqueio sem idade, liberação com idade e 403 em mídia.
- [ ] Aplicar rate limit específico no fluxo de verificação.
- [ ] Definir textos e fluxo de consentimento/idade com jurídico.

#### Fase 5 — Vídeo

- [ ] Decidir pipeline: HLS pré-transcodificado no R2 ou provedor externo (Cloudflare Stream/Bunny).
- [ ] Definir proteção do playback: público, token curto ou proxy da API.
- [ ] Implementar upload/import de vídeo no editorial.
- [ ] Implementar transcodificação/empacotamento ou integração com provedor.
- [ ] Persistir metadados: duração, codecs, faixas, legendas e poster.
- [ ] Aplicar autorização VIP/NSFW no manifesto e nos segmentos.
- [ ] Implementar progresso de vídeo por usuário.
- [ ] Cobrir vídeo no E2E: manifesto, playback, progresso e bloqueio.
- [ ] Definir limites de tamanho, duração e quota de storage/egress.
- [x] Documentar contrato de vídeo para o frontend.

#### Fase 6 — Ingestão manual e automática

- [ ] Definir interface de conector por fonte (busca, metadados, capítulos e páginas).
- [ ] Implementar a primeira fonte automática.
- [ ] Agendar ingestão no worker com idempotência.
- [ ] Implementar retry com backoff, DLQ e visibilidade de falhas.
- [ ] Implementar deduplicação e provenance (fonte, URL, data, hash).
- [ ] Manter anti-SSRF, limites de taxa, robots/termos e revisão legal por fonte.
- [ ] Expor falhas e reprocessamento no admin.
- [x] Endurecer o import manual por URL: 1–50 URLs, 512 MiB agregados, cap por página e anti-SSRF.
- [ ] Cobrir ingestão no E2E com fonte simulada.

### Trilha C — estabilizar produção

#### Fase 7 — Operação e administração

- [ ] Agendar backup diário.
- [x] Exigir cópia remota e verificação de checksum no backup de produção.
- [ ] Rodar `restore-drill` mensal e registrar no calendário operacional.
- [ ] Configurar WAL archiving/PITR se o RPO exigido for menor que 24h.
- [ ] Configurar Prometheus, Grafana e alertas: 5xx, p95, pool, backlog de views, disco, idade do backup e variantes.
- [ ] Agregar logs e configurar uptime check.
- [ ] Aplicar WAF/rate limit de borda na Cloudflare.
- [x] Fechar API keys fora de `/auth/*`, exigir escopo `admin` e limitar grupo no editorial.
- [x] Limitar download CBZ (1.000 páginas/512 MiB) e importação (50 URLs/512 MiB).
- [x] Índice de expressão para o feed e flush de views set-based.
- [x] Piso de cobertura de 35% e MinIO real no CI.
- [ ] Configurar SPF, DKIM e DMARC.
- [ ] Migrar secrets para cofre ou secrets manager.
- [ ] Implementar `system_settings` com hot-reload.
- [ ] Atualizar runbooks com os novos fluxos de NSFW, vídeo e ingestão.

#### Fase 8 — Carga, segurança e hardening

- [ ] Teste de carga no DAU esperado, com pico.
- [ ] Tuning do PostgreSQL: conexões, memória e autovacuum.
- [ ] Analisar slow queries e índices.
- [ ] Decidir PgBouncer apenas se houver múltiplas réplicas.
- [ ] Testar falha de banco, storage e provedor de idade.
- [ ] Revisão de segurança: upload, vídeo, mídia protegida, tokens, headers e rate limit.
- [ ] Revisar resultados de `govulncheck`, SBOM e Trivy.
- [ ] Definir SLO e capacidade documentada.
- [ ] Avaliar AVIF/WebP, strip de EXIF no original e blurhash.

**Marco P — produção estável:** backup/restore drill, alertas, carga e segurança aprovados.

#### Fase 9 — Beta fechado

- [ ] Subir conteúdo real e validar moderação.
- [ ] Configurar fila de moderação, DMCA e suporte.
- [ ] Publicar termos, privacidade e política de idade.
- [ ] Congelar o contrato: apenas mudanças aditivas durante o beta.
- [ ] Integrar o frontend em staging e corrigir lacunas.
- [ ] Executar checklist de lançamento.

---

## 6. P2 — depois do MVP

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
| 9 | Ingestão em escala | múltiplas fontes, reconciliação e sandbox por fonte |
| 10 | PWA/offline | leitor web maduro |

---

## 7. Fora de escopo (deliberado)

- WebSocket público, GraphQL, microservices, Kafka.
- DRM e ads como core.
- Elasticsearch no MVP.
- Multi-region antes de SLO/DR.

Ver [`DECISIONS.md`](./DECISIONS.md) para o racional e os ADRs.

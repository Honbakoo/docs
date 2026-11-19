# 🧪 Honbakoo Testing Strategy

> **Status:** contrato de qualidade. Define o que precisa passar antes de qualquer release.
> **Fonte de verdade da automação:** [`engine/.github/workflows/ci.yml`](https://github.com/Honbakoo/engine/blob/main/.github/workflows/ci.yml).

---

## 1. Pirâmide

| Camada | Ferramenta | Escopo | Quando |
| :--- | :--- | :--- | :--- |
| Unit | `go test` | regras puras, config, auth, CBZ, SMTP, validação de cursor/permutação | cada commit |
| Integração | `go test` + PostgreSQL real | queries, migrations, transações, CAS/storage | cada PR na CI |
| Contrato | `TestOpenAPIMatchesRouter` | rotas reais × `api/openapi.yaml` | cada PR |
| E2E | API real + banco | fluxos de leitor, upload, moderação | nightly/release (pendente) |
| Carga | k6 | leitura, pico, upload | release (pendente) |
| Segurança | `govulncheck`, Trivy, SBOM | dependências, imagem, supply chain | cada PR/release |

---

## 2. Unit tests

Não usam banco nem rede:

- `internal/config`: defaults, overrides, rejeição de `vip_only` sem billing, SMTP inválido, S3 incompleto, segredos fracos em produção.
- `internal/auth`: JWT, refresh opaco, Argon2, API keys, middlewares, rate limit e chave HMAC do throttle de login.
- `internal/content`: validação de download, materialização de CBZ (inclui falha de página ausente), contagem de views (deduplicação por leitor, flush idempotente e reset de janelas expiradas) e contrato de mídia (CDN para público; endpoint protegido sem vazar `storage_key`/variantes), expiração de capability e revalidação de banimento/idade/VIP a cada request, além do limite de 1.000 páginas no CBZ.
- `internal/media`: geração de variantes (thumb 320, preview limitado), limites de pixels e rejeição de originais grandes.
- `internal/editorial`: rejeição de permutações inválidas (`0`, duplicados, fora de 1..n) e teto de 50 URLs/512 MiB no import remoto.
- `internal/community`: cursor inválido.
- `internal/mailer`: validação de endereço/porta/from, envio SMTP real contra servidor TCP de teste e rejeição de injeção CRLF.
- `internal/storage`: traversal, hotlink, CAS e deduplicação.
- `internal/ingestion`: bloqueio de SSRF.
- `internal/server`: health/readiness, modo read-only, contrato OpenAPI.

Regras:

- `-race` e `-coverprofile` obrigatórios no CI, com piso de 35% de cobertura total.
- Cobrir caminhos de erro e borda, não só o happy path.
- Nada de relógio/rede reais sem injeção; SMTP usa `net.Listen` em `127.0.0.1:0`.

---

## 3. Integração

- **PostgreSQL 16 real.** No CI, service container `postgres:16-alpine` com `honbakoo_test`.
- Localmente, suba o compose e rode as migrations:

```bash
cd engine
podman-compose up -d postgres
HONBAKOO__ENV=development ./bin/honbakoo --role=migrate
go test -race -count=1 ./...
```

- Sem banco acessível, os testes de integração fazem `t.Skip` com a causa — isso mantém `go test ./...` utilizável em máquina limpa, mas **não substitui** a CI.
- Cada suíte cria seus próprios registros com UUID/sufixo aleatório e limpa o que insere quando necessário.
- Não há dependência de ordem entre testes.

Cobertura de integração atual:

- Fluxo de conteúdo: mangá → capítulo → páginas → reader → download CBZ.
- Modos de catálogo `hybrid`/`sfw_only`/`nsfw_only`.
- `ltree` de comentários, denúncias e resolução.
- Editorial: criação, upload CAS, reordenação transacional (swap real de páginas) e import de URLs via HTTP local.
- Admin: paginação keyset de usuários sem duplicados e com cursor final vazio.
- Auth: registro/login/refresh, API keys, exportação e deleção LGPD, throttle durável (3 falhas → lock → expiração).
- Billing: assinatura de webhook e replay idempotente.
- Backup: `backup.sh` valida dump/manifesto e `verify-backup.sh` confere checksum e estrutura; `restore-drill.sh` restaura em banco descartável, compara contagens com o manifesto e registra o drill em `backups/restore-drills.log`.

**Cobertura no CI:** Postgres real como service e MinIO real iniciado em container; `TestS3StorageLifecycle` grava, lê, verifica existência e apaga um objeto. Ainda não adotado: Testcontainers, Redis e E2E noturno de navegador. O CI impõe piso de 35% de cobertura total; o número é um piso contra regressão, não uma meta.

---

## 4. Contrato

- `engine/api/openapi.yaml` (OpenAPI 3.1) é a fonte de verdade; cópia publicada em `docs/api/openapi.yaml`.
- `TestOpenAPIMatchesRouter` constrói o router com handlers reais e compara `chi.Walk` com o YAML:
  - normaliza `{param}` → `{}`;
  - remove barra final;
  - considera GET/POST/PUT/PATCH/DELETE.
- Qualquer rota nova sem documentação (ou documentada sem implementação) **quebra o teste**.
- Erros reais são `{"error":"codigo"}`; o documento reflete isso (não há envelope `{success,data}`).
- Breaking change exige `/v2` e plano de depreciação.

---

## 5. E2E (planejado)

Fluxos mínimos para quando o E2E entrar:

1. Registrar → verificar e-mail → login → refresh → logout.
2. Listar catálogo → detalhe → capítulos → páginas → histórico.
3. Favoritar/desfavoritar → biblioteca.
4. Comentar → responder → reagir → denunciar.
5. Criar obra/capítulo → upload → reordenar → importar → ler.
6. API key → importação → auditoria.
7. Moderador resolve denúncia → soft-delete.
8. DMCA block/unblock → capítulos somem do catálogo.
9. Webhook de billing repetido → sem duplicidade.

E2E deve rodar contra a imagem final, não contra mocks.

---

## 6. Carga (k6, planejado)

| Script | Objetivo | Critério |
| :--- | :--- | :--- |
| `smoke-test.js` | sanidade | 0 erros, p95 < 300ms |
| `reader-load-test.js` | 500–2.000 leitores | p95 < 500ms, 5xx < 0,5% |
| `spike-test.js` | 0→3.000 em 10s | sem colapso, recuperação < 2 min |

Rodar em `budget` e `scale`, medindo pool, CPU, RAM e fila.

---

## 7. Segurança

- `govulncheck ./...` e Trivy (CRITICAL/HIGH) no CI.
- Testes de autorização: usuário A não acessa recurso de B; guest não muta.
- Upload: MIME falso, magic bytes inválidos, imagem truncada, decompression bomb, SVG, hash divergente.
- Webhook: assinatura inválida, replay, payload gigante.
- Rate limit: janela, reset e `Retry-After`.
- OpenAPI: todas as rotas administrativas exigem Bearer.
- ZAP baseline no staging (pendente).

---

## 8. CI gates

O job `test` roda, nesta ordem:

```bash
gofmt -l .                              # precisa sair vazio
go vet ./...
go build ./...
sqlc generate && git diff --exit-code internal/database
./bin/honbakoo --role=migrate           # up
./bin/honbakoo --role=migrate-down      # down
./bin/honbakoo --role=migrate           # up de novo
go test -race -count=1 ./...
govulncheck ./...
```

Jobs adicionais:

- **SBOM** com `anchore/sbom-action`.
- **container-scan** com build da imagem + Trivy `CRITICAL,HIGH` (`ignore-unfixed`).

Ainda pendentes como gate: lint externo do OpenAPI (Spectral/Redocly), gitleaks e k6. Enquanto não entram, a revisão manual cobre esses pontos.

---

## 9. Dados de teste

- UUIDs e sufixos aleatórios; sem dados reais de usuários.
- Imagens pequenas e sintéticas; sem conteúdo protegido.
- Limpar storage temporário (`t.TempDir()`) e registros criados.
- Nunca usar o banco de produção nem `HONBAKOO__ENV=production` nos testes.

### Stack local e smoke

`docker compose up --build` (ou `make dev`) sobe PostgreSQL + MinIO + engine com seed idempotente. O seed demo só roda em `development`/`test` e cria:

- personas free, verificada, VIP e banida;
- catálogo SFW, NSFW, VIP exclusivo, early access, vazio, draft e vídeo HLS;
- imagens demo no storage e manifesto com CDN ou endpoint protegido.

`make smoke` (ou `BASE_URL=http://localhost:8080 ./scripts/smoke.sh`) valida health, config, login, catálogo, leitor, mídia CDN, mídia protegida, gate NSFW, gate VIP e fontes de vídeo. Requer `curl` e `jq`.

---

## 10. Definition of Done

- [ ] `gofmt`, `go vet`, `go build` limpos.
- [ ] `go test -race -count=1 ./...` verde (com Postgres para integração).
- [ ] `sqlc generate` sem diff.
- [ ] Migrations `up → down → up`.
- [ ] OpenAPI atualizado e `TestOpenAPIMatchesRouter` verde.
- [ ] `redocly lint` verde.
- [ ] `make smoke` verde na stack local.
- [ ] Nenhum segredo no diff.
- [ ] Se a mudança for operacional, runbook/`CONFIGURATION.md` atualizados.

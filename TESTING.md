# 🧪 Honbakoo Testing Strategy

> **Status:** contrato de qualidade. Define o que precisa passar antes de qualquer release.

---

## 1. Pirâmide

| Camada | Ferramenta | Escopo | Quando |
| :--- | :--- | :--- | :--- |
| Unit | `go test` | regras puras, auth, cursor, validação | cada commit |
| Integração | Testcontainers (Postgres/Redis/MinIO) | queries, migrations, transações, storage | cada PR |
| Contrato | OpenAPI + `oapi-codegen`/Schemathesis | request/response, erros, auth | cada PR |
| E2E | API real + banco | fluxos de leitor, upload, moderação | nightly/release |
| Carga | k6 | leitura, pico, upload | release |
| Segurança | `govulncheck`, Trivy, ZAP | dependências, imagem, API | cada PR/release |

---

## 2. Unit tests

- Sem banco/rede; tabelas de casos para cursor keyset, validação de payload, cálculo de entitlement VIP, sanitização de `ltree`, rate limit.
- Cobertura não é meta isolada; cobrir caminhos de erro e borda.
- `-race` obrigatório no CI.
- Golden files para JSON de erro e manifesto de páginas.

---

## 3. Integração

- **Postgres real** via Testcontainers; nunca SQLite como substituto.
- Rodar todas as migrations `up` e `down` em banco limpo.
- Testar:
  - `UNIQUE NULLS NOT DISTINCT` de capítulos.
  - `ltree` com UUID sanitizado e profundidade máxima.
  - Triggers de rating/favoritos/reações.
  - Keyset com empates e escrita concorrente.
  - `manga_view_daily` e flush idempotente.
  - `api_keys` expirada/revogada/escopo.
  - Idempotência: replay e conflito de payload.
- **Redis** para cache/rate limit/fila no perfil scale.
- **MinIO** para storage S3; filesystem temporário para budget.
- Cada teste cria e destrói seu schema/tenant; sem dependência de ordem.

---

## 4. Contrato

- `api/openapi.yaml` é a fonte de verdade; lint com Spectral/Redocly.
- CI compara o spec com a implementação (Schemathesis ou testes gerados).
- Breaking change exige nova versão (`/v2`) e plano de depreciação.
- Validar:
  - Envelope `{success,data,meta}` e erros `{success,error}`.
  - `Cache-Control` por rota.
  - Headers de rate limit.
  - Códigos de erro documentados.
- Clientes tipados gerados a partir do spec; não editar à mão.

---

## 5. E2E

Fluxos mínimos:

1. Registrar → verificar e-mail → login → refresh → logout.
2. Listar catálogo → detalhe → capítulos → páginas → histórico.
3. Favoritar/desfavoritar → biblioteca.
4. Comentar → responder → reagir → denunciar.
5. Criar upload → complete → publicar capítulo → ler.
6. Ingestão com API key → auditoria.
7. Moderador resolve denúncia → soft-delete.
8. DMCA block/unblock → hash blacklist.
9. Webhook de billing repetido → sem duplicidade.

E2E roda contra a imagem final, não contra mocks.

---

## 6. Carga (k6)

| Script | Objetivo | Critério |
| :--- | :--- | :--- |
| `smoke-test.js` | sanidade | 0 erros, p95 < 300ms |
| `reader-load-test.js` | 500–2.000 leitores | p95 < 500ms, 5xx < 0,5% |
| `spike-test.js` | 0→3.000 em 10s | sem colapso, recuperação < 2 min |

- Rodar no perfil budget e scale.
- Medir cache hit, pool, CPU, RAM e fila.
- Thresholds do k6 são SLOs executáveis; falha bloqueia release.

---

## 7. Segurança

- `govulncheck ./...` e Trivy na imagem.
- Testes de autorização: usuário A não acessa recurso de B; guest não muta.
- Testes de upload: MIME falso, magic bytes inválidos, imagem truncada, decompression bomb, SVG, hash divergente.
- Testes de webhook: assinatura inválida, replay, payload gigante.
- Rate limit: janela, reset e `Retry-After`.
- ZAP baseline no ambiente de staging.

---

## 8. CI gates

Toda PR deve passar:

```bash
gofmt -l .            # vazio
go vet ./...
go test ./... -race
sqlc diff             # sem diff
goose up/down         # banco limpo
spectral lint api/openapi.yaml
govulncheck ./...
trivy image <tag>
```

- Cobertura de integração não pode cair.
- Migration sem `down` falha.
- OpenAPI sem exemplos de erro falha.
- Nenhum segredo no diff (gitleaks).

---

## 9. Dados de teste

- Seeds determinísticos com UUIDv7 fixos e datas controladas.
- Nunca usar dados reais de usuários.
- Imagens pequenas e sintéticas; sem conteúdo protegido.
- Limpar storage e banco entre suítes.

---

## 10. Definition of Done

- [ ] Testes unitários e de integração verdes.
- [ ] Contrato OpenAPI atualizado e validado.
- [ ] Fluxo E2E do módulo coberto.
- [ ] Carga sem regressão de p95/erro.
- [ ] Sem CVE crítica.
- [ ] Migration `up`/`down` testada.
- [ ] Documentação e ADR atualizados.

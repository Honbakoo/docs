# 🔌 Honbakoo REST API Specification (Headless Contract)

> **Fonte de verdade:** [`api/openapi.yaml`](./api/openapi.yaml) (OpenAPI 3.1).
> O teste `internal/server/openapi_test.go` compara o documento com as rotas reais do `chi.Router`; qualquer divergência quebra a CI.
> Base URL: `https://<host>/api/v1`. Respostas são JSON exceto downloads e `/metrics`.

---

## 1. Princípios

- **Headless:** a API é o produto; frontend web/app são consumidores.
- **Versionada na URL:** `/api/v1`.
- **Autenticação:** `Authorization: Bearer <access_token>` para JWT, ou `X-API-Key: hbk_live_...` (também aceito como `Authorization: Bearer hbk_live_...`) nas rotas de conteúdo/editorial/admin. API keys não podem chamar rotas de gerenciamento de conta (`/auth/*`).
- **Erros previsíveis:** todo erro usa `{"error": "código_estável"}` (às vezes com `message`). Códigos são snake_case e não mudam sem versionamento.
- **Paginação por cursor opaco:** nunca por offset. O cursor vai em `cursor`; a resposta traz `next_cursor` (string vazia = fim).
- **Idempotência:** endpoints de escrita aceitam `Idempotency-Key`; o middleware devolve a resposta original em repetições.

---

## 2. Mapa Completo de Endpoints

### 2.1 Operação

| Método | Rota | Auth | Descrição |
| :--- | :--- | :--- | :--- |
| GET | `/healthz` | — | Liveness. |
| GET | `/readyz` | — | Readiness (ping no PostgreSQL). |
| GET | `/metrics` | Bearer token¹ | Métricas Prometheus. |
| GET | `/api/v1/config` | — | Capacidades públicas da instância. |

¹ `HONBAKOO__METRICS__TOKEN`; vazio desabilita `/metrics` fora de dev/test.

### 2.2 Autenticação e conta (`/api/v1/auth`)

| Método | Rota | Auth | Descrição |
| :--- | :--- | :--- | :--- |
| POST | `/register` | — | Cria conta. Rate limit 10/min por IP. |
| POST | `/login` | — | Access + refresh token. 20/min por IP + lock durável de 10 falhas/15 min por IP + conta. |
| POST | `/refresh` | — | Rotaciona refresh token. |
| POST | `/logout` | — | Revoga refresh token. |
| POST | `/forgot-password` | — | Envia link (1h). Rate limit 60/min por IP. |
| POST | `/reset-password` | — | Redefine com token. |
| POST | `/verify-email` | — | Confirma e-mail com token (24h). |
| GET | `/me` | Bearer | Perfil do usuário. |
| DELETE | `/me` | Bearer | Soft-delete + anonimização (LGPD). |
| GET | `/me/export` | Bearer | Export completo dos dados (LGPD). |
| POST | `/verify-age` | Bearer | Declaração/verificação de idade. Retorna `200` com `access_token` atualizado. |
| GET | `/age-verification` | Bearer | Estado efetivo: `unverified`, `pending`, `verified`, `rejected` ou `expired`, com método, validade e motivo. |
| POST | `/change-password` | Bearer | Troca senha e revoga sessões. |
| POST | `/request-email-verification` | Bearer | Reenvia verificação. |
| POST | `/api-keys` | Bearer | Cria API key (retorna o segredo uma única vez). |
| GET | `/api-keys` | Bearer | Lista keys (sem segredo). |
| DELETE | `/api-keys/{id}` | Bearer | Revoga key. |

### 2.3 Catálogo e interações (`/api/v1/mangas`)

| Método | Rota | Auth | Descrição |
| :--- | :--- | :--- | :--- |
| GET | `/` | — | Busca/listagem. Query: `q`, `format`, `status`, `tag`, `cursor`, `limit`. |
| GET | `/updates` | — | Capítulos recentes. |
| GET | `/tags` | — | Tags disponíveis. |
| GET | `/{slug}` | — | Detalhe por slug. |
| GET | `/{slug}/chapters` | — | Capítulos publicados. |
| GET | `/favorites` | Bearer | Favoritos do usuário. |
| GET | `/history` | Bearer | Histórico de leitura. |
| PUT | `/{id}/rating` | Bearer | Define nota (1–10). |
| DELETE | `/{id}/rating` | Bearer | Remove nota. |
| POST | `/{id}/favorite` | Bearer | Favorita. |
| DELETE | `/{id}/favorite` | Bearer | Desfavorita. |
| PUT | `/{id}/history` | Bearer | Atualiza progresso. |
| DELETE | `/{id}/history` | Bearer | Remove do histórico. |

**Modos de catálogo:** `hybrid`, `sfw_only`, `nsfw_only`. O filtro roda no SQL antes do `LIMIT` e também em `GET /{slug}` e no reader; em `sfw_only`, obra NSFW responde `404`.

### 2.4 Leitor (`/api/v1/chapters`)

| Método | Rota | Auth | Descrição |
| :--- | :--- | :--- | :--- |
| GET | `/{id}/pages` | opcional | Manifesto de páginas + metadados. NSFW/VIP pode exigir idade/assinatura. |
| GET | `/{id}/pages/{page}/media` | opcional | Stream privado de uma página gated (`private, no-store`). Páginas públicas usam a URL da CDN do manifesto. |
| GET | `/{id}/download` | Bearer (VIP) | CBZ completo. Respeita `CONTENT__DOWNLOAD_MODE`. |

Cada item de `pages` traz `url`, `access` (`cdn`, `protected` ou `unavailable`) e os metadados. Em página `cdn`, `url` aponta para o storage imutável e `storage_key`/`variants` são expostos; em página `protected`, `url` aponta para `/api/v1/chapters/{id}/pages/{page}/media?token=<capability>`, `storage_key` e `variants` são omitidos; a capability expira em 10 minutos e é vinculada a capítulo/página/leitor para permitir `<img>` sem header `Authorization`.

**Contagem de views:** cada `GET /{id}/pages` bem-sucedido registra no máximo uma view por leitor, capítulo e dia UTC (`chapter_view_events`). Usuário autenticado é deduplicado por `user_id`; anônimo por HMAC de IP + User-Agent + dia, sem persistir IP bruto. O worker agrega os eventos em `manga_view_daily` e nos contadores `chapters.views_count` e `mangas.views_*` a cada 30 segundos; a leitura nunca faz `UPDATE` na linha quente da obra.

O CBZ é montado em arquivo temporário **antes** do status `200`, com `Content-Length`; falha de storage vira `500 {"error":"failed_to_build_archive"}` sem vazar detalhes.

**Vídeo:** capítulos com `media_type=video_stream` retornam `sources` tipadas (`direct_hls`, `direct_mp4` ou `external_embed`), com `resolution`, `stream_url` e `server_name`. O progresso usa o mesmo `PUT /mangas/{id}/history`, com `page_number` e `video_position_seconds`; a autorização é a mesma do leitor (idade, VIP e early access). O player nunca recebe `storage_key` ou URL administrativa.

### 2.5 Comunidade (`/api/v1/community`)

| Método | Rota | Auth | Descrição |
| :--- | :--- | :--- | :--- |
| GET | `/chapters/{id}/comments` | — | Árvore de comentários. |
| POST | `/chapters/{id}/comments` | Bearer | Comenta. |
| DELETE | `/comments/{id}` | Bearer | Remove (autor/moderação). |
| POST | `/comments/{id}/react` | Bearer | Reação. |
| DELETE | `/comments/{id}/react` | Bearer | Remove reação. |
| POST | `/reports` | Bearer | Abre denúncia. |
| GET | `/groups/{id}/reports` | Bearer (grupo) | Denúncias do grupo. |
| POST | `/reports/{id}/resolve` | Bearer (grupo) | Resolve denúncia. |

### 2.6 Editorial (`/api/v1/editorial`)

| Método | Rota | Auth | Descrição |
| :--- | :--- | :--- | :--- |
| POST | `/groups` | Bearer | Cria grupo. |
| POST | `/groups/{id}/members` | Bearer (líder) | Adiciona membro. |
| POST | `/mangas` | Bearer² | Cria obra (inclui `tag_ids`). |
| PATCH | `/mangas/{id}` | Bearer² | Atualiza obra (inclui `tag_ids`). |
| DELETE | `/mangas/{id}` | Bearer² | Remove obra. |
| POST | `/mangas/{id}/chapters` | Bearer² | Cria capítulo. |
| PATCH | `/chapters/{id}` | Bearer² | Atualiza capítulo. |
| DELETE | `/chapters/{id}` | Bearer² | Remove capítulo. |
| POST | `/chapters/{id}/pages` | Bearer² | Upload multipart de página. |
| POST | `/chapters/{id}/pages/import` | Bearer² | Importa 1–50 URLs via cliente anti-SSRF, com teto agregado de 512 MiB. |
| PATCH | `/chapters/{id}/pages/order` | Bearer² | Reordena páginas (permutação 1..n). |
| DELETE | `/chapters/{id}/pages/{page_number}` | Bearer² | Remove página. |

² Autorização conforme `EDITORIAL__CREATION_POLICY` (`group_member`, `open`, `admin_only`).

### 2.7 Administração (`/api/v1/admin`)

| Método | Rota | Auth | Descrição |
| :--- | :--- | :--- | :--- |
| GET | `/users` | Bearer admin | Lista usuários (cursor, `limit` ≤ 200). |
| GET | `/reports` | Bearer admin | Denúncias abertas. |
| POST | `/reports/{id}/resolve` | Bearer admin | Resolve denúncia. |
| POST | `/dmca/block` | Bearer admin | Bloqueia obra (cascateia capítulos). |
| POST | `/dmca/unblock` | Bearer admin | Desbloqueia. |
| POST | `/users/{id}/ban` | Bearer admin | Bane usuário. |
| POST | `/users/{id}/unban` | Bearer admin | Desbane. |

### 2.8 Billing (`/api/v1/billing`)

| Método | Rota | Auth | Descrição |
| :--- | :--- | :--- | :--- |
| POST | `/webhook` | assinatura | Webhook genérico (`X-Honbakoo-Signature`). |
| POST | `/webhook/{provider}` | assinatura | Provider específico (ex.: Stripe). |

Billing é montado apenas com `BILLING__ENABLED=true`.

---

## 3. Autenticação

### 3.1 Tokens

- **Access token:** JWT HMAC, TTL `AUTH__ACCESS_TOKEN_TTL` (15m).
- **Refresh token:** opaco, rotacionado a cada uso, TTL `AUTH__REFRESH_TOKEN_TTL` (720h).
- **API key:** `hbk_live_<32 hex>`; envie em `X-API-Key` ou `Authorization: Bearer hbk_...`. O segredo só aparece na criação.

### 3.2 Rate limiting

Duas camadas no login:

| Camada | Escopo | Limite |
| :--- | :--- | :--- |
| Em memória, por processo | IP | 20/min |
| Durável no PostgreSQL | HMAC(IP + e-mail) | 10 falhas/15 min; lock de 15 min |
| Em memória, por processo | IP | `register` 10/min, `forgot-password` 60/min |

Falhas de login e senha errada incrementam o balde durável; sucesso limpa a linha. A chave é HMAC-SHA256 e não persiste IP nem e-mail em claro. Se o PostgreSQL falhar, o throttle durável falha aberto (o limite em memória continua). Respostas de bloqueio são `429 {"error":"rate_limited"}` com `Retry-After`.

Com múltiplas réplicas, o limite em memória é por processo; o lock durável é compartilhado. Para limite global por IP, use um proxy/edge (Cloudflare, Traefik) ou Redis no perfil `scale`.

---

## 4. Paginação, cache e erros

### 4.1 Cursor

- `limit` default 20, máximo 100 (50/200 em `/admin/users`).
- A resposta inclui `next_cursor`; envie-o em `cursor` para a próxima página.
- Cursor é base64url opaco; não é necessário interpretá-lo.

### 4.2 Erros

| HTTP | Quando |
| :--- | :--- |
| `400` | JSON inválido, campo inválido, cursor inválido. |
| `401` | Token ausente/expirado/inválido. |
| `403` | Sem permissão, idade não verificada, download VIP. |
| `404` | Recurso inexistente ou oculto pelo modo de catálogo. |
| `409` | Conflito (slug/e-mail duplicado). |
| `413` | Corpo/arquivo acima do limite. |
| `429` | Rate limit excedido (inclui `Retry-After`). |
| `500` | Erro interno; nunca inclui detalhes de infraestrutura. |
| `502` | Falha ao buscar URL remota no import. |
| `503` | Readiness falhando ou modo somente leitura. |

Formato:

```json
{ "error": "invalid_cursor" }
```

### 4.3 Headers

- `X-Request-Id` é gerado/propagado para correlação de logs e também exposto no CORS.
- `Idempotency-Key` ecoado nas respostas de escrita.
- `X-Next-Cursor` também é enviado em `/admin/users` (além do corpo).
- CORS usa allow-list explícita (`HONBAKOO__SERVER__CORS_ORIGINS`), nunca `*` com credenciais. `Access-Control-Expose-Headers` inclui `Link`, `ETag`, `Idempotency-Key` e `X-Request-ID`.
- Páginas protegidas respondem `Cache-Control: private, no-store`; páginas públicas usam cache imutável na CDN.
- Se `/media` responder `403 invalid_media_token`, o frontend deve refazer `GET /{id}/pages` para obter uma nova capability de 10 minutos.

---

## 5. Compatibilidade

Mudanças incompatíveis exigem `/api/v2` ou período de depreciação documentado. Campos novos podem ser adicionados; clientes devem ignorar campos desconhecidos.

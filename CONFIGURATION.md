# ⚙️ Honbakoo Configuration Specification (Self-Hosted Architecture)

> **Inspiração:** Modelos consagrados de self-hosted de alta escala (**Gitea/Forgejo** e **Supabase**), adaptados para máxima leveza e zero atrito de instalação.
> **Filosofia:** _"Convention over Configuration"_ — a plataforma sobe 100% funcional com defaults inteligentes ("Zero-Config"), mas oferece controle cirúrgico para administradores avançados.

---

## 1. Hierarquia de Configuração

```mermaid
flowchart TD
    C1["Camada 1: Defaults embutidos no código Go"]
    C2["Camada 2: .env e variáveis de ambiente do processo"]
    C3["Camada 3: system_settings no PostgreSQL (reservada)"]

    C1 -->|sobrescrito por| C2
    C2 -.->|previsto| C3
```

1. **Camada 1 — Defaults embutidos.** Valores seguros em `internal/config/config.go`. Sem nenhum arquivo ou variável, a API sobe na porta `8080`, com storage local e políticas conservadoras.
2. **Camada 2 — Ambiente.** `.env` (lido do diretório de trabalho, sem sobrescrever variáveis já definidas) ou variáveis do contêiner. Alterações exigem restart.
3. **Camada 3 — `system_settings`.** A tabela e as queries existem no schema, mas **ainda não há endpoint nem hot-reload ligado a ela**. Toda configuração efetiva hoje vem da Camada 2. Não documente nem dependa de hot-reload até a Camada 3 ser implementada.

A validação é **fail-closed**: `config.Validate()` roda no boot e derruba o processo com configuração inválida. Em `HONBAKOO__ENV=production` há checagens adicionais de segredos.

---

## 2. Convenção de Nomenclatura

```text
HONBAKOO__<SEÇÃO>__<CHAVE>=<valor>
```

- Prefixo obrigatório `HONBAKOO__`.
- Separador de seção `__` (dois underscores).
- Nomes em `SCREAMING_SNAKE_CASE`.
- Durações usam a sintaxe de `time.ParseDuration` (`5s`, `15m`, `720h`).
- Booleanos aceitam `true/false`, `1/0`, `yes/no`, `on/off`.

Arquivo de referência pronto para copiar: [`engine/.env.example`](https://github.com/Honbakoo/engine/blob/main/.env.example).

---

## 3. Matriz Completa de Configuração

### 3.1 Ambiente e Servidor (`HONBAKOO__ENV`, `HONBAKOO__SERVER__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__ENV` | string | `production` | `production`, `development` ou `test`. Em produção a inicialização exige segredos fortes, banco não-padrão e `PUBLIC_URL` HTTPS. |
| `HONBAKOO__SERVER__HOST` | string | `0.0.0.0` | Endereço de bind. |
| `HONBAKOO__SERVER__PORT` | int | `8080` | Porta TCP (1–65535). |
| `HONBAKOO__SERVER__PUBLIC_URL` | string | `http://localhost:8080` | URL pública canônica da API. Usada em CORS, links de e-mail e URLs de mídia local (`/uploads`). Precisa ser `https` em produção. Não é usada como base do S3. |
| `HONBAKOO__SERVER__CORS_ORIGINS` | CSV | `""` | Origens exatas permitidas (esquema + host + porta, sem path). Vazio usa `http://localhost:3000`, `http://localhost:8080` e `PUBLIC_URL`. Nunca use `*` com credenciais. |
| `HONBAKOO__SERVER__READ_HEADER_TIMEOUT` | duration | `5s` | Timeout de leitura dos headers (anti-Slowloris). |
| `HONBAKOO__SERVER__READ_TIMEOUT` | duration | `5m` | Timeout de leitura da requisição. |
| `HONBAKOO__SERVER__WRITE_TIMEOUT` | duration | `5m` | Timeout de escrita da resposta; precisa acomodar downloads de CBZ grandes. |
| `HONBAKOO__SERVER__TRUSTED_PROXIES` | string | `127.0.0.1/32,10.0.0.0/8` | CIDRs confiáveis para `X-Forwarded-For`/`CF-Connecting-IP`. |
| `HONBAKOO__SERVER__PROFILE` | string | `budget` | `budget` ou `scale`. Hoje é informativo (telemetria/config público): storage vem de `STORAGE__BACKEND` e a fila é sempre PostgreSQL. Réplicas da API são stateless. |
| `HONBAKOO__SERVER__READ_ONLY` | bool | `false` | Modo manutenção: bloqueia toda escrita, exceto login/refresh/logout/recuperação de senha/verificação de e-mail/`/auth/me`/webhook de billing. |

### Seed de desenvolvimento

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__AUTO_SEED` | bool | `false` | Executa o seed no startup. Só tem efeito em `development`/`test` para o catálogo demo. Nunca habilite em produção. |
| `HONBAKOO__SEED__ADMIN_USERNAME` | string | `admin` | Username do admin inicial. |
| `HONBAKOO__SEED__ADMIN_EMAIL` | string | `admin@honbakoo.org` | E-mail do admin inicial. |
| `HONBAKOO__SEED__ADMIN_PASSWORD` | string | vazio | Em dev, vazio usa `HonbakooAdmin!2026`; em produção, vazio gera senha aleatória e a registra no log apenas na criação. |

Personas demo (senha `HonbakooDemo!2026`): `reader@honbakoo.test`, `verified@honbakoo.test`, `vip@honbakoo.test`, `banned@honbakoo.test`.

### 3.2 Banco de Dados (`HONBAKOO__DATABASE__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__DATABASE__URL` | string | `postgres://honbakoo_user:honbakoo_password@localhost:5432/honbakoo_db?sslmode=disable` | String de conexão PostgreSQL 16+. Em produção o valor padrão é rejeitado. |
| `HONBAKOO__DATABASE__MAX_OPEN_CONNS` | int | `25` | Máximo de conexões abertas no pool `pgx`. |
| `HONBAKOO__DATABASE__MIN_IDLE_CONNS` | int | `5` | Conexões ociosas mantidas. |
| `HONBAKOO__DATABASE__CONN_MAX_LIFETIME` | duration | `1h` | Tempo máximo de vida de uma conexão. |
| `HONBAKOO__DATABASE__CONN_MAX_IDLE_TIME` | duration | `30m` | Tempo máximo de ociosidade. |

### 3.3 Autenticação e Políticas de Acesso (`HONBAKOO__AUTH__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__AUTH__JWT_SECRET` | string | placeholder inseguro | Chave HMAC dos access tokens. Em produção: mínimo 32 bytes e diferente do placeholder (`openssl rand -base64 32`). |
| `HONBAKOO__AUTH__ACCESS_TOKEN_TTL` | duration | `15m` | Validade do access token. |
| `HONBAKOO__AUTH__REFRESH_TOKEN_TTL` | duration | `720h` | Validade do refresh token rotativo. Deve ser maior que o access TTL. |
| `HONBAKOO__AUTH__AGE_VERIFICATION_MODE` | string | `self_declaration` | `disabled`, `self_declaration` ou `strict`. |
| `HONBAKOO__AUTH__REGISTRATION_MODE` | string | `public` | `public` ou `disabled`. |

> Não existem variáveis de Argon2/pepper: os parâmetros de hash são fixos no código e o refresh token é opaco com hash no banco.

### 3.4 Conteúdo (`HONBAKOO__CONTENT__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__CONTENT__DOWNLOAD_MODE` | string | `vip_only` | `public`, `vip_only` ou `disabled`. `vip_only` exige billing habilitado. |
| `HONBAKOO__CONTENT__CATALOG_MODE` | string | `hybrid` | `hybrid`, `sfw_only` ou `nsfw_only`. Aplicado no SQL de busca/listagem e também em `GET /mangas/{slug}` e no reader. |

### 3.5 Editorial (`HONBAKOO__EDITORIAL__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__EDITORIAL__CREATION_POLICY` | string | `group_member` | `group_member`, `open` ou `admin_only`. |

### 3.6 Comunidade (`HONBAKOO__COMMUNITY__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__COMMUNITY__COMMENTS_ENABLED` | bool | `true` | Liga/desliga comentários. |
| `HONBAKOO__COMMUNITY__REPORTS_ENABLED` | bool | `true` | Liga/desliga denúncias. |

### 3.7 Storage (`HONBAKOO__STORAGE__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__STORAGE__BACKEND` | string | `local` | `local` ou `s3`. |
| `HONBAKOO__STORAGE__LOCAL_PATH` | string | `./uploads` | Diretório de mídia no disco (apenas `local`). |
| `HONBAKOO__STORAGE__HOTLINK_PROTECTION` | bool | `false` | Ativa checagem de `Referer` em `/uploads` (deixe desligado atrás de CDN). |
| `HONBAKOO__STORAGE__S3_ENDPOINT` | string | `""` | Host[:porta] do endpoint S3-compatível (R2, B2, MinIO, AWS), sem `https://`. Obrigatório com `BACKEND=s3`. |
| `HONBAKOO__STORAGE__S3_REGION` | string | `auto` | Região do bucket. |
| `HONBAKOO__STORAGE__S3_BUCKET` | string | `""` | Nome do bucket. Obrigatório com `BACKEND=s3`. |
| `HONBAKOO__STORAGE__S3_ACCESS_KEY` | string | `""` | Access key. Obrigatória com `BACKEND=s3`. |
| `HONBAKOO__STORAGE__S3_SECRET_KEY` | string | `""` | Secret key. Obrigatória com `BACKEND=s3`. |
| `HONBAKOO__STORAGE__S3_USE_SSL` | bool | `true` | Usa HTTPS para falar com o endpoint. |
| `HONBAKOO__STORAGE__S3_PUBLIC_URL` | string | `""` | Base pública/CDN do bucket usada nas URLs do reader. Obrigatória com `BACKEND=s3`; não use a URL da API. |

> Com `BACKEND=s3`, o bucket é criado automaticamente se não existir e `/uploads` deixa de ser servido pela API; `PublicURL` é `S3_PUBLIC_URL` + chave do objeto. Não há variáveis `CDN_BASE_URL`/`MIRROR_URLS` implementadas.

### 3.8 Billing (`HONBAKOO__BILLING__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__BILLING__ENABLED` | bool | `true` | Liga VIP/billing. |
| `HONBAKOO__BILLING__WEBHOOK_SECRET` | string | placeholder inseguro | Segredo do webhook genérico. Em produção: mínimo 32 bytes e diferente do placeholder. |
| `HONBAKOO__BILLING__STRIPE_WEBHOOK_SECRET` | string | `""` | Segredo de assinatura do Stripe (`whsec_...`), opcional. |

### 3.9 E-mail transacional (`HONBAKOO__SMTP__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__SMTP__ENABLED` | bool | `false` | Quando falso, e-mails são apenas logados (sem corpo/token). |
| `HONBAKOO__SMTP__HOST` | string | `""` | Host SMTP. Obrigatório quando habilitado. |
| `HONBAKOO__SMTP__PORT` | int | `587` | Porta SMTP (1–65535) com STARTTLS obrigatório para AUTH; TLS mínimo 1.2. TLS implícito (465) não é suportado. |
| `HONBAKOO__SMTP__USERNAME` | string | `""` | Usuário para `PLAIN AUTH` (opcional). Se definido, o servidor precisa anunciar STARTTLS e AUTH; credenciais nunca são enviadas em texto puro. |
| `HONBAKOO__SMTP__PASSWORD` | string | `""` | Senha do usuário SMTP. |
| `HONBAKOO__SMTP__FROM` | string | `no-reply@honbakoo.local` | Remetente; precisa conter `@`. |

Os links enviados usam `HONBAKOO__SERVER__PUBLIC_URL`:
- redefinição de senha: `.../reset-password?token=...` (1h);
- verificação de e-mail: `.../verify-email?token=...` (24h).

### 3.10 Observabilidade (`HONBAKOO__METRICS__*`, `HONBAKOO__LOG__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__METRICS__TOKEN` | string | `""` | Bearer token exigido por `/metrics` fora de dev/test. Vazio desabilita o endpoint nesses ambientes. |
| `HONBAKOO__LOG__LEVEL` | string | `info` | `debug`, `info`, `warn` ou `error`. |
| `HONBAKOO__LOG__FORMAT` | string | `json` | `json` ou `text`. |

### 3.11 Variáveis que NÃO existem

As seções abaixo apareciam em versões antigas desta especificação e **não são lidas pelo código**:

- `HONBAKOO_PROFILE` (use `HONBAKOO__SERVER__PROFILE`);
- `HONBAKOO__STORAGE__DRIVER` (use `...__BACKEND`);
- `HONBAKOO__AUTH__JWT_EXPIRY` / `...__REFRESH_TOKEN_EXPIRY` (use `...__ACCESS_TOKEN_TTL` / `...__REFRESH_TOKEN_TTL`);
- `HONBAKOO__AUTH__REFRESH_PEPPER`, `...__ARGON2_*`;
- `HONBAKOO__CACHE__*`, `HONBAKOO__QUEUE__*`, `HONBAKOO__LIMITS__*`;
- `HONBAKOO__STORAGE__CDN_BASE_URL`, `...__MIRROR_URLS`;
- `HONBAKOO__FEATURES__ENABLE_AGE_VERIFICATION` (use `HONBAKOO__AUTH__AGE_VERIFICATION_MODE`).

---

## 4. Configuração Dinâmica (`system_settings`)

A tabela existe e as queries `GetSetting`, `ListPublicSettings` e `UpsertSetting` estão geradas, mas **não há serviço, endpoint `PATCH /admin/settings` ou hot-reload conectado**. Trate-a como reservada para trabalho futuro; qualquer mudança de comportamento hoje exige alterar a Camada 2 e reiniciar.

---

## 5. Rota Pública de Configuração (`GET /api/v1/config`)

O frontend descobre o que a instância oferece numa única chamada (sem autenticação):

```http
GET /api/v1/config
```

```json
{
  "site_name": "Honbakoo",
  "public_url": "https://honbakoo.example",
  "profile": "budget",
  "allow_registration": true,
  "age_verification_mode": "self_declaration",
  "billing_enabled": true,
  "comments_enabled": true,
  "reports_enabled": true,
  "download_mode": "vip_only",
  "catalog_mode": "hybrid",
  "read_only": false
}
```

O contrato exato está em `engine/api/openapi.yaml` e é validado por `TestOpenAPIMatchesRouter`.

---

## 6. `.env.example` completo

O arquivo canônico fica em [`engine/.env.example`](https://github.com/Honbakoo/engine/blob/main/.env.example) e contém todas as variáveis acima com comentários. Para começar:

```bash
cp .env.example .env
# edite DATABASE__URL e gere os segredos:
openssl rand -base64 32
```

Em produção, no mínimo:

```env
HONBAKOO__ENV=production
HONBAKOO__DATABASE__URL=postgres://user:pass@host:5432/honbakoo?sslmode=require
HONBAKOO__AUTH__JWT_SECRET=<32+ bytes aleatórios>
HONBAKOO__BILLING__WEBHOOK_SECRET=<32+ bytes aleatórios>
HONBAKOO__SERVER__PUBLIC_URL=https://honbakoo.example
```

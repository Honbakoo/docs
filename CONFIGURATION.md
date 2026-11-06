# ⚙️ Honbakoo Configuration Specification (Self-Hosted Architecture)

> **Inspiração:** Modelos consagrados de self-hosted de alta escala (**Gitea/Forgejo** e **Supabase**), adaptados para máxima leveza e zero atrito de instalação.  
> **Filosofia:** *"Convention over Configuration"* — a plataforma sobe 100% funcional com defaults inteligentes ("Zero-Config"), mas oferece controle cirúrgico para administradores avançados.

---

## 1. A Hierarquia das 3 Camadas de Configuração

Para evitar os erros do GitLab (arquivos de configuração gigantes de 2.000 linhas) e do Ghost (necessidade de restart para qualquer ajuste de texto), o Honbakoo implementa uma **Hierarquia em 3 Camadas**:

```mermaid
flowchart TD
    C1["Camada 1: Defaults Embutidos no Código Go (Hardcoded Sanity Defaults)"]
    C2["Camada 2: Arquivo .env / config.yaml & Variáveis de Ambiente (Infraestrutura Estática)"]
    C3["Camada 3: Tabela system_settings no PostgreSQL (Configurações Dinâmicas / Hot-Reload)"]

    C1 -->|Sobrescrito por| C2
    C2 -->|Sobrescrito por| C3
    C3 --> FinalConfig["Configuração Efetiva em Runtime"]
```

1. **Camada 1 (Defaults Embutidos):** Valores seguros definidos no código Go. Se nenhum arquivo ou variável for fornecido, a aplicação sobe ouvindo na porta `8080`, com storage local e limites padrões de segurança.
2. **Camada 2 (Ambiente & Infraestrutura Estática):** Conexão do banco de dados, chaves criptográficas JWT, endpoints de S3 e portas de rede. Gerenciado via `.env` ou variáveis de contêiner. Exige reinício do processo em caso de alteração.
3. **Camada 3 (Tabela de Banco Dinâmica com Hot-Reload):** Nome do site, se aceita novos registros, banners de aviso, limites de upload por leitor e ativação de módulos (anime, doujinshi). Pode ser alterado em tempo real via Painel Administrativo sem reiniciar o servidor.

---

## 2. Convenção de Nomenclatura de Variáveis (Padrão Gitea / 12-Factor)

Todas as variáveis de ambiente seguem o padrão estruturado com prefixo `HONBAKOO__` e separador duplo de subseção `__`:

```text
HONBAKOO__<SEÇÃO>__<CHAVE>=<VALOR>
```

Isso permite mapear diretamente estruturas de configuração complexas (YAML/JSON) para variáveis de ambiente no Docker ou Kubernetes sem ambiguidade.

---

## 3. Matriz Completa de Configuração de Infraestrutura (Camada 2)

### 3.1 Servidor & Rede (`HONBAKOO__SERVER__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__SERVER__PORT` | int | `8080` | Porta TCP onde a API escuta. |
| `HONBAKOO__SERVER__HOST` | string | `0.0.0.0` | Endereço de bind de rede. |
| `HONBAKOO__SERVER__READ_TIMEOUT` | duration | `10s` | Timeout de leitura de requisição HTTP (anti-Slowloris). |
| `HONBAKOO__SERVER__WRITE_TIMEOUT`| duration | `15s` | Timeout de resposta HTTP (anti-connection leak). |
| `HONBAKOO__SERVER__PUBLIC_URL` | string | `http://localhost:8080` | URL pública canônica (usada em links e manifestos). |
| `HONBAKOO__SERVER__TRUSTED_PROXIES`| string | `127.0.0.1/32,10.0.0.0/8` | CIDRs confiáveis para leitura de cabeçalhos de IP (`CF-Connecting-IP`, `X-Forwarded-For`). |

### 3.2 Banco de Dados (`HONBAKOO__DATABASE__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__DATABASE__URL` | string | *(obrigatório)* | String de conexão PostgreSQL (`postgres://user:pass@host:5432/db?sslmode=disable`). |
| `HONBAKOO__DATABASE__MAX_OPEN_CONNS`| int | `25` (budget) / `50` (scale) | Limite máximo de conexões abertas no pool `pgx`. |
| `HONBAKOO__DATABASE__MIN_IDLE_CONNS`| int | `5` | Conexões mantidas ociosas e prontas para uso. |
| `HONBAKOO__DATABASE__MAX_CONN_LIFETIME`| duration | `30m` | Tempo máximo de vida de uma conexão TCP antes da reciclagem. |

### 3.3 Armazenamento de Mídia (`HONBAKOO__STORAGE__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__STORAGE__DRIVER` | string | `local` | Provedor de storage: `local` ou `s3`. |
| `HONBAKOO__STORAGE__LOCAL_PATH` | string | `./data/media` | Diretório no disco local se `DRIVER=local`. |
| `HONBAKOO__STORAGE__S3_ENDPOINT`| string | `""` | Endpoint S3 (ex: `https://<id>.r2.cloudflarestorage.com`). |
| `HONBAKOO__STORAGE__S3_BUCKET` | string | `honbakoo-media` | Nome do bucket. |
| `HONBAKOO__STORAGE__S3_ACCESS_KEY`| string | `""` | Access Key ID do S3/R2/B2. |
| `HONBAKOO__STORAGE__S3_SECRET_KEY`| string | `""` | Secret Access Key (mascarado nos logs). |
| `HONBAKOO__STORAGE__S3_REGION` | string | `auto` | Região do bucket S3. |
| `HONBAKOO__STORAGE__CDN_BASE_URL`| string | `""` | URL da CDN pública na frente do storage (ex: `https://cdn.site.com`). |
| `HONBAKOO__STORAGE__MIRROR_URLS`| string | `""` | URLs de mirrors de backup separadas por vírgula em caso de falha do CDN principal. |

### 3.4 Autenticação & Segurança (`HONBAKOO__AUTH__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__AUTH__JWT_SECRET` | string | *(gerado no init se vazio)* | Chave HMAC de 256 bits para assinatura de Access Tokens. |
| `HONBAKOO__AUTH__JWT_EXPIRY` | duration | `15m` | Tempo de vida do Access Token em memória. |
| `HONBAKOO__AUTH__REFRESH_TOKEN_EXPIRY`| duration | `30d` | Tempo de vida máximo do Refresh Token rotativo. |
| `HONBAKOO__AUTH__REFRESH_PEPPER` | string | *(obrigatório)* | Pimenta criptográfica usada no hash do refresh token. |
| `HONBAKOO__AUTH__ARGON2_MEMORY` | int | `65536` (64MB) | Memória alocada para hashing de senhas. |
| `HONBAKOO__AUTH__ARGON2_TIME` | int | `3` | Número de iterações do algoritmo Argon2id. |

### 3.5 Cache & Filas (`HONBAKOO__CACHE__*` e `HONBAKOO__QUEUE__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__CACHE__DRIVER` | string | `memory` | Provedor de cache: `memory` (Ristretto) ou `redis`. |
| `HONBAKOO__CACHE__REDIS_URL` | string | `""` | URL de conexão Redis (`redis://:pass@host:6379/0`). |
| `HONBAKOO__QUEUE__DRIVER` | string | `postgres` (budget) / `redis` (scale) | Motor de fila de tarefas em background. |

### 3.6 Limites & Proteção Defensiva (`HONBAKOO__LIMITS__*`)

| Variável | Tipo | Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `HONBAKOO__LIMITS__MEDIA_MAX_BYTES` | int | `5242880` (5MB) | Tamanho máximo por imagem individual. |
| `HONBAKOO__LIMITS__MEDIA_MAX_PIXELS`| int | `50000000` (50 MP) | Teto máximo de resolução contra bombas de descompressão. |
| `HONBAKOO__LIMITS__UPLOAD_MAX_CONCURRENCY`| int | `1` (budget) / `8` (scale) | Número de conversões WebP paralelas via `libvips`. |

---

## 4. Tabela de Configurações Dinâmicas no Banco (`system_settings` - Camada 3)

Configurações operacionais que podem ser alteradas em tempo real via Painel Administrativo ou chamada autenticada `PATCH /api/v1/admin/settings`:

```sql
CREATE TABLE system_settings (
    key VARCHAR(64) PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    is_public BOOLEAN NOT NULL DEFAULT FALSE, -- Se true, é serializado em GET /api/v1/config para o frontend
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Chaves Dinâmicas Suportadas de Fábrica:

1. **`app.general` (`is_public = TRUE`):**
   ```json
   {
     "site_name": "Honbakoo Reader",
     "site_description": "O melhor leitor de mangás e doujinshis da comunidade",
     "default_language": "pt-br",
     "allow_registrations": true,
     "maintenance_mode": false,
     "announcement_banner": "Novo servidor de imagens ativo com velocidade 10x maior!"
   }
   ```
2. **`features.modules` (`is_public = TRUE`):**
   ```json
   {
     "enable_manga": true,
     "enable_doujinshi": true,
     "enable_webtoon": true,
     "enable_anime_video": false,
     "enable_age_verification": true
   }
   ```
3. **`moderation.rules` (`is_public = FALSE`):**
   ```json
   {
     "auto_quarantine_report_threshold": 5,
     "daily_upload_limit_new_users": 3,
     "comment_min_reputation_score": 0
   }
   ```
4. **`vip.plans` (`is_public = TRUE`):**
   ```json
   {
     "monthly_price_brl": 15.00,
     "early_access_days": 7,
     "enable_cbz_downloads": true
   }
   ```

---

## 5. Rota Pública de Configuração para Frontends (`GET /api/v1/config`)

O frontend web ou app mobile não precisa adivinhar o que a instância suporta. Ele faz uma única requisição na inicialização:

```http
GET /api/v1/config
Cache-Control: public, max-age=300
```

**Resposta:**
```json
{
  "success": true,
  "data": {
    "site_name": "Honbakoo Reader",
    "version": "1.0.0",
    "modules": {
      "manga": true,
      "doujinshi": true,
      "webtoon": true,
      "anime_video": false
    },
    "features": {
      "age_verification_required": true,
      "registrations_open": true
    },
    "default_language": "pt-br",
    "supported_languages": ["pt-br", "en", "es", "ja"]
  }
}
```

---

## 6. O Arquivo `.env.example` Completo

```env
# ==============================================================================
# HONBAKOO ENGINE - CONFIGURAÇÃO BÁSICA
# ==============================================================================

# PERFIL: 'budget' (1 VPS, 512MB-1GB, tudo local) ou 'scale' (Nuvem, S3, Redis)
HONBAKOO_PROFILE=budget

# BANCO DE DADOS POSTGRESQL (OBRIGATÓRIO)
HONBAKOO__DATABASE__URL=postgres://honbakoo:honbakoopass@localhost:5432/honbakoo?sslmode=disable

# SEGREDOS CRIPTOGRÁFICOS (Gere com: openssl rand -base64 32)
HONBAKOO__AUTH__JWT_SECRET=substitua_por_uma_chave_secreta_longa_e_aleatoria
HONBAKOO__AUTH__REFRESH_PEPPER=substitua_por_outra_chave_secreta_longa

# STORAGE: 'local' (usa pasta no disco) ou 's3' (Cloudflare R2 / Backblaze B2)
HONBAKOO__STORAGE__DRIVER=local
HONBAKOO__STORAGE__LOCAL_PATH=./data/media

# DESCOMENTE SE FOR USAR S3 / CLOUDFLARE R2
# HONBAKOO__STORAGE__DRIVER=s3
# HONBAKOO__STORAGE__S3_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
# HONBAKOO__STORAGE__S3_BUCKET=honbakoo-media
# HONBAKOO__STORAGE__S3_ACCESS_KEY=sua_access_key
# HONBAKOO__STORAGE__S3_SECRET_KEY=sua_secret_key
# HONBAKOO__STORAGE__CDN_BASE_URL=https://cdn.meusite.org

# CONFORMIDADE E AFERIÇÃO DE IDADE (ECA Digital Brasil)
HONBAKOO__FEATURES__ENABLE_AGE_VERIFICATION=strict
```

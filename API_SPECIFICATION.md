# 🔌 Honbakoo RESTful API Specification (Headless Contract)

> **Versão da API:** `v1`  
> **Protocolo:** HTTP/2 ou HTTP/3 sobre TLS (Stateless puro, zero WebSockets para máxima eficiência e compatibilidade com CDNs)  
> **Formato de Dados:** JSON (RFC 8259)  
> **Autenticação:** Bearer JWT (Access Token) + HttpOnly Cookie / Header (Refresh Token)  
> **Convenção de Paginação:** Cursor-based pagination (`cursor` baseado em UUIDv7 / CreatedAt) para consultas em tempo constante $O(1)$.

---

## 1. Princípios de Design da API

1. **Edge-Cache Friendly (Stateless):** Rotas públicas de catálogo, capítulos e comentários geram cabeçalhos de cache otimizados (`ETag`, `Cache-Control: public, max-age=...`) para que CDNs (Cloudflare / Caddy) absorvam mais de 90% do tráfego sem tocar na CPU do servidor.
2. **Cursor Pagination:** Elimina o lento `OFFSET` em tabelas com milhares de registros. O cliente envia `limit=20&cursor=018d45...` garantindo performance contínua.
3. **Mutações Otimistas no Frontend:** O envio de comentários e reações atualiza a interface do usuário instantaneamente enquanto o `POST` é processado em segundo plano, entregando a sensação de tempo real sem os custos e instabilidades de WebSockets contínuos.
4. **Respostas Padronizadas:**

```json
{
  "success": true,
  "data": { ... },
  "meta": {
    "next_cursor": "018d45f3-...",
    "has_more": true
  }
}
```

---

## 2. Mapa Completo de Endpoints

```mermaid
flowchart LR
    subgraph "Catálogo & Conteúdo (Edge Cached)"
        A1[GET /api/v1/mangas] --> A2[GET /api/v1/mangas/:slug]
        A2 --> A3[GET /api/v1/chapters/:id]
        A3 --> A4[GET /api/v1/chapters/:id/pages]
        A3 --> A5[GET /api/v1/chapters/:id/sources]
        A1 --> A6[GET /api/v1/tags]
        A1 --> A7[GET /api/v1/creators/:slug]
    end

    subgraph "Comunidade (REST Puro)"
        C1[GET /api/v1/chapters/:id/comments]
        C2[POST /api/v1/chapters/:id/comments]
        C3[POST /api/v1/comments/:id/react]
    end

    subgraph "Auth & Usuário"
        U1[POST /api/v1/auth/register]
        U2[POST /api/v1/auth/login]
        U3[POST /api/v1/auth/refresh]
        U4[GET /api/v1/users/me/library]
        U5[POST /api/v1/users/me/history]
    end

    subgraph "Ingestão & Scanlators"
        I1[POST /api/v1/ingest/manga]
        I2[POST /api/v1/ingest/chapter]
        I3[POST /api/v1/uploads/presigned-url]
    end
```

---

## 3. Especificação Detalhada por Módulo

### 3.1 Módulo de Catálogo & Busca (`/api/v1/mangas`)

#### `GET /api/v1/mangas`
Listagem de catálogo com filtros universais e busca booleana por tags.

* **Query Parameters:**
  * `format` (opcional): `manga`, `manhwa`, `manhua`, `doujinshi`, `anime_h`, `anime_m`
  * `lang` (opcional): Código de idioma preferido para título/sinopse (default: `pt-br`)
  * `tags_include` (opcional): Array de slugs ou IDs (`12,45` ou `romance,action`)
  * `tags_exclude` (opcional): Array de slugs ou IDs a proibir (`netorare,gore`)
  * `creator` (opcional): Slug de artista ou roteirista
  * `search` (opcional): Texto para busca com trigramas no título
  * `sort` (opcional): `trending`, `popular`, `latest`, `rating` (default: `trending`)
  * `limit` (opcional): Padrão `24`, máx `100`
  * `cursor` (opcional): UUIDv7 da última obra recebida

* **Resposta de Sucesso (`200 OK`):**
```json
{
  "success": true,
  "data": [
    {
      "id": "018d45f3-a12b-7c3d-9e4f-5a6b7c8d9e0f",
      "display_title": "Aventuras no Outro Mundo",
      "original_title": "Otherworldly Adventures",
      "original_language": "ko",
      "slug": "aventuras-no-outro-mundo",
      "format": "manhwa",
      "reading_direction": "vertical_scroll",
      "is_gallery": false,
      "is_nsfw": false,
      "cover_url": "https://cdn.honbakoo.org/covers/018d45f3...webp",
      "views_all_time": 154200,
      "views_weekly": 12800,
      "rating_score": "9.45",
      "tags": [
        {"id": 1, "name": "Ação", "slug": "acao", "category": "general"},
        {"id": 14, "name": "Fantasia", "slug": "fantasia", "category": "general"}
      ],
      "creators": [
        {"name": "Park Jin-Woo", "slug": "park-jin-woo", "role": "story"},
        {"name": "Studio Red", "slug": "studio-red", "role": "art"}
      ]
    }
  ],
  "meta": {
    "next_cursor": "018d45f3-a12b-7c3d-9e4f-5a6b7c8d9e0f",
    "has_more": true
  }
}
```

---

### 3.2 Módulo de Leitor & Player (`/api/v1/chapters`)

#### `GET /api/v1/chapters/:id/pages` (Mangá / Manhwa / Doujinshi)
Retorna as páginas ordenadas para renderização.

* **Headers de Resposta:** `Cache-Control: public, max-age=86400, immutable`
* **Resposta de Sucesso (`200 OK`):**
```json
{
  "success": true,
  "data": {
    "chapter_id": "018d4610-b23c-7d4e-af5a-6b7c8d9e0f1a",
    "reading_direction": "vertical_scroll",
    "pages_count": 28,
    "pages": [
      {
        "page_number": 1,
        "url": "https://cdn.honbakoo.org/media/a1/b2/c3/a1b2c3d4e5f6...webp?token=hmac&exp=1794000000",
        "width": 1200,
        "height": 1800,
        "byte_size": 245100
      }
    ]
  }
}
```

#### `GET /api/v1/chapters/:id/sources` (Anime / Anime-H / Vídeo)
Retorna os servidores de streaming e legendas.

* **Resposta de Sucesso (`200 OK`):**
```json
{
  "success": true,
  "data": {
    "chapter_id": "018d4610-b23c-7d4e-af5a-6b7c8d9e0f1a",
    "sources": [
      {
        "server_name": "Main Server",
        "source_type": "direct_hls",
        "resolution": "1080p",
        "stream_url": "https://stream.honbakoo.org/hls/ep01/master.m3u8"
      },
      {
        "server_name": "Mirror Embed (Zero Egress)",
        "source_type": "external_embed",
        "resolution": "auto",
        "stream_url": "https://streamtape.com/e/abc123xyz/"
      }
    ],
    "subtitles": [
      {
        "language_code": "pt-br",
        "label": "Português",
        "subtitle_url": "https://cdn.honbakoo.org/subs/ep01_pt.vtt",
        "is_default": true
      }
    ]
  }
}
```

---

### 3.3 Módulo de Comunidade & Comentários (`/api/v1/comments` - REST Puro)

#### `GET /api/v1/chapters/:id/comments`
Retorna a árvore hierárquica de comentários (construída via `ltree`).

* **Headers de Resposta:** `Cache-Control: public, max-age=30, stale-while-revalidate=60`
* **Resposta de Sucesso (`200 OK`):**
```json
{
  "success": true,
  "data": [
    {
      "id": "018d4650-1111-7777-8888-999999999999",
      "parent_id": null,
      "user": {
        "username": "OtakuMaster",
        "avatar_url": "https://cdn.honbakoo.org/avatars/user1.webp",
        "role": "vip"
      },
      "content": "Esse capítulo foi sensacional!",
      "likes_count": 42,
      "dislikes_count": 1,
      "created_at": "2026-11-06T13:10:00Z",
      "replies": [
        {
          "id": "018d4655-2222-7777-8888-999999999999",
          "parent_id": "018d4650-1111-7777-8888-999999999999",
          "user": {
            "username": "ScanReader",
            "avatar_url": "https://cdn.honbakoo.org/avatars/user2.webp",
            "role": "user"
          },
          "content": "Concordo totalmente!",
          "likes_count": 8,
          "dislikes_count": 0,
          "created_at": "2026-11-06T13:15:00Z",
          "replies": []
        }
      ]
    }
  ]
}
```

#### `POST /api/v1/chapters/:id/comments`
* **Autenticação:** Bearer JWT
* **Body:**
  * `parent_id` (opcional): UUIDv7 do comentário pai se for resposta
  * `content`: Texto do comentário (máx 2.000 caracteres)

#### `POST /api/v1/comments/:id/react`
* **Autenticação:** Bearer JWT
* **Body:** `{"is_like": true}`

---

### 3.4 Módulo de Ingestão & Upload (`/api/v1/ingest` & `/api/v1/uploads`)

#### `POST /api/v1/uploads/presigned-url`
Gera URLs pré-assinadas com expiração temporária e verificação de deduplicação prévia por hash SHA-256.

* **Autenticação:** Bearer Token de Scanlator/Admin ou `X-API-Key`
* **Request:**
```json
{
  "files": [
    {
      "filename": "page_001.webp",
      "byte_size": 245100,
      "sha256_hash": "a1b2c3d4e5f6...",
      "mime_type": "image/webp"
    }
  ]
}
```
* **Resposta (`200 OK`):**
```json
{
  "success": true,
  "data": {
    "upload_slots": [
      {
        "filename": "page_001.webp",
        "sha256_hash": "a1b2c3d4e5f6...",
        "upload_url": "https://storage.honbakoo.org/incoming/temp_a1b2c3...?token=...",
        "already_exists": false
      }
    ]
  }
}
```

---

## 4. Políticas de Rate Limiting e Cache

* **Rotas Públicas de Leitura (`GET /mangas`, `/chapters`):** 120 req/min por IP.
* **Rotas de Criação de Comentários (`POST /comments`):** 5 comentários/min por usuário.
* **Rotas de Autenticação (`/auth/login`):** 5 tentativas/min por IP com bloqueio exponencial contra força bruta.
* **Cache de Borda:** Respostas `GET` utilizam `ETag` + `Cache-Control`. Se os dados não mudaram, o servidor retorna `304 Not Modified`, poupando 100% do tráfego do banco de dados.

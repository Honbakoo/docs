# ADR-0001 — Mídia content-addressed, CDN imutável e manifesto assinado

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `ARCHITECTURE.md` §7.2 e §8.1; `API_SPECIFICATION.md` §3.2; `DATABASE_SCHEMA.md` §9

## Contexto

Banda é o maior custo de uma plataforma de leitura. O projeto precisa servir milhares de imagens por capítulo, sobreviver a picos e ainda usar Cloudflare R2 (zero egress) sem transformar cada leitor em um cache miss.

## Como o mercado faz

- **MangaDex / Batoto:** CDN na frente, imagens em storage de objetos, cache agressivo e regras de hotlink.
- **Webtoon / Tapas:** URLs assinadas por sessão/usuário, fatiamento de imagem e, em alguns casos, DRM.
- **Agregadores:** proxy de imagem, ofuscação de URL e bloqueio por `Referer`.

## O que copiamos

- Imagens **content-addressed** (`/media/{sha256}.webp`, com sharding por prefixo).
- `Cache-Control: public, max-age=31536000, immutable` + `ETag`.
- CDN na borda e storage de objetos com zero egress (R2/B2).
- `Referer` allowlist, `Cross-Origin-Resource-Policy` e WAF como fricção contra hotlink.

## O que não copiamos

- **Token por imagem/usuário:** destrói a cache key da CDN e transforma cada leitura em um miss.
- **Fatiamento de imagem/DRM:** custo de UX, acessibilidade e infraestrutura; não é requisito do MVP.
- **URL opaca gerada por sessão:** dificulta cache, debug e compartilhamento legítimo.

## Decisão

1. A imagem é pública e imutável; o hash SHA-256 funciona como capability.
2. A autorização fica no **manifesto** (`GET /chapters/:id/pages`), que é `private, no-store`.
3. Quando houver VIP/early access, o manifesto devolve URLs assinadas de curta duração; a imagem continua cacheável.
4. **Resiliência Multi-Storage e Mirrors (Anti-ToS/Deplatforming):** A URL base da mídia não fica engessada em um único provedor de S3. O manifesto pode entregar URLs primárias e mirrors alternativos (ex: R2 primário + Backblaze B2 secundário ou VPS MinIO). Se um provedor bloquear o bucket ou suspender a conta, o frontend comuta o mirror automaticamente sem quebrar as leituras.
5. DMCA usa `blocked_media_hashes` para impedir reingestão; a remoção é soft-delete.

## Consequências

- **Positivas:** hit ratio alto de CDN, custo de banda próximo de zero, leitura rápida e cacheável no dispositivo.
- **Negativas:** uma URL vazada é acessível enquanto o hash existir; não há revogação por usuário na imagem. A mitigação é o manifesto + DMCA + rotação de conteúdo, não token por imagem.
- **Operacionais:** o purge de CDN é por hash; o GC de `media_objects` precisa respeitar `ref_count`.

## Gatilho de revisão

- Contrato de licenciamento exigir DRM/watermark por usuário.
- Abuso de hotlink que o `Referer`/WAF não contiver.
- Necessidade de revogação imediata por usuário (ex.: vazamento de capítulo VIP).

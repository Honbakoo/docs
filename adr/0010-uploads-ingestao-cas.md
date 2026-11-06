# ADR-0010 — Uploads presigned/diretos, validação server-side e CAS

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `ARCHITECTURE.md` §5 e §8.4; `API_SPECIFICATION.md` §3.4; `DATABASE_SCHEMA.md` §9

## Contexto

O upload de capítulos é a operação mais pesada e mais exposta. No `budget` não existe S3 para presigned URL; no `scale` o upload não pode passar pela API. O cliente pode mentir sobre MIME, hash e dimensões.

## Como o mercado faz

- **S3/R2:** presigned PUT, multipart, lifecycle e object lock.
- **Plataformas de imagem:** validação de magic bytes, strip de EXIF, geração de variantes e CDN.
- **Agregadores:** scrapers externos, proxies e ingestão por API key.
- **Sistemas ruins:** confiam no `Content-Type` e no hash do cliente.

## O que copiamos

- Presigned URL no `scale`; PUT direto na API no `budget` (mesmo contrato).
- Validação de **magic bytes**, SHA-256 recalculado no servidor, dimensões e EXIF.
- Deduplicação CAS por SHA-256, `ref_count` e GC de órfãos.
- `blocked_media_hashes` para DMCA.
- `X-API-Key` para ingestão machine-to-machine.
- Compressão client-side para WebP como otimização, nunca como confiança.

## O que não copiamos

- Confiar no MIME/hash declarado pelo cliente.
- Processar `libvips` de forma síncrona na API.
- Bucket público com escrita aberta.
- Scraper sem proveniência/auditoria.

## Decisão

1. `POST /uploads/presigned-url` cria `upload_sessions` com expiração e expected hash.
2. `POST /uploads/complete` valida o objeto, recalcula SHA-256, cria `media_objects` com `status='pending'` e `ref_count=0`; só vira `ready` após validação.
3. `media_objects` tem `storage_provider`, `storage_key`, `byte_size`, `width/height`, `ref_count`, `variants` e `status`.
4. `chapter_pages` referencia `media_objects`; o `ref_count` é mantido na mesma transação.
5. GC remove `status='pending'` expirado e `ref_count=0` após carência.
6. Ingestão externa usa API key com escopo e registra `audit_log`.

## Consequências

- **Positivas:** upload escala sem passar pela API, deduplicação economiza disco, validação impede conteúdo malicioso.
- **Negativas:** fluxo de duas etapas; órfãos se o cliente não chamar `complete`; custo de recalcular hash.
- **Operacionais:** job de GC, lifecycle no bucket, monitorar falhas de `complete`.

## Gatilho de revisão

- Necessidade de antivírus/scanner.
- Vídeos grandes com multipart.
- Transcoder dedicado.

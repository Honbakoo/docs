# ADR-0006 — PostgreSQL + `sqlc`/`pgx`; busca sem Elasticsearch

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `DATABASE_SCHEMA.md` §1, §3 e §4; `ARCHITECTURE.md` §2.2 e §4

## Contexto

O catálogo precisa de busca por título, tags booleanas, filtros por formato/idioma e ordenações por popularidade/nota. O orçamento não comporta um cluster de busca dedicado no MVP.

## Como o mercado faz

- **MangaDex / fóruns:** PostgreSQL com trigram/FTS e cache.
- **Grandes plataformas:** Elasticsearch/OpenSearch como índice derivado.
- **Stacks Rails/Django:** ORM + buscas em SQL, às vezes com `pg_search`.

## O que copiamos

- PostgreSQL 16+ como fonte de verdade.
- `sqlc` + `pgx` para queries tipadas, sem ORM e sem reflection em runtime.
- `tsvector` + `pg_trgm` + `unaccent`; `pg_bigm` opcional para CJK.
- GIN em `tag_ids` para inclusão booleana de tags.
- Índices keyset para cada ordenação pública.

## O que não copiamos

- ORM pesado (GORM/Ent/Prisma) no caminho quente.
- Elasticsearch/OpenSearch no MVP.
- MongoDB para catálogo relacional.
- `uuid-ossp` (UUIDv7 é gerado na aplicação).

## Decisão

1. Postgres é a única fonte de verdade transacional.
2. `mangas.search_vector` é mantido por trigger; `original_title` peso A, `alt_titles` peso B.
3. Busca usa `websearch_to_tsquery` + trigram para tolerância a erro/acento.
4. Filtros de exclusão (`NOT @>`) são pós-filtro; exigir `EXPLAIN (ANALYZE, BUFFERS)` antes de prometer latência.
5. Índice externo, se necessário, será **read model derivado** — nunca fonte de verdade.

## Consequências

- **Positivas:** uma dependência a menos, consistência transacional, queries auditáveis.
- **Negativas:** relevância e busca semântica limitadas; queries complexas exigem tuning manual.
- **Operacionais:** monitorar latência de busca e tamanho dos índices GIN.

## Gatilho de revisão

- Busca com p95 > 200ms sob carga real.
- Necessidade de relevância semântica/embeddings.
- Catálogo com dezenas de milhões de linhas e filtros combinados pesados.

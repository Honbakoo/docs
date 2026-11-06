# ADR-0002 — Paginação keyset com cursor opaco

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `API_SPECIFICATION.md` §1 e §3.1; `DATABASE_SCHEMA.md` §7 e §4.2

## Contexto

O catálogo tem milhares de obras e vários modos de ordenação (`trending`, `popular`, `latest`, `rating`). `LIMIT/OFFSET` degrada com o tempo, duplica ou pula registros quando o catálogo muda entre páginas.

## Como o mercado faz

- **GitHub / Stripe:** cursores opacos, keyset e limites máximos.
- **Fóruns e CRMs antigos:** `page`/`offset`, com contagem total.
- **Alguns frontends:** cursor montado no cliente a partir do último ID.

## O que copiamos

- Cursor **opaco** (base64url) com a tupla `(sort_key, id)`.
- Fingerprint do `sort` para rejeitar cursor reutilizado com outra ordenação.
- Índices compostos por modo de ordenação, com `id` como desempate.
- `limit` máximo e ausência de `OFFSET`.

## O que não copiamos

- `page`/`offset` como contrato público.
- Cursor construído pelo cliente.
- Contagem total exata em toda listagem (custosa e instável).

## Decisão

1. Toda listagem paginada usa keyset.
2. O cursor é base64url de `{sort, key, id}`; o cliente nunca o interpreta.
3. Reutilizar cursor com outro `sort` retorna `CURSOR_SORT_MISMATCH` (400).
4. `meta.next_cursor` é nulo quando não há próxima página; `has_more` é explícito.
5. Contagem aproximada, se necessária, vem de tabela de estatísticas — nunca de `COUNT(*)` na rota quente.

## Consequências

- **Positivas:** páginas estáveis sob escrita concorrente, custo O(1) por página, índices previsíveis.
- **Negativas:** não é possível "pular para a página 10"; a UI precisa de scroll infinito ou "carregar mais".
- **Operacionais:** cada `sort` novo exige índice compatível; revisar `EXPLAIN (ANALYZE, BUFFERS)`.

## Gatilho de revisão

- Requisito de navegação por número de página.
- Necessidade de contagem total exata em tempo real.

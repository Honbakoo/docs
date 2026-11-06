# ADR-0009 — Comentários com `ltree` + `parent_id`, REST e cache curto

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `DATABASE_SCHEMA.md` §11; `API_SPECIFICATION.md` §3.3

## Contexto

Comentários precisam de respostas aninhadas, moderação, contagem de reações e cache de borda. WebSocket foi descartado por custo e fragilidade sob CDN. `ltree` com label UUID cru falha porque hífen não é válido em label.

## Como o mercado faz

- **Reddit / Hacker News:** árvore aninhada com profundidade e colapso.
- **Disqus:** comentários flat com respostas de um nível.
- **Apps de chat:** WebSocket e presença em tempo real.
- **Fóruns:** paginação por página e contagem total.

## O que copiamos

- `parent_id` explícito + `path` `ltree` para consultas de subárvore.
- `depth` com limite máximo (5) para evitar árvores degeneradas.
- REST + cache curto (`30s` + `stale-while-revalidate`), mutações otimistas no frontend.
- Reações like/dislike com contadores denormalizados.
- Soft-delete/tombstone e fila de denúncias.

## O que não copiamos

- WebSocket para comentários ao vivo.
- Aninhamento infinito.
- Paginação por offset na árvore.
- Moderação apenas no cliente.

## Decisão

1. `comments.path` é `replace(id::text, '-', '_')::ltree`; `UNIQUE(path::text)`.
2. `parent_id` é a fonte de verdade da resposta; `depth` é derivado e limitado a 5.
3. Leitura pública com cache de 30s; invalidação por TTL curto, não por purge caro.
4. `is_deleted` mantém o tombstone para não quebrar a árvore.
5. Denúncias entram em `content_reports`; moderador resolve com auditoria.
6. Contadores de reação são mantidos por trigger na mesma transação.

## Consequências

- **Positivas:** consulta de subárvore eficiente, cache de borda, sem conexões persistentes.
- **Negativas:** comentário novo pode levar até 30s para aparecer em outro dispositivo; `ltree` exige sanitização cuidadosa.
- **Operacionais:** monitorar profundidade e volume de denúncias; limpar soft-deletes antigos conforme política.

## Gatilho de revisão

- Requisito real de tempo real (avaliar SSE).
- Profundidade maior que 5 ou necessidade de menções/notificações.

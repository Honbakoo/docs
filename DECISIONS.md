# 🧭 Honbakoo Architecture Decisions (ADR Index)

> **Status:** vivo. Toda decisão arquitetural relevante entra aqui antes de virar código.
> **Data de criação:** 2026-11-06

---

## 1. Como este projeto decide

O Honbakoo não copia arquitetura de mercado por imitação. Cada decisão nasce de três perguntas:

1. **Como o mercado resolve este problema?**
2. **O que devemos copiar?**
3. **O que não devemos copiar — e por quê?**

A resposta vira um **ADR** (Architecture Decision Record). O valor está menos na lista de práticas e mais no registro explícito das rejeições: é o que preserva a vantagem de custo e simplicidade do projeto.

### Critérios de avaliação

| Critério | Pergunta |
| :--- | :--- |
| Problema real | Qual dor concreta a prática resolve? |
| Custo | Quanto consome de RAM, CPU, ops e dinheiro? |
| Modo de falha | O que acontece quando quebra? |
| Fit | Funciona no `budget`? E no `scale`? |
| Reversibilidade | Quão caro é desfazer depois? |

### Status possíveis

- **Aceito** — vale para o MVP.
- **Aceito com gatilho** — só entra quando o gatilho descrito for atingido.
- **Rejeitado** — não entra; o motivo fica registrado.
- **Substituído** — referencia o ADR que o substituiu.

---

## 2. Índice de ADRs

| ADR | Decisão | Status | Documentos afetados |
| :--- | :--- | :--- | :--- |
| [0001](./adr/0001-midia-content-addressed-cdn.md) | Mídia content-addressed, CDN imutável e manifesto assinado | Aceito | Arquitetura, API, Schema |
| [0002](./adr/0002-paginacao-keyset-cursor-opaco.md) | Paginação keyset com cursor opaco | Aceito | API, Schema |
| [0003](./adr/0003-perfil-dual-budget-scale.md) | Perfil dual `budget`/`scale` e dependências opcionais | Aceito | Arquitetura, API |
| [0004](./adr/0004-monolito-modular-deployable-por-papel.md) | Monolito modular e um deployable por papel | Aceito | Arquitetura |
| [0005](./adr/0005-rest-openapi-erros-idempotencia.md) | REST stateless, OpenAPI 3.1, erros e idempotência | Aceito | API |
| [0006](./adr/0006-postgres-sqlc-busca.md) | PostgreSQL + `sqlc`/`pgx`; busca sem Elasticsearch | Aceito | Schema, Arquitetura |
| [0007](./adr/0007-cache-fila-rate-limit.md) | Cache, fila e rate limit: in-process vs Redis/Asynq | Aceito | Arquitetura, API |
| [0008](./adr/0008-auth-jwt-argon2-vip.md) | Auth com JWT rotativo, Argon2id e VIP como entitlement | Aceito | API, Schema |
| [0009](./adr/0009-comentarios-ltree-rest.md) | Comentários com `ltree` + `parent_id`, REST e cache curto | Aceito | Schema, API |
| [0010](./adr/0010-uploads-ingestao-cas.md) | Uploads presigned/diretos, validação server-side e CAS | Aceito | API, Schema, Arquitetura |
| [0011](./adr/0011-operacao-observabilidade-backup-ci.md) | Observabilidade, backup/restore, CI/CD e supply chain | Aceito | Arquitetura, API |
| [0012](./adr/0012-modelo-negocio-vip-sem-ads-drm.md) | VIP/doações, sem ads/DRM como core; scrapers com cautela | Aceito | Arquitetura, README |
| [0013](./adr/0013-escala-futura-watchlist.md) | Escala futura: PWA, multi-region, feature flags e partições | Aceito com gatilho | Arquitetura |
| [0014](./adr/0014-api-keys-automacao.md) | API keys com hash, escopo, expiração e revogação | Aceito | Schema, API, Arquitetura |
| [0015](./adr/0015-retencao-lgpd-ciclo-de-vida.md) | Retenção, LGPD, DMCA e ciclo de vida de dados | Aceito | Schema, API, Arquitetura |

---

## 3. Matriz de mercado: copiar ou não copiar

| Prática de mercado | Quem usa | Decisão | ADR |
| :--- | :--- | :--- | :--- |
| CDN + cache imutável | MangaDex, Webtoon, Batoto | **Copiar** | 0001 |
| URL assinada por imagem/usuário | Webtoon, Tapas | **Não copiar** | 0001 |
| Image slicing / DRM de imagem | Webtoon | **Não copiar no MVP** | 0001, 0012 |
| REST + OpenAPI | MangaDex, Stripe | **Copiar** | 0005 |
| Cursor pagination | GitHub, Stripe | **Copiar** | 0002 |
| Offset pagination | fóruns legados | **Não copiar** | 0002 |
| GraphQL | GitHub | **Não copiar** | 0005 |
| WebSocket para comentários | apps de chat | **Não copiar** | 0005, 0009 |
| Microservices | plataformas grandes | **Não copiar** | 0004 |
| Monolito modular | Shopify, Basecamp | **Copiar** | 0004 |
| Redis obrigatório | maioria | **Não no budget; sim no scale** | 0003, 0007 |
| Kafka | grandes | **Não copiar** | 0007 |
| Asynq / fila de jobs | SaaS | **Copiar no scale** | 0007 |
| Postgres FTS + trigram | MangaDex, fóruns | **Copiar** | 0006 |
| Elasticsearch | grandes | **Não no MVP** | 0006 |
| ORM | Rails/Django | **Não copiar** | 0006 |
| JWT + refresh rotation | Auth0, Stripe | **Copiar** | 0008 |
| Argon2id | OWASP | **Copiar** | 0008 |
| VIP como role | alguns fóruns | **Não copiar** | 0008 |
| Rate limit headers | GitHub, Stripe | **Copiar** | 0005, 0007 |
| `Idempotency-Key` | Stripe | **Copiar** | 0005 |
| Webhooks assinados | Stripe | **Copiar** | 0005, 0011 |
| DRM | Webtoon, Netflix | **Não copiar** | 0012 |
| Ads | Batoto, agregadores | **Não como core** | 0012 |
| VIP/doações | MangaDex, Patreon | **Copiar** | 0012 |
| Scrapers | agregadores | **Com cautela** | 0010, 0012 |
| API key global sem escopo | sistemas ruins | **Não copiar** | 0014 |
| API key com hash/escopo/revogação | Stripe, GitHub | **Copiar** | 0014 |
| Retenção por classe + LGPD | SaaS maduro | **Copiar** | 0015 |
| PWA/offline | Webtoon | **P2 / gatilho** | 0013 |
| Multi-region | grandes | **P2 / gatilho** | 0013 |
| Feature flags | SaaS | **P2 / gatilho** | 0013 |
| Observabilidade + backup | todos | **Copiar (P1)** | 0011 |

---

## 4. Mapa P1/P2

| Prioridade | Itens | ADRs |
| :--- | :--- | :--- |
| **P1 — antes do MVP** | OpenAPI executável, erros/idempotência, observabilidade, backup/restore, CI/CD, testes de integração, segurança de upload, API keys, retenção/LGPD, runbooks | 0005, 0011, 0010, 0014, 0015 |
| **P2 — depois do MVP** | Busca/ranking, feed/notificações, moderação madura, billing maduro, analytics, i18n/acessibilidade, performance de escala, operação avançada, ingest, PWA/offline | 0006, 0009, 0012, 0013 |

---

## 5. Como adicionar um ADR

1. Copie o template de qualquer ADR existente.
2. Numere em sequência (`000N-titulo-curto.md`).
3. Preencha **Como o mercado faz**, **O que copiamos** e **O que não copiamos**.
4. Registre as consequências negativas e o **gatilho de revisão**.
5. Adicione a linha no índice e, se necessário, linke em `ARCHITECTURE.md`.

> Regra: se a decisão não tem um "não copiamos" explícito, ela ainda não foi realmente discutida.

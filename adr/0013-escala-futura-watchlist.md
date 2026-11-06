# ADR-0013 — Escala futura: PWA, multi-region, feature flags e partições

- **Status:** Aceito com gatilho
- **Data:** 2026-11-06
- **Relacionado:** `ARCHITECTURE.md` §10

## Contexto

Existem práticas de mercado que são boas, mas caras ou prematuras para o MVP. O objetivo é registrá-las sem implementá-las agora, com um gatilho objetivo de revisão.

## Como o mercado faz

- **Webtoon:** PWA/app, offline, notificações push.
- **Grandes plataformas:** multi-region, read replicas, sharding, feature flags e canary.
- **SaaS:** feature flags e experimentos desde cedo.

## O que copiamos (quando o gatilho chegar)

- PWA com leitura offline e cache de capítulos.
- Read replicas para leitura de catálogo.
- Particionamento de tabelas grandes (`comments`, `reading_history`, `manga_view_daily`).
- Feature flags para liberar recursos sem deploy.
- CDN rules por rota e cache warming.
- Multi-region só depois de SLO, DR e custo previsível.

## O que não copiamos agora

- Multi-region no MVP.
- Sharding prematuro.
- Micro-frontends.
- Kubernetes obrigatório.
- Experimentação pesada sem base de métricas.

## Decisão

1. Nada desta lista entra no MVP.
2. Cada item tem gatilho mensurável:
   - PWA/offline: >20% de acesso mobile recorrente.
   - Read replica: p95 de leitura >300ms ou CPU do PG >70% sustentado.
   - Partição: tabela >50GB ou vacuum/latência degradando.
   - Feature flags: >2 releases/semana ou necessidade de kill switch.
   - Multi-region: SLO definido, DR testado e custo por região aprovado.
3. Revisão trimestral no roadmap.

## Consequências

- **Positivas:** evita overengineering e mantém o budget viável.
- **Negativas:** algumas melhorias de UX (offline) demoram.
- **Operacionais:** os gatilhos precisam ser medidos; sem métricas, a lista vira estagnação.

## Gatilho de revisão

- Qualquer item acima atingir seu gatilho.
- Mudança de modelo de negócio que exija offline/DRM.

# 📖 Honbakoo Documentation

Bem-vindo à documentação oficial do ecossistema **Honbakoo**.

O **Honbakoo** é uma engine de backend modular, headless e de altíssima performance para plataformas de mangá, doujinshi, manhwa e anime/h-anime, projetada para máxima eficiência operacional, custo mínimo de infraestrutura e zero atrito de instalação.

---

## 📚 Documentos Disponíveis

* 🏛️ **[Arquitetura do Sistema (ARCHITECTURE.md)](./ARCHITECTURE.md)**:
  * Princípios de design e decisão técnica (Go, sem ORM com `sqlc`).
  * Estrutura de Auth, VIP/Assinaturas e Comunidade (Comentários).
  * Pipeline de processamento de mídia e imagens com `libvips`.
  * Simulação de ingestão de usuários e benchmarks com `k6`.
  * Estrutura de pastas do projeto.
* 🗄️ **[Modelagem e Schema do Banco de Dados (DATABASE_SCHEMA.md)](./DATABASE_SCHEMA.md)**:
  * Diagrama de Entidade-Relacionamento (ERD completo).
  * Migração Goose DDL completa com PostgreSQL 16+.
  * Índices GIN para busca booleana de tags (`+tag1 -tag2`).
  * Árvores de comentários hierárquicos com `ltree`.
  * Deduplicação de storage (CAS) com SHA-256 e Blacklist DMCA.
* 🔌 **[Especificação da API RESTful Headless (API_SPECIFICATION.md)](./API_SPECIFICATION.md)**:
  * Contrato de rotas REST v1 stateless (sem WebSockets).
  * Paginação keyset com cursor opaco para alta escala.
  * Endpoints para Leitor de Mangá/Webtoon e Player de Vídeo/Anime.
  * Uploads presigned (scale) ou diretos na API (budget), com deduplicação por hash.
  * Auth completo (verificação de e-mail, refresh rotativo, reset), ratings e denúncias.
  * Políticas de cache de borda (CDN), rate limiting e modelo de erro.
* 🧭 **[Decisões de Arquitetura (DECISIONS.md)](./DECISIONS.md)**:
  * Índice de ADRs em [`adr/`](./adr/).
  * Matriz "copiar / não copiar" de práticas de mercado.
  * Critérios de decisão e gatilhos de revisão.
* 🔐 **[Modelo de Segurança (SECURITY.md)](./SECURITY.md)**:
  * Modelo de ameaça, autenticação, autorização e API keys.
  * Segurança de upload, borda/HTTP, rate limiting e segredos.
  * Checklist de release e resposta a incidentes.
* 🛠️ **[Operação (OPERATIONS.md)](./OPERATIONS.md)**:
  * Topologia budget/scale, configuração e migrations.
  * Métricas, SLOs, backup/restore e runbooks.
  * Deploy, rollback, capacidade e custo.
* 🚨 **[Runbooks Operacionais (RUNBOOKS.md)](./RUNBOOKS.md)**:
  * Procedimentos passo a passo para resolução de incidentes.
  * Esgotamento de disco, database locks e falha de Redis.
  * Takedowns DMCA em < 5 minutos e rotação emergencial de segredos.
* 📄 **[Contrato Executável OpenAPI 3.1 (api/openapi.yaml)](./api/openapi.yaml)**:
  * Especificação formal lintada pronta para geração de clientes SDK (TypeScript, Dart/Flutter, Python).
* 🧪 **[Estratégia de Testes (TESTING.md)](./TESTING.md)**:
  * Unit, integração com Testcontainers, contrato, E2E e k6.
  * Gates de CI e definition of done.
* 🗺️ **[Roadmap (ROADMAP.md)](./ROADMAP.md)**:
  * P0 concluído, P1 com critérios de aceite e P2 com gatilhos.
* 🧾 **[Retenção e LGPD (ADR-0015)](./adr/0015-retencao-lgpd-ciclo-de-vida.md)**:
  * Classes de dado, prazos, anonimização, DMCA e backup.

---

## 🧭 Como o projeto decide

Toda decisão arquitetural nasce de três perguntas:

1. **Como o mercado resolve este problema?**
2. **O que devemos copiar?**
3. **O que não devemos copiar — e por quê?**

A resposta vira um ADR. O objetivo não é copiar a arquitetura de quem tem outro modelo de negócio, e sim montar a arquitetura **melhor para as restrições do Honbakoo**: custo baixo, operação simples e leitura rápida.

> Regra: se uma decisão não tem um "não copiamos" explícito, ela ainda não foi realmente discutida.

### Status e próximos passos

- **P0 — corrigido nos docs:** mídia/CDN, cursor, `ltree`, constraints, rating, histórico, VIP e Redis opcional.
- **P1 — antes do MVP:** OpenAPI executável, erros/idempotência, observabilidade, backup/restore, CI/CD, testes de integração, segurança de upload, API keys, retenção/LGPD e runbooks.
- **P2 — depois do MVP:** busca/ranking, feed/notificações, moderação madura, billing maduro, analytics, i18n/acessibilidade, performance de escala, operação avançada, ingest e PWA/offline.

---

## 🚀 Como Executar Localmente (Visão Rápida)

> **Status:** este repositório contém **apenas a documentação** (arquitetura, schema e contrato da API). A engine, o `docker-compose.yml`, as migrations e os testes vivem no repositório da engine. Os comandos abaixo descrevem a UX alvo do projeto e não funcionam a partir deste repositório.

No repositório da engine, o objetivo é **zero atrito**:

```bash
# Clonar o repositório da engine (quando publicado)
git clone <url-do-repositorio-da-engine> honbakoo
cd honbakoo

# Subir toda a infraestrutura com 1 comando
docker compose up -d
```

Enquanto a engine não é publicada, use estes documentos como contrato de implementação.

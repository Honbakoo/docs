# 📖 Honbakoo Documentation

Bem-vindo à documentação oficial do ecossistema **Honbakoo**.

O **Honbakoo** é uma engine de backend modular, headless e de altíssima performance para plataformas de mangá, doujinshi, manhwa e anime/h-anime, projetada para máxima eficiência operacional, custo mínimo de infraestrutura e zero atrito de instalação.

---

## 📚 Documentos Disponíveis

* 🏛️ **[Arquitetura do Sistema (ARCHITECTURE.md)](./ARCHITECTURE.md)**:
  * Princípios de design e decisão técnica (Go, sem ORM com `sqlc`).
  * Estrutura de Auth, VIP/Assinaturas e Comunidade (Comentários).
  * Pipeline de mídia content-addressed, CDN imutável, variantes em Go puro e entrega protegida para conteúdo gated.
  * Simulação de ingestão de usuários e benchmarks com `k6`.
  * Estrutura de pastas do projeto.
* 🗄️ **[Modelagem e Schema do Banco de Dados (DATABASE_SCHEMA.md)](./DATABASE_SCHEMA.md)**:
  * Diagrama de Entidade-Relacionamento (ERD completo).
  * Migração Goose DDL completa com PostgreSQL 16+.
  * Índices GIN para busca booleana de tags (`+tag1 -tag2`).
  * Árvores de comentários hierárquicos com `ltree`.
  * Deduplicação de storage (CAS) com SHA-256 e Blacklist DMCA.
* 🔌 **[Especificação da API RESTful Headless (API_SPECIFICATION.md)](./API_SPECIFICATION.md)**:
  * Contrato de rotas REST v1 stateless (sem WebSockets), validado contra o router real.
  * Paginação keyset com cursor opaco para alta escala.
  * Catálogo com busca, filtros, tags, updates, favoritos e histórico.
  * Reader de imagem + download CBZ; áudio/vídeo ainda não tem fluxo editorial.
  * Auth completo (verificação de e-mail, refresh rotativo, reset), API keys, ratings e denúncias.
  * Rate limiting em memória por processo e modelo de erro `{error}`.
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
  * Esgotamento de disco, database locks e backlog da fila durável.
  * Takedowns DMCA em < 5 minutos e rotação emergencial de segredos.
* 🛡️ **[Governança de Conteúdo, Moderação e Suporte (CONTENT_GOVERNANCE_AND_SUPPORT.md)](./CONTENT_GOVERNANCE_AND_SUPPORT.md)**:
  * Máquina de estados de publicação (`draft`, `pending_review`, `published`, `rejected`).
  * Governança de tags com propostas e aliases contra duplicidades.
  * Tombstone pattern para moderação de comentários preservando árvores de respostas.
  * Sistema de denúncias e tickets de suporte com roteamento direto para scanlators.
  * Auditoria de sanções (warn, mute temporário e ban).
* 🔌 **[Pipeline de Ingestão e Conectores (INGESTION_PIPELINE.md)](./INGESTION_PIPELINE.md)**:
  * Arquitetura de scrapers desacoplados em sandbox (Wasm/Python).
  * Fila com retentativas exponenciais e Dead Letter Queue (DLQ).
  * Sanitização rigorosa, mitigação anti-bot e deduplicação on-the-fly.
* 📈 **[Escala Futura, Particionamento e DR (SCALING_AND_DR.md)](./SCALING_AND_DR.md)**:
  * Particionamento declarativo no PostgreSQL para histórico e logs.
  * Multiplexação de conexões com PgBouncer (5.000 conexões para 50 no banco).
  * Plano de Disaster Recovery para restaurar o ecossistema em < 15 minutos.
* 📄 **[Contrato Executável OpenAPI 3.1 (api/openapi.yaml)](./api/openapi.yaml)**:
  * Especificação 3.1 que cobre todas as rotas reais, pronta para gerar clientes SDK (TypeScript, Dart/Flutter, Python).
* 🧪 **[Estratégia de Testes (TESTING.md)](./TESTING.md)**:
  * Unit, integração com PostgreSQL real, contrato OpenAPI e segurança.
  * Gates reais da CI (fmt, vet, build, sqlc diff, migrations up/down, race, govulncheck, Trivy, SBOM).
  * E2E, k6 e Testcontainers ainda planejados.
* 🗺️ **[Roadmap (ROADMAP.md)](./ROADMAP.md)**:
  * P0 e P1 implementados (com ressalvas de operação/E2E), incluindo views por evento durável, e P2 com gatilhos.
* 🧾 **[Retenção e LGPD (ADR-0015)](./adr/0015-retencao-lgpd-ciclo-de-vida.md)**:
  * Classes de dado, prazos, anonimização, DMCA e backup.
* 💎 **[Modelo de Monetização VIP e Early Access (ADR-0016)](./adr/0016-modelo-vip-monetizacao-hentai-manga.md)**:
  * Acesso antecipado temporal (Early Access) vs exclusividade permanente (Paywall seletivo/Uncensored).
  * Vantagens QoL para apoiadores: download de capítulos em `.cbz` em 1 clique e resolução original lossless.
* ⚙️ **[Especificação de Configuração Self-Hosted (CONFIGURATION.md)](./CONFIGURATION.md)**:
  * Defaults embutidos + `.env`/variáveis reais (`HONBAKOO__SECTION__KEY`), com validação fail-closed.
  * Matriz completa: servidor, banco, auth, conteúdo, storage S3, billing, SMTP e observabilidade.
  * `system_settings` existe no schema, mas ainda sem hot-reload/endpoint (Camada 3 reservada).
  * Endpoint público de configuração do frontend (`GET /api/v1/config`).

---

## 🧭 Como o projeto decide

Toda decisão arquitetural nasce de três perguntas:

1. **Como o mercado resolve este problema?**
2. **O que devemos copiar?**
3. **O que não devemos copiar — e por quê?**

A resposta vira um ADR. O objetivo não é copiar a arquitetura de quem tem outro modelo de negócio, e sim montar a arquitetura **melhor para as restrições do Honbakoo**: custo baixo, operação simples e leitura rápida.

> Regra: se uma decisão não tem um "não copiamos" explícito, ela ainda não foi realmente discutida.

### Status e próximos passos

- **P0 — implementado:** mídia/CAS com entrega CDN ou endpoint protegido, cursor keyset, `ltree`, constraints, rating, histórico, VIP, API keys, LGPD, fila durável no PostgreSQL, contagem de views por eventos com rollup em lote e throttle de login durável.
- **P1 — implementado (com ressalvas):** OpenAPI executável, erros/idempotência, observabilidade com métricas de views/GC/variantes, backup/restore com manifesto e verificação, CI/CD, segurança de upload, API keys, LGPD e runbooks. Testcontainers/E2E, agendamento do dump e o restore mensal ainda são pendências operacionais.
- **Núcleo de produto:** busca, tags, updates, favoritos, histórico, admin real, reordenação/import de páginas, S3 e SMTP.
- **P2 — depois do MVP:** busca/ranking, feed/notificações, moderação madura, billing maduro, analytics, i18n/acessibilidade, performance de escala, ingest e PWA/offline.

---

## 🚀 Como Executar Localmente

Este repositório contém a documentação. A engine vive no repositório irmão `engine/` (module `github.com/Honbakoo/engine`). Localmente:

```bash
cd engine

# 1. Configuração
cp .env.example .env
# edite DATABASE__URL e gere segredos com: openssl rand -base64 32

# 2. PostgreSQL 16
podman-compose up -d postgres
# ou: docker compose up -d postgres

# 3. Migrations + API
go build -o bin/honbakoo ./cmd/honbakoo
HONBAKOO__ENV=development ./bin/honbakoo --role=migrate
HONBAKOO__ENV=development ./bin/honbakoo --role=all

# 4. Verificação
curl http://localhost:8080/healthz
curl http://localhost:8080/readyz
go test -race -count=1 ./...
```

Para stack completa (API + banco) use `docker compose up -d --build`. Em produção, defina `HONBAKOO__ENV=production`, `PUBLIC_URL` com HTTPS e segredos fortes; a API se recusa a subir com os placeholders de desenvolvimento.

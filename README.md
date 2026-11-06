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
  * Diagrama de Entidade-Relacionamento (ERD).
  * Migração Goose DDL completa com PostgreSQL 16+.
  * Índices GIN para busca booleana de tags (`+tag1 -tag2`).
  * Árvores de comentários hierárquicos com `ltree`.
  * Deduplicação de storage (CAS) com SHA-256 e Blacklist DMCA.

---

## 🚀 Como Executar Localmente (Visão Rápida)

O projeto é planejado para rodar com **zero atrito**:

```bash
# Clonar o repositório
git clone https://github.com/Honbakoo/docs.git honbakoo
cd honbakoo

# Subir toda a infraestrutura com 1 comando
docker compose up -d
```

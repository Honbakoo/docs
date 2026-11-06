# ADR-0004 — Monolito modular e um deployable por papel

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `ARCHITECTURE.md` §1, §2.2 e §10

## Contexto

O projeto precisa ser simples de operar (uma pessoa, um VPS) sem virar um monólito acoplado que impeça escalar o worker de mídia separadamente. O termo "single-binary" era impreciso: `libvips` exige CGO e uma biblioteca nativa.

## Como o mercado faz

- **Shopify / Basecamp:** monolito modular com fronteiras internas claras.
- **Grandes plataformas:** microservices, service mesh e deploys independentes.
- **Projetos pequenos:** um único processo com tudo, incluindo tarefas pesadas.

## O que copiamos

- **Monolito modular:** um repositório, um banco, módulos internos com fronteiras explícitas.
- **Um deployable por papel:** `cmd/api` (estático, `CGO_ENABLED=0`) e `cmd/worker` (CGO + `libvips`).
- **Comunicação in-process** entre módulos; sem hop de rede no caminho quente.

## O que não copiamos

- Microservices e service mesh no MVP.
- Kubernetes como requisito de instalação.
- Um único binário com `libvips` embutido na API.

## Decisão

1. `cmd/api`: HTTP REST, sem CGO, imagem enxuta.
2. `cmd/worker`: processamento de imagem/vídeo, fila, flush de views e jobs; imagem com `libvips`.
3. `cmd/cli`: setup, seed e migrations.
4. `internal/` compartilha domínio, banco e contratos; nenhum módulo acessa tabela de outro sem passar pela interface do domínio.
5. Migrations embutidas no binário da API, aplicadas sob advisory lock.

## Consequências

- **Positivas:** deploy simples, dois papéis escaláveis de forma independente, sem custo de rede entre módulos.
- **Negativas:** duas imagens para construir/publicar; o worker pode ficar sem atualização se o deploy não for coordenado.
- **Operacionais:** versionar API e worker juntos; health/readiness separados.

## Gatilho de revisão

- Necessidade de deploy independente de um módulo por time.
- Um módulo precisar de stack/runtime diferente.
- Carga do worker competir com a API no mesmo host.

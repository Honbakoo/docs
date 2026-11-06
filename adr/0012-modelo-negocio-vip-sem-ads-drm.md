# ADR-0012 — VIP/doações, sem ads/DRM como core; scrapers com cautela

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `ARCHITECTURE.md` §6; `README.md`

## Contexto

O modelo de negócio condiciona a arquitetura. Ads exigem tracking e mais pageviews; DRM exige image slicing e URLs por usuário; doações/VIP exigem entitlement e webhooks. O Honbakoo quer custo baixo e UX de leitura limpa.

## Como o mercado faz

- **Batoto / agregadores:** ads, múltiplos domínios, proxy de imagem e volume.
- **Webtoon / Tapas:** app, moedas, early access, DRM/watermark.
- **MangaDex:** comunidade, doações, API aberta e DMCA.
- **Patreon / Ko-fi:** assinatura recorrente e conteúdo exclusivo.

## O que copiamos

- **VIP/doações** como receita principal: early access, sem ads.
- **Scanlation groups** e créditos de tradução.
- **DMCA** com soft-delete, blacklist de hash e transparência.
- **API de ingestão** autenticada para a comunidade.
- **Webhooks idempotentes** para billing.

## O que não copiamos

- **Ads como core:** tracking, terceiros e pressão por pageview não cabem no modelo.
- **DRM/watermark por usuário:** custo e UX; só com contrato de licenciamento.
- **Paywall em todo o catálogo:** mata a comunidade e o SEO.
- **Scrapers sem proveniência:** risco legal e de qualidade.

## Decisão

1. Núcleo gratuito; VIP dá early access, sem bloquear o catálogo inteiro.
2. Sem ads no core; se necessário, plugin opcional e desabilitado por padrão.
3. Sem DRM no MVP; entitlement + manifesto assinado resolvem o caso comum.
4. Scrapers só via `POST /ingest/*` com API key, `audit_log` e validação.
5. DMCA é workflow de primeira classe, não exceção.

## Consequências

- **Positivas:** UX limpa, arquitetura simples, menos dependências de terceiros.
- **Negativas:** receita depende de conversão VIP/doações; sem ads, o crescimento precisa ser orgânico.
- **Operacionais:** acompanhar churn, conversão e custo por leitor.

## Gatilho de revisão

- Contrato de licenciamento exigir DRM.
- Receita de doações/VIP não cobrir custos.
- Demanda real por ads de anunciantes locais.

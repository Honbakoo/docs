# ADR-0017 — Escopo do MVP: NSFW, vídeo e ingestão

- **Status:** Aceito
- **Data:** 2026-11-12
- **Relacionado:** `ROADMAP.md` §4–§5; `ARCHITECTURE.md` §4 e §10; `SECURITY.md`

---

## 1. Contexto

O escopo anterior tratava o MVP como um catálogo de mangá SFW com curadoria manual. O produto real precisa validar três frentes ao mesmo tempo: conteúdo adulto (NSFW), vídeo e aquisição de catálogo em escala.

Adiar essas frentes reduziria o risco de engenharia, mas criaria um MVP que não representa o produto. O custo de adicioná-las depois é maior do que projetá-las agora, porque cada uma muda contrato, moderação, custo de mídia e operação.

## 2. Decisão

O MVP inclui:

- **NSFW**, com verificação de idade em modo `strict`, moderação e páginas legais. A autodeclaração isolada não é suficiente para produção.
- **Vídeo**, com capítulo `video_stream`, fontes de playback, autorização VIP/NSFW e progresso por usuário. O pipeline pode ser HLS pré-transcodificado no R2 ou provedor externo.
- **Ingestão manual e automática**: o import editorial por URL continua e conectores por fonte entram no MVP, com retry, DLQ, idempotência e provenance.
- **Deploy em VPS** com Cloudflare para DNS/CDN/WAF e Cloudflare R2 para mídia.
- **OpenAPI validado com Redocly** no CI.
- **Frontend liberado no Marco F**, depois de contrato executável + ambiente local com seed, sem esperar a infraestrutura de produção.

## 3. Como o mercado faz

| Frente | Prática comum | O que copiamos | O que não copiamos |
| :--- | :--- | :--- | :--- |
| NSFW | idade autodeclarada, gate simples | gate explícito em catálogo, leitor, mídia e busca | autodeclaração como única prova em produção |
| Vídeo | transcodificação dedicada + CDN | HLS, poster, legendas, autorização no manifesto | DRM como requisito de MVP |
| Ingestão | scrapers sem contrato e sem observabilidade | conector com contrato, retry, DLQ e provenance | scraping sem termos/revisão legal |
| Deploy | Kubernetes + múltiplos serviços | VPS + Cloudflare + R2, um binário com papéis | complexidade operacional prematura |

## 4. Consequências

### Positivas

- O MVP valida o produto real, não uma versão diluída.
- Contrato de idade, vídeo e ingestão nasce antes do frontend, evitando retrabalho.
- O caminho de mídia protegida já existe (capability HMAC + endpoint da API), o que atende NSFW e VIP sem destruir o cache da CDN.

### Negativas

- Verificação de idade `strict` vira bloqueador: sem provedor, NSFW não vai para produção.
- Vídeo adiciona custo de storage/egress e um pipeline que não existia.
- Ingestão automática adiciona obrigações legais (termos, robots, DMCA) e operação de falhas.
- O prazo até o Marco P aumenta; o frontend continua desbloqueado no Marco F.

### Riscos e mitigação

| Risco | Mitigação |
| :--- | :--- |
| Provedor de idade caro ou ruim | escolher cedo, medir conversão e custo; manter fluxo de recurso |
| Egress de vídeo estourar | quotas, HLS, cache no R2/Cloudflare e limite por resolução |
| Fonte de ingestão instável | retry com backoff, DLQ, sandbox por fonte e kill switch |
| Conteúdo ilegal | quarentena de emergência, moderação, DMCA e trilha de auditoria |

## 5. Gatilho de revisão

Revisar se:

- o custo de verificação de idade inviabilizar a conversão;
- o egress de vídeo passar do orçamento mensal;
- uma fonte de ingestão exigir mudança de contrato;
- o escopo do MVP mudar por decisão de produto.

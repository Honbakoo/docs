# ADR-0014 — API keys para ingestão e automação

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `ARCHITECTURE.md` §5.3; `API_SPECIFICATION.md` §3.4; `DATABASE_SCHEMA.md` §5

## Contexto

Scrapers externos e a CLI Python de ingestão precisam autenticar sem senha humana e sem um JWT de curta duração. A API já citava `X-API-Key`, mas o schema não tinha onde armazenar a credencial, o escopo ou a revogação. Uma string de API key sem registro é impossível de rotacionar, auditar ou limitar.

## Como o mercado faz

- **Stripe/GitHub:** tokens com prefixo identificável, hash em repouso, escopos, expiração e revogação.
- **SaaS de ingestão:** API key por integração, com `last_used_at` e auditoria.
- **Sistemas ruins:** uma única chave global em variável de ambiente, sem escopo, sem revogação e sem rastro de quem usou.

## O que copiamos

- Token com prefixo legível (`hbk_live_...`) para identificar a chave em logs sem expor o segredo.
- Apenas SHA-256 em repouso; o valor em claro aparece uma única vez na criação.
- Escopos (`ingest`, `admin`), expiração opcional e revogação explícita.
- Vínculo com usuário responsável e, opcionalmente, com grupo de scanlation.
- `last_used_at` e `audit_log` para proveniência.

## O que não copiamos

- Chave global compartilhada por todos os scrapers.
- Token em query string (vaza em logs e proxies).
- Escopo `admin` por padrão.
- Hash reversível ou criptografia simétrica do token.

## Decisão

1. `api_keys` guarda `key_hash`, `key_prefix`, `scopes`, `user_id`, `group_id` opcional, `expires_at` e `revoked_at`.
2. O middleware `X-API-Key` calcula SHA-256, busca a chave ativa, verifica escopo e expiração, e resolve o ator para `user_id` + `api_key_id`.
3. `idempotency_keys.actor_key` usa `api_key:<uuid>`; `audit_log` registra o ator e o `request_id`.
4. Rotação = criar nova chave, migrar o cliente e revogar a antiga; não existe "editar token".
5. Chaves `admin` exigem usuário com role `admin` e nunca são criadas por auto-serviço.

## Consequências

- **Positivas:** ingestão auditável, rotação sem downtime, escopo mínimo e revogação imediata.
- **Negativas:** mais uma tabela e um fluxo de provisionamento; o operador precisa guardar o token na criação.
- **Operacionais:** monitorar `last_used_at`, alertar chaves expiradas e revisar chaves sem uso.

## Gatilho de revisão

- Necessidade de OAuth client credentials ou mTLS.
- Múltiplos escopos por grupo/organização.
- Requisito de rotação automática.

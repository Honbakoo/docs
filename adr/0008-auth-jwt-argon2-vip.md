# ADR-0008 — Auth com JWT rotativo, Argon2id e VIP como entitlement

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `DATABASE_SCHEMA.md` §4; `API_SPECIFICATION.md` §3.5

## Contexto

O projeto precisa de autenticação stateless para a API, revogação de sessão, proteção contra roubo de refresh token e um modelo VIP que não vire uma role permanente. O schema anterior tinha `vip` no enum `user_role` e `vip_subscriptions` em paralelo — duas fontes de verdade.

## Como o mercado faz

- **Auth0 / Clerk:** access token curto, refresh rotativo, detecção de reuso, e-mail verificado.
- **Stripe:** entitlement por assinatura, webhooks idempotentes.
- **Fóruns antigos:** role `vip`/`premium` no usuário, sem expiração.
- **APIs públicas:** API keys para integrações machine-to-machine.

## O que copiamos

- **Argon2id** para senhas (memória parametrizável).
- Access token JWT de curta duração + refresh token opaco, hasheado no banco.
- Rotação de refresh com `family_id`, `replaced_by` e detecção de reuso.
- Verificação de e-mail e reset de senha com tokens de uso único.
- Rate limit agressivo em login/registro/reset.
- Entitlement VIP separado da autorização.

## O que não copiamos

- `vip` como role permanente.
- JWT de longa duração sem revogação.
- Refresh token em texto puro.
- Login social/SSO no MVP (fica para gatilho).

## Decisão

1. `user_role` tem apenas `guest`, `user`, `moderator`, `admin`.
2. VIP é derivado de `users.vip_until` (cache curto) e `vip_subscriptions` (fonte de verdade).
3. Refresh tokens são opacos, com hash SHA-256, `family_id`, `revoked_at` e `replaced_by`.
4. Reuso de refresh revoga a família inteira e retorna `TOKEN_REUSED`.
5. Comentários e reações exigem e-mail verificado; leitura não exige login.
6. Logout revoga a família; `DELETE /users/me` faz soft-delete e anonimização.

## Consequências

- **Positivas:** revogação real, entitlement expira sozinho, menos risco de sequestro de sessão.
- **Negativas:** mais fluxos (verificação/reset) e dependência de e-mail; cache de entitlement pode atrasar a perda de VIP.
- **Operacionais:** limpar tokens expirados; monitorar taxa de reuso; proteger endpoints de auth contra enumeração.

## Gatilho de revisão

- Demanda por login social/SSO.
- Necessidade de MFA.
- Integração B2B com API keys de longa duração.

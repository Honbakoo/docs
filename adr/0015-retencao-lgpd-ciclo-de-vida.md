# ADR-0015 — Retenção, LGPD e ciclo de vida de dados

- **Status:** Aceito
- **Data:** 2026-11-06
- **Relacionado:** `ARCHITECTURE.md` §6; `API_SPECIFICATION.md` §3.5 e §3.7; `DATABASE_SCHEMA.md` §13

## Contexto

O sistema guarda dados pessoais (e-mail, IP, user agent, histórico de leitura), conteúdo de terceiros (mídia, capítulos) e trilhas operacionais (auditoria, webhooks, idempotência). Sem uma política explícita, o banco cresce para sempre, um pedido de exclusão LGPD vira um `DELETE` manual arriscado e um DMCA não tem ciclo de vida claro.

## Como o mercado faz

- **SaaS maduro:** retenção por classe de dado, exclusão lógica com anonimização, exportação e prazos documentados.
- **Plataformas de conteúdo:** soft-delete para DMCA, blacklist de hashes e retenção de metadados mínimos.
- **Sistemas ruins:** `DELETE` em cascata sem auditoria, logs com PII para sempre e backups sem prazo.

## O que copiamos

- Classes de dado com prazo e base legal explícitos.
- Soft-delete + anonimização para conta de usuário, preservando agregados.
- DMCA como soft-delete reversível, com blacklist de hash separada.
- Expiração automática de tokens, idempotência, webhooks e sessões de upload.
- Backup com retenção curta e restore testado.

## O que não copiamos

- Apagar histórico agregado de terceiros ao excluir uma conta.
- Guardar IP/user agent indefinidamente em logs.
- Backups imutáveis por anos sem necessidade legal.
- Excluir mídia referenciada antes de recalcular `ref_count`.

## Decisão

| Classe | Retenção | Ação |
| :--- | :--- | :--- |
| Conta ativa | enquanto ativa | — |
| Conta excluída | 30 dias de carência | anonimizar e-mail/username/avatar; manter `id` e agregados |
| Refresh tokens | até expirar/revogar | apagar após 30 dias |
| Tokens de e-mail/reset | 24h de uso ou 7 dias | apagar expirados |
| `idempotency_keys` | 24h | job de limpeza |
| `webhook_events` | 90 dias | apagar payload após processar |
| `upload_sessions` pendentes | 24h | marcar `expired`, remover objeto |
| `media_objects` órfãos | 7 dias de carência | GC após `ref_count = 0` |
| `reading_history` | enquanto conta ativa | apagar na exclusão |
| `audit_log` | 1 ano | reter para moderação/segurança |
| `content_reports` | 1 ano após resolução | anonimizar denunciante |
| Logs de aplicação | 30 dias | sem corpo, token ou e-mail completo |
| Backups | 7 diários + 4 semanais | restore testado mensalmente |

1. `DELETE /users/me` é soft-delete imediato; a anonimização roda em job e é idempotente.
2. Exportação LGPD é um job assíncrono que gera JSON com dados do usuário, sem segredos.
3. DMCA bloqueia `is_dmca_blocked` de forma síncrona e blacklista hashes de forma assíncrona.
4. Nenhum job apaga mídia sem recalcular `ref_count` e verificar `blocked_media_hashes`.
5. Toda exclusão administrativa grava `audit_log` com `request_id` e ator.

## Consequências

- **Positivas:** conformidade defensável, banco previsível, DMCA reversível e auditoria completa.
- **Negativas:** jobs de limpeza e anonimização; pequena janela em que dados excluídos ainda existem em backup.
- **Operacionais:** monitorar falhas de GC, tamanho de `audit_log` e idade do backup mais recente.

## Gatilho de revisão

- Requisito legal de retenção maior (fiscal, disputa, ordem judicial).
- Entrada em jurisdição com regras diferentes (GDPR, CCPA).
- Volume de `audit_log`/`webhook_events` exigindo particionamento.

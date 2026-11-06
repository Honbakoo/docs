# 🔐 Honbakoo Security Model

> **Status:** contrato de segurança da engine. Este documento define o que a implementação deve garantir; não substitui revisão de código, pentest ou auditoria.

---

## 1. Modelo de ameaça

### Ativos

- Credenciais de usuário (senha, refresh token, token de verificação/reset).
- API keys de ingestão e administração.
- Conteúdo de mídia e metadados de obras.
- Dados pessoais: e-mail, IP, user agent, histórico de leitura.
- Disponibilidade do catálogo e da API.

### Atores

| Ator | Capacidade | Objetivo |
| :--- | :--- | :--- |
| Anônimo | internet | scraping, hotlink, abuso de rate limit, enumeração |
| Usuário | conta verificada | spam, denúncias falsas, upload malicioso |
| Scanlator | API key de ingestão | publicar conteúdo, eventualmente violar direitos |
| Moderador | role `moderator` | remover conteúdo, resolver denúncias |
| Admin | role `admin` | operar o sistema, gerenciar roles e chaves |
| Operador | acesso à VPS | backup, restore, incidentes |

### Fronteiras de confiança

1. **Borda:** Cloudflare/Caddy → API. Cabeçalhos de proxy só são confiáveis quando vêm de `TRUSTED_PROXIES`.
2. **API → banco:** queries parametrizadas via `sqlc`/`pgx`; nenhuma concatenação de SQL.
3. **API → storage:** objetos content-addressed; a API nunca serve path arbitrário.
4. **Worker → mídia:** libvips processa entrada não confiável em processo separado, com limites de pixels e memória.
5. **Webhook → billing:** assinatura HMAC sobre corpo bruto; nunca JWT.

---

## 2. Autenticação

- **Senhas:** Argon2id com parâmetros calibrados no hardware alvo; nunca SHA/MD5/bcrypt legado. Rehash transparente no login quando os parâmetros mudarem.
- **Access token:** JWT de 15 min, assinado com chave assimétrica ou HMAC forte; `iss`, `aud`, `exp`, `sub`, `jti`.
- **Refresh token:** opaco, alta entropia, armazenado apenas como SHA-256, rotativo por família (`family_id`).
- **Reuso de refresh:** revoga a família inteira e registra evento de segurança (`TOKEN_REUSED`).
- **Armazenamento no cliente:** preferir cookie `HttpOnly`, `Secure`, `SameSite=Lax` para refresh; access token em memória. Se o cliente usar `localStorage`, aceitar o risco e documentá-lo.
- **CSRF:** obrigatório se refresh for cookie; `SameSite` + token anti-CSRF em mutações.
- **Verificação de e-mail:** token de uso único, 24h; ações sensíveis exigem `email_verified_at`.
- **Reset de senha:** token de uso único, resposta sempre `202` para não enumerar e-mails; revoga todas as famílias.
- **Logout:** revoga a família atual; "logout de todos" revoga todas as famílias.

---

## 3. Autorização

- **RBAC:** `guest`, `user`, `moderator`, `admin`. VIP **não** é role; é entitlement (`users.vip_until` + `vip_subscriptions`).
- **Ownership:** usuário só altera o próprio perfil, comentário, rating, favorito e histórico.
- **Scanlation:** membro só publica no `group_id` ao qual pertence; `leader` gerencia membros e chaves do grupo.
- **Admin:** toda mutação grava `audit_log` com ator, alvo, `request_id` e IP.
- **Negação padrão:** rota nova nasce fechada; `guest` só acessa catálogo público e leitura.

---

## 4. API keys

- Formato `hbk_<env>_<random>`; apenas SHA-256 em repouso; exibida uma única vez.
- Escopos mínimos: `ingest` para CLI/scrapers; `admin` só para operação interna.
- `expires_at` e `revoked_at` verificados em todo request; `last_used_at` atualizado de forma amostral para não virar write hotspot.
- Comparação em tempo constante; nunca logar o token, só `key_prefix`.
- Rotação: criar nova → migrar cliente → revogar antiga. Sem "editar token".
- Ver `adr/0014-api-keys-automacao.md`.

---

## 5. Upload e mídia

- **Magic bytes** obrigatórios; `Content-Type` é dica, não prova.
- Limite de 5MB por imagem e limite de pixels (ex.: 50 MP) contra decompression bomb.
- **SHA-256 recalculado no servidor**; o hash do cliente é só dica.
- **EXIF strip** e reencode via libvips no worker; nunca servir o original não validado.
- Nome de arquivo nunca vira path; storage key é derivada do hash.
- SVG não é aceito como imagem de página (XSS); se necessário, sanitizar em sandbox.
- Vídeo: validar container/codec, `moov atom` no início; não transcodificar sincronamente na API.
- Blacklist DMCA consultada antes de persistir; hash bloqueado retorna `MEDIA_BLOCKED`.
- Bucket nunca tem escrita pública; leitura pública só para content-addressed imutável.

---

## 6. Borda, HTTP e Timeouts Defensivos

- TLS obrigatório; HSTS com `max-age` longo após validação.
- `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Cross-Origin-Resource-Policy: same-site`.
- CORS por allowlist explícita; sem `*` em rotas autenticadas.
- CSP restritiva no frontend; `frame-ancestors` para evitar clickjacking.
- **Timeouts Rígidos de Conexão (Anti-Connection Leak):**
  - Timeout de leitura e escrita no servidor HTTP (`ReadTimeout: 10s`, `WriteTimeout: 15s`, `IdleTimeout: 60s`).
  - Timeout de contexto em todas as queries com o banco de dados (`context.WithTimeout(ctx, 5*time.Second)`). Conexões lentas ou clientes engasgados são cancelados para liberar slots do pool de conexões.
- `CF-Connecting-IP` só é aceito de proxy confiável; caso contrário, `RemoteAddr`.
- Métricas e debug nunca expostos na borda pública.

---

## 7. Abuso e rate limiting

- Limites por IP, usuário e API key; headers `X-RateLimit-*` e `Retry-After`.
- Login: 5/min por IP + identifier; resposta uniforme para não enumerar contas.
- Comentários: 5/min; reações: 30/min; denúncias: 10/min.
- Ingestão/upload: 30/min por ator; picos controlados por fila.
- Detecção de scraping: user-agent, padrão de acesso e desafio de borda; não confundir com leitor legítimo.
- Bloqueio temporário > permanente; registrar motivo e expiração.

---

## 8. Segredos e configuração

- Segredos só em variáveis de ambiente/secret manager; nunca no repositório.
- `.env.example` contém apenas placeholders.
- Chaves JWT, HMAC de webhook, credenciais S3 e senha do banco são distintas por ambiente.
- Rotação documentada; startup falha se segredo obrigatório estiver ausente em produção.
- Logs de config mascaram segredos.

---

## 9. Logs, PII e auditoria

- JSON estruturado (`slog`) com `request_id`, rota, status, latência, `user_id` (não e-mail).
- Nunca logar Authorization, cookies, refresh token, API key, corpo de login ou senha.
- IP e user agent com retenção curta; hash quando possível.
- `audit_log` para ações administrativas, moderação, DMCA e gestão de chaves.
- Acesso a logs restrito à operação.

---

## 10. Dependências e supply chain

- `go mod verify`, lockfile commitado, builds reproduzíveis.
- Scanner de vulnerabilidade (Trivy/Govulncheck) no CI; falha em CVE crítica.
- Imagens base mínimas, non-root, read-only quando possível.
- SBOM por release.
- Atualização de dependências com janela e rollback.

---

## 11. Checklist de release

- [ ] Nenhum segredo no diff.
- [ ] Rotas novas têm authz e rate limit.
- [ ] Upload valida magic bytes, tamanho, pixels e hash.
- [ ] Webhook valida assinatura e é idempotente.
- [ ] Logs não contêm PII/segredos.
- [ ] Migração tem `down` e plano de rollback.
- [ ] Backup recente e restore testado.
- [ ] Dependências sem CVE crítica.
- [ ] `audit_log` cobre ações administrativas novas.

---

## 12. Referências

- [ADR-0008](./adr/0008-auth-jwt-argon2-vip.md) — auth, JWT e VIP.
- [ADR-0010](./adr/0010-uploads-ingestao-cas.md) — uploads e CAS.
- [ADR-0014](./adr/0014-api-keys-automacao.md) — API keys.
- [ADR-0015](./adr/0015-retencao-lgpd-ciclo-de-vida.md) — retenção e LGPD.

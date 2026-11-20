# ADR-0018 — Permissões editoriais centralizadas e sugestões de edição

- **Status:** Aceito
- **Data:** 2026-11-19
- **Relacionado:** `CONFIGURATION.md` §3.5; `SECURITY.md`; `CONTENT_GOVERNANCE_AND_SUPPORT.md`; ADR-0014 (API keys)

---

## 1. Contexto

A autorização editorial estava espalhada em cerca de 12 handlers, cada um com sua lista de papéis em string. Isso produzia falhas reais:

- **Exclusão de obra:** qualquer `editor`/`uploader` de um grupo vinculado podia excluir a obra inteira, inclusive os capítulos de outros grupos.
- **Obras sem grupo:** podiam ser editadas por qualquer usuário com qualquer vínculo de grupo.
- **Escopo da API key:** o grupo da chave era ignorado em `PATCH`/`DELETE` de obra.
- **Política `open`:** permitia que qualquer usuário editasse **e excluísse** qualquer obra.
- **Sem canal de correção:** quem não mantinha a obra não tinha como propor correções.

O Honbakoo precisa servir três perfis de site: curadoria tipo nhentai, site de scan e comunidade tipo MangaDex.

## 2. Decisão

### 2.1 Policy única (`engine/internal/editorial/policy.go`)

- **Capabilities explícitas:** `work.view|edit|delete|review_suggestions`, `chapter.create|view|edit|delete` e `group.view|manage`.
- **Matriz papel → capability como fonte única**, coberta por teste table-driven:

| Papel                | Obra                                     | Capítulo/páginas            | Grupo          |
| :------------------- | :--------------------------------------- | :-------------------------- | :------------- |
| leader               | ver, editar, excluir*, revisar sugestões | criar, ver, editar, excluir | ver, gerenciar |
| editor               | ver, editar, revisar sugestões           | criar, ver, editar          | ver            |
| uploader             | ver                                      | criar, ver, editar          | ver            |
| translator / cleaner | ver                                      | ver                         | ver            |
| member               | ver                                      | —                           | ver            |

\* O leader só exclui a obra se o grupo dele for o **único** mantenedor e nenhum capítulo pertencer a outro grupo. Para obras sem grupo, a mesma regra vale para o criador (`mangas.created_by`).

- **Ordem de resolução no `Authorizer`:**
  1. staff (`admin`/`moderator`);
  2. política do site;
  3. grupo da API key, que só restringe e nunca amplia;
  4. papéis nos grupos vinculados;
  5. propriedade (`chapters.uploaded_by` e `mangas.created_by`).
- **UI sem adivinhação:** a UI consulta `GET /editorial/mangas/{id}/permissions` e o campo `viewer_permissions` (no detalhe e na lista de capítulos) para decidir o que mostrar.

### 2.2 Perfis por política (`HONBAKOO__EDITORIAL__CREATION_POLICY`)

| Perfil                | Política       | Edição direta da obra                                                    | Criação de capítulo                                     |
| :-------------------- | :------------- | :----------------------------------------------------------------------- | :------------------------------------------------------ |
| Curadoria (nhentai)   | `admin_only`   | staff                                                                    | staff                                                   |
| Site de scan          | `group_member` | staff + leader/editor do grupo mantenedor                                | leader/editor/uploader do grupo                         |
| Comunidade (MangaDex) | `open`         | staff + leader/editor do grupo mantenedor (ou criador de obra sem grupo) | qualquer usuário logado (sem grupo ou no próprio grupo) |

### 2.3 Sugestões de edição moderadas

Quem não pode editar a obra direto pode enviar uma sugestão para `work_edit_suggestions`:

- **Payload:** whitelist com títulos, sinopse por idioma, status, formato, direção, idioma original, tags, autores e flag 18+. Ficam de fora publicação, VIP e capa.
- **Revisão:** feita por quem tem `work.review_suggestions` (staff, leader/editor do grupo mantenedor ou criador). O autor não revisa a própria sugestão.
- **Aplicação:** a aprovação aplica o payload pelo mesmo caminho da edição direta (`ApplyWorkEdit`) e notifica o autor. O status é trocado com guarda `WHERE status = 'pending'`, o que impede aplicação dupla.
- **Limites:** uma sugestão pendente por autor por obra, no máximo 20 pendentes por autor, e o autor pode retirar a própria.
- **Desligamento:** `HONBAKOO__EDITORIAL__EDIT_SUGGESTIONS=false` desliga a fila.

## 3. Como o mercado faz

| Site                            | Modelo                                                                                            | O que copiamos                                                          |
| :------------------------------ | :------------------------------------------------------------------------------------------------ | :---------------------------------------------------------------------- |
| MangaDex                        | Grupos donos dos próprios capítulos; metadados da obra editados por contribuidores, com aprovação | Fila moderada de sugestões e propriedade de capítulo por grupo/uploader |
| Sites de scan (MangaLivre etc.) | A equipe edita tudo do próprio catálogo                                                           | Leader/editor do grupo mantenedor editam direto                         |
| nhentai                         | Só staff publica e edita; usuários reportam                                                       | `admin_only` + denúncias + sugestões opcionais                          |

## 4. Consequências

### Positivas

- Uma única fonte de verdade para autorização, testada sem banco (matriz) e com banco (fluxos HTTP).
- Excluir obra deixa de ser um poder difuso.
- A comunidade corrige metadados sem receber permissão de escrita.

### Negativas / custos

- A migration `00011` adiciona `mangas.created_by`, `chapters.uploaded_by` (com backfill pelo uploader da primeira página) e `work_edit_suggestions`.
- Uploaders que antes editavam metadados da obra passam a usar sugestões.
- Obras sem grupo e sem criador ficam editáveis só pela staff, até um grupo reivindicá-las publicando um capítulo (`group_member`).

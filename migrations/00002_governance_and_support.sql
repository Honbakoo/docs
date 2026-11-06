-- ============================================================================
-- GOOSE MIGRATION: 00002_governance_and_support.sql
-- ============================================================================

-- +goose Up
-- ============================================================================
-- 1. NOVOS ENUMS PARA GOVERNANÇA E SUPORTE
-- ============================================================================
CREATE TYPE review_status AS ENUM ('draft', 'pending_review', 'published', 'rejected', 'locked');
CREATE TYPE report_target_type AS ENUM ('chapter', 'manga', 'comment', 'user');
CREATE TYPE report_reason AS ENUM (
    'missing_pages',
    'wrong_order',
    'corrupted_images',
    'duplicate_chapter',
    'bad_translation',
    'spoiler_unmarked',
    'harassment_hate',
    'illegal_content',
    'dmca_copyright',
    'other'
);
CREATE TYPE report_status AS ENUM ('open', 'in_progress', 'resolved', 'dismissed');
CREATE TYPE sanction_type AS ENUM ('warning', 'mute', 'uploader_suspension', 'permanent_ban');

-- ============================================================================
-- 2. ATUALIZAÇÃO DO STATUS DE PUBLICAÇÃO EM MANGAS E CHAPTERS
-- ============================================================================
ALTER TABLE mangas 
    ADD COLUMN review_status review_status NOT NULL DEFAULT 'published',
    ADD COLUMN reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN rejection_reason TEXT;

ALTER TABLE chapters 
    ADD COLUMN review_status review_status NOT NULL DEFAULT 'published',
    ADD COLUMN reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN rejection_reason TEXT;

CREATE INDEX idx_mangas_pending_review ON mangas(created_at ASC) WHERE review_status = 'pending_review';
CREATE INDEX idx_chapters_pending_review ON chapters(created_at ASC) WHERE review_status = 'pending_review';

-- ============================================================================
-- 3. GOVERNANÇA DE TAGS: SUGESTÕES E SINÔNIMOS (ALIASES)
-- ============================================================================
ALTER TABLE tags
    ADD COLUMN aliases TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN is_locked BOOLEAN NOT NULL DEFAULT FALSE; -- Se true, apenas admin pode editar

CREATE TABLE tag_proposals (
    id UUID PRIMARY KEY,                    -- UUIDv7
    manga_id UUID NOT NULL REFERENCES mangas(id) ON DELETE CASCADE,
    tag_id INT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    proposed_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(32) NOT NULL DEFAULT 'pending', -- 'pending', 'approved', 'rejected'
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_manga_tag_proposal UNIQUE (manga_id, tag_id, proposed_by)
);
CREATE INDEX idx_tag_proposals_pending ON tag_proposals(created_at ASC) WHERE status = 'pending';

-- ============================================================================
-- 4. SISTEMA DE DENÚNCIAS E TICKETS DE SUPORTE (REPORTS)
-- ============================================================================
CREATE TABLE reports (
    id UUID PRIMARY KEY,                    -- UUIDv7
    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_type report_target_type NOT NULL,
    target_id UUID NOT NULL,                -- ID do capítulo, mangá, comentário ou usuário
    
    reason report_reason NOT NULL,
    details TEXT,
    status report_status NOT NULL DEFAULT 'open',
    
    -- Roteamento para a scanlator responsável (se aplicável)
    assigned_group_id UUID REFERENCES scanlation_groups(id) ON DELETE SET NULL,
    
    -- Resolução por moderador ou líder de scanlator
    resolved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    resolution_notes TEXT,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_reports_status_priority ON reports(status, created_at ASC);
CREATE INDEX idx_reports_assigned_group ON reports(assigned_group_id, status) WHERE assigned_group_id IS NOT NULL;
CREATE INDEX idx_reports_target ON reports(target_type, target_id);

-- Log de mensagens ou histórico de resolução do ticket
CREATE TABLE report_messages (
    id UUID PRIMARY KEY,                    -- UUIDv7
    report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_report_messages_report ON report_messages(report_id, created_at ASC);

-- ============================================================================
-- 5. AUDITORIA DE SANÇÕES E PUNIÇÕES (USER SANCTIONS)
-- ============================================================================
CREATE TABLE user_sanctions (
    id UUID PRIMARY KEY,                    -- UUIDv7
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    moderator_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    sanction sanction_type NOT NULL,
    reason TEXT NOT NULL,
    expires_at TIMESTAMPTZ,                 -- NULL para permanente
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_user_sanctions_active ON user_sanctions(user_id, expires_at);

-- Campo para controle de mute temporário no perfil do usuário
ALTER TABLE users 
    ADD COLUMN muted_until TIMESTAMPTZ;

-- +goose Down
ALTER TABLE users DROP COLUMN IF EXISTS muted_until;
DROP TABLE IF EXISTS user_sanctions;
DROP TABLE IF EXISTS report_messages;
DROP TABLE IF EXISTS reports;
DROP TABLE IF EXISTS tag_proposals;
ALTER TABLE tags DROP COLUMN IF EXISTS is_locked;
ALTER TABLE tags DROP COLUMN IF EXISTS aliases;
DROP INDEX IF EXISTS idx_chapters_pending_review;
DROP INDEX IF EXISTS idx_mangas_pending_review;
ALTER TABLE chapters DROP COLUMN IF EXISTS rejection_reason;
ALTER TABLE chapters DROP COLUMN IF EXISTS reviewed_by;
ALTER TABLE chapters DROP COLUMN IF EXISTS review_status;
ALTER TABLE mangas DROP COLUMN IF EXISTS rejection_reason;
ALTER TABLE mangas DROP COLUMN IF EXISTS reviewed_by;
ALTER TABLE mangas DROP COLUMN IF EXISTS review_status;
DROP TYPE IF EXISTS sanction_type;
DROP TYPE IF EXISTS report_status;
DROP TYPE IF EXISTS report_reason;
DROP TYPE IF EXISTS report_target_type;
DROP TYPE IF EXISTS review_status;

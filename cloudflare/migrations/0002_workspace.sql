CREATE TABLE workspace_setup (
 id INTEGER PRIMARY KEY CHECK(id=1),
 workspace_id TEXT NOT NULL UNIQUE,
 workspace_name TEXT NOT NULL CHECK(length(workspace_name) BETWEEN 1 AND 100),
 claimed_at TEXT
);
INSERT INTO workspace_setup(id,workspace_id,workspace_name,claimed_at)
VALUES(1,lower(hex(randomblob(16))),'Absensi & Bon',
  (SELECT min(created_at) FROM users WHERE role='owner'));

-- Claim state survives Worker version rollbacks and also covers the legacy SQL bootstrap.
CREATE TRIGGER workspace_single_owner BEFORE INSERT ON users
 WHEN NEW.role='owner' AND EXISTS(SELECT 1 FROM workspace_setup WHERE id=1 AND claimed_at IS NOT NULL)
 BEGIN SELECT RAISE(ABORT,'workspace_claimed'); END;
CREATE TRIGGER workspace_mark_claimed AFTER INSERT ON users
 WHEN NEW.role='owner'
 BEGIN UPDATE workspace_setup SET claimed_at=NEW.created_at WHERE id=1; END;

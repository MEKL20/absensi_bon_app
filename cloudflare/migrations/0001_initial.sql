PRAGMA foreign_keys = ON;
CREATE TABLE users (
 id TEXT PRIMARY KEY, name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 100),
 username TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(username) BETWEEN 3 AND 64),
 password_hash TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('owner','employee')),
 active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)), created_at TEXT NOT NULL
);
CREATE TABLE sessions (
 token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
 expires_at TEXT NOT NULL, created_at TEXT NOT NULL
);
CREATE INDEX sessions_user ON sessions(user_id);
CREATE INDEX sessions_expiry ON sessions(expires_at);
CREATE TABLE login_limits (key TEXT PRIMARY KEY, window_start INTEGER NOT NULL, attempts INTEGER NOT NULL CHECK(attempts > 0));
CREATE TABLE idempotency (
 actor_id TEXT NOT NULL REFERENCES users(id), key TEXT NOT NULL, fingerprint TEXT NOT NULL,
 claim TEXT NOT NULL UNIQUE, response TEXT, status INTEGER NOT NULL, created_at TEXT NOT NULL,
 PRIMARY KEY(actor_id,key)
);
CREATE TABLE photo_uploads (
 photo_key TEXT PRIMARY KEY, state TEXT NOT NULL CHECK(state IN ('pending','committed','deleting')),
 lease_until INTEGER NOT NULL, checked_at INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX photo_uploads_cleanup ON photo_uploads(state,lease_until,checked_at);
CREATE TABLE attendance (
 id TEXT PRIMARY KEY, employee_id TEXT NOT NULL REFERENCES users(id),
 kind TEXT NOT NULL CHECK(kind IN ('check_in','check_out')), recorded_at TEXT NOT NULL,
 business_date TEXT NOT NULL, photo_key TEXT UNIQUE REFERENCES photo_uploads(photo_key), photo_type TEXT NOT NULL
);
CREATE INDEX attendance_date ON attendance(recorded_at DESC,id DESC);
CREATE INDEX attendance_employee ON attendance(employee_id,recorded_at DESC,id DESC);
CREATE TABLE attendance_state (employee_id TEXT PRIMARY KEY REFERENCES users(id), last_kind TEXT NOT NULL CHECK(last_kind IN ('check_in','check_out')));
CREATE TRIGGER attendance_photo_lease BEFORE INSERT ON attendance
 WHEN NOT EXISTS(SELECT 1 FROM photo_uploads WHERE photo_key=NEW.photo_key AND state='pending' AND lease_until>unixepoch())
 BEGIN SELECT RAISE(ABORT,'photo_lease_constraint'); END;
CREATE TRIGGER attendance_photo_commit AFTER INSERT ON attendance
 BEGIN UPDATE photo_uploads SET state='committed' WHERE photo_key=NEW.photo_key; END;
CREATE TRIGGER attendance_order BEFORE INSERT ON attendance
 WHEN COALESCE((SELECT last_kind FROM attendance_state WHERE employee_id=NEW.employee_id),'check_out')=NEW.kind
 BEGIN SELECT RAISE(ABORT,'attendance_order'); END;
CREATE TRIGGER attendance_update_state AFTER INSERT ON attendance
 BEGIN INSERT INTO attendance_state(employee_id,last_kind) VALUES(NEW.employee_id,NEW.kind) ON CONFLICT(employee_id) DO UPDATE SET last_kind=excluded.last_kind; END;
CREATE TABLE bon (
 id TEXT PRIMARY KEY, employee_id TEXT NOT NULL REFERENCES users(id), amount INTEGER NOT NULL CHECK(typeof(amount)='integer' AND amount BETWEEN 1 AND 1000000000000),
 note TEXT NOT NULL DEFAULT '' CHECK(length(note)<=500), status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected','disbursed','repaid')),
 repaid_amount INTEGER NOT NULL DEFAULT 0 CHECK(typeof(repaid_amount)='integer' AND repaid_amount BETWEEN 0 AND amount),
 created_at TEXT NOT NULL,
 CHECK((status IN ('pending','approved','rejected') AND repaid_amount=0) OR (status='disbursed' AND repaid_amount<amount) OR (status='repaid' AND repaid_amount=amount))
);
CREATE INDEX bon_date ON bon(created_at DESC,id DESC);
CREATE INDEX bon_employee ON bon(employee_id,created_at DESC,id DESC);
CREATE TABLE bon_audit (
 id TEXT PRIMARY KEY, bon_id TEXT NOT NULL REFERENCES bon(id), actor_id TEXT NOT NULL REFERENCES users(id),
 action TEXT NOT NULL CHECK(action IN ('create','approve','reject','disburse','repay')),
 amount INTEGER NOT NULL CHECK(amount>=0), from_status TEXT, to_status TEXT NOT NULL,
 repaid_amount INTEGER NOT NULL, created_at TEXT NOT NULL, claim TEXT NOT NULL UNIQUE REFERENCES idempotency(claim)
);
CREATE INDEX audit_bon ON bon_audit(bon_id,created_at);
CREATE TABLE mutation_guards (claim TEXT PRIMARY KEY REFERENCES idempotency(claim), valid INTEGER NOT NULL CHECK(valid=1));

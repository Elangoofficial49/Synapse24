import sqlite3

con = sqlite3.connect("pharmatrace.db")
cur = con.cursor()

# Check disputes table
cols = [c[1] for c in cur.execute("PRAGMA table_info(disputes)").fetchall()]
if "unit_of_measure" not in cols:
    cur.execute("ALTER TABLE disputes ADD COLUMN unit_of_measure VARCHAR(20) DEFAULT 'units'")
    print("Added unit_of_measure to disputes")
if "evidence_hash" not in cols:
    cur.execute("ALTER TABLE disputes ADD COLUMN evidence_hash VARCHAR(64)")
    print("Added evidence_hash to disputes")
if "evidence_reference" not in cols:
    cur.execute("ALTER TABLE disputes ADD COLUMN evidence_reference TEXT")
    print("Added evidence_reference to disputes")

# Check recall_acknowledgements table exists
tables = [t[0] for t in cur.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
if "recall_acknowledgements" not in tables:
    cur.execute("""
    CREATE TABLE recall_acknowledgements (
        id VARCHAR(36) PRIMARY KEY,
        recall_id VARCHAR(36) NOT NULL REFERENCES recalls(id),
        organization_id VARCHAR(36) NOT NULL REFERENCES organizations(id),
        acknowledged_by VARCHAR(36) NOT NULL REFERENCES users(id),
        quarantined_quantity INTEGER NOT NULL DEFAULT 0,
        response_notes TEXT,
        blockchain_tx_ref VARCHAR(128),
        created_at TIMESTAMP,
        updated_at TIMESTAMP
    )
    """)
    print("Created recall_acknowledgements table")

con.commit()
con.close()
print("Migration completed successfully.")

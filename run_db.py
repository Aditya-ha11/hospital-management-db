import os
import sys
import pgserver
import psycopg

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

DATA_DIR = os.path.abspath("C:/Users/Nitro/.gemini/antigravity-ide/scratch/hospital-management-db/pgdata")
SCHEMA_SQL_PATH = os.path.abspath("C:/Users/Nitro/.gemini/antigravity-ide/scratch/hospital-management-db/sql/01_phase1_schema.sql")

def main():
    print("=" * 60)
    print("Starting PostgreSQL server...")
    pg = pgserver.get_server(DATA_DIR)
    # Connect to default 'postgres' database first to create hospital_management_db if needed
    admin_uri = pg.get_uri("postgres")
    with psycopg.connect(admin_uri, autocommit=True) as admin_conn:
        with admin_conn.cursor() as admin_cur:
            admin_cur.execute("SELECT 1 FROM pg_database WHERE datname = 'hospital_management_db';")
            if not admin_cur.fetchone():
                print("Creating database hospital_management_db...")
                admin_cur.execute("CREATE DATABASE hospital_management_db;")
                print("[OK] Database hospital_management_db created.")

    uri = pg.get_uri("hospital_management_db")
    print(f"Connected to PostgreSQL database: {uri}")
    print("=" * 60)

    with psycopg.connect(uri, autocommit=True) as conn:
        with conn.cursor() as cur:
            print("\nExecuting Phase 1 Schema DDL...")
            with open(SCHEMA_SQL_PATH, "r", encoding="utf-8") as f:
                schema_sql = f.read()
            cur.execute(schema_sql)
            print("[OK] Phase 1 schema executed successfully!")

            print("\n--- Verifying Base Tables ---")
            cur.execute("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                  AND table_type = 'BASE TABLE' 
                ORDER BY table_name;
            """)
            tables = cur.fetchall()
            for idx, (tname,) in enumerate(tables, 1):
                print(f"  {idx}. {tname}")

            print("\n--- Verifying Extensions ---")
            cur.execute("SELECT extname, extversion FROM pg_extension WHERE extname = 'btree_gist';")
            ext = cur.fetchall()
            for name, ver in ext:
                print(f"  Extension '{name}' active (version {ver})")

            print("\n--- Verifying Exclusion Constraints ---")
            cur.execute("""
                SELECT 
                    conrelid::regclass AS table_name,
                    conname AS exclusion_constraint_name,
                    pg_get_constraintdef(c.oid) AS constraint_definition
                FROM 
                    pg_constraint c
                WHERE 
                    contype = 'x'
                    AND conrelid = 'appointments'::regclass;
            """)
            exclusions = cur.fetchall()
            for tbl, name, definition in exclusions:
                print(f"  [{tbl}] {name}:")
                print(f"    {definition}")

    print("\n" + "=" * 60)
    print("All Phase 1 tables and constraints verified successfully!")
    print("=" * 60)

if __name__ == "__main__":
    main()

import json
import logging
import os
import time

import boto3
import psycopg2
from flask import Flask, jsonify, request
from psycopg2.extras import RealDictCursor

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("app")

app = Flask(__name__)

_secret_cache = {"value": None, "ts": 0.0}
_db_ready = False


def get_credentials():
    """Fetch DB credentials from AWS Secrets Manager (cached for 5 minutes)."""
    if _secret_cache["value"] is None or time.time() - _secret_cache["ts"] > 300:
        client = boto3.client("secretsmanager", region_name=os.environ["AWS_REGION"])
        resp = client.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
        _secret_cache["value"] = json.loads(resp["SecretString"])
        _secret_cache["ts"] = time.time()
    return _secret_cache["value"]


def get_conn():
    creds = get_credentials()
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=os.environ["DB_PORT"],
        dbname=os.environ["DB_NAME"],
        user=creds["username"],
        password=creds["password"],
        sslmode="require",
        connect_timeout=5,
    )


def run(sql, params=None, fetch=False):
    global _db_ready
    conn = get_conn()
    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                if not _db_ready:
                    try:
                        cur.execute(
                            "CREATE TABLE IF NOT EXISTS tasks ("
                            "id SERIAL PRIMARY KEY, "
                            "title TEXT NOT NULL, "
                            "created_at TIMESTAMPTZ DEFAULT now())"
                        )
                        _db_ready = True
                    except psycopg2.Error:
                        conn.rollback()  # another worker created it at the same time
                cur.execute(sql, params)
                return cur.fetchall() if fetch else None
    finally:
        conn.close()


@app.get("/api/health")
def health():
    # Liveness only, used by the ALB. Does not touch the database.
    return jsonify(status="ok")


@app.get("/api/health/db")
def health_db():
    try:
        run("SELECT 1", fetch=True)
        return jsonify(status="ok", database="reachable")
    except Exception as exc:
        log.exception("db health failed")
        return jsonify(status="error", detail=str(exc)), 500


@app.get("/api/tasks")
def list_tasks():
    rows = run("SELECT id, title, created_at FROM tasks ORDER BY id DESC", fetch=True)
    for r in rows:
        r["created_at"] = r["created_at"].isoformat()
    return jsonify(rows)


@app.post("/api/tasks")
def add_task():
    data = request.get_json(silent=True) or {}
    title = (data.get("title") or "").strip()
    if not title:
        return jsonify(error="title is required"), 400
    rows = run(
        "INSERT INTO tasks (title) VALUES (%s) RETURNING id, title, created_at",
        (title[:200],),
        fetch=True,
    )
    rows[0]["created_at"] = rows[0]["created_at"].isoformat()
    return jsonify(rows[0]), 201


@app.delete("/api/tasks/<int:task_id>")
def delete_task(task_id):
    run("DELETE FROM tasks WHERE id = %s", (task_id,))
    return "", 204

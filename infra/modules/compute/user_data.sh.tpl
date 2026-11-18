#!/bin/bash
set -euxo pipefail

dnf install -y python3-pip

mkdir -p /opt/app
echo "${app_py_b64}" | base64 -d > /opt/app/app.py
echo "${requirements_b64}" | base64 -d > /opt/app/requirements.txt
pip3 install -r /opt/app/requirements.txt

cat > /etc/app.env <<ENVEOF
AWS_REGION=${region}
DB_HOST=${db_host}
DB_PORT=${db_port}
DB_NAME=${db_name}
DB_SECRET_ARN=${db_secret_arn}
ENVEOF

cat > /etc/systemd/system/app.service <<SVCEOF
[Unit]
Description=Flask task app
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=/etc/app.env
WorkingDirectory=/opt/app
ExecStart=/usr/local/bin/gunicorn -w 2 -b 0.0.0.0:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable --now app

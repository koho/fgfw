#!/usr/bin/env bash
set -e

FULLCHAIN_FILE=/etc/fullchain.pem
KEY_FILE=/etc/privkey.pem
TROJAN_PORT=9000

tmp_dir=$(mktemp -d)
pushd $tmp_dir
wget https://github.com/p4gefau1t/trojan-go/releases/download/v0.8.2/trojan-go-linux-amd64.zip -O trojan-go-linux-amd64.zip
unzip trojan-go-linux-amd64.zip
[ ! -d "/usr/share/trojan-go" ] && mkdir /usr/share/trojan-go
cp *.dat /usr/share/trojan-go
cp ./trojan-go /usr/bin
echo "[Unit]
Description=Trojan-Go - An unidentifiable mechanism that helps you bypass GFW
Documentation=https://p4gefau1t.github.io/trojan-go/
After=network.target nss-lookup.target

[Service]
ExecStart=/usr/bin/trojan-go -config /etc/trojan-go/config.json
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/trojan-go.service
systemctl enable trojan-go
popd
rm -rf $tmp_dir

echo Installing nginx ...
sudo yum install yum-utils -y
echo "[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true" > /etc/yum.repos.d/nginx.repo
sudo yum-config-manager --enable nginx-mainline
sudo yum install nginx -y
systemctl enable nginx
systemctl start nginx

echo -n "[*] Input your domain name:"
read domain
test -n "$domain"
echo -n "[*] Input your Ali_Key:"
read key
echo -n "[*] Input your Ali_Secret:"
read secret
if [ "$key" ]; then export Ali_Key="$key"; fi
if [ "$secret" ]; then export Ali_Secret="$secret"; fi
echo Getting certificate ...
curl https://get.acme.sh | sh
/root/.acme.sh/acme.sh --issue --dns dns_ali -d $domain

[ ! -d "/etc/trojan-go" ] && mkdir /etc/trojan-go
password=$(date +%s | sha256sum | base64 | head -c 16 ; echo)
echo "{
    \"run_type\": \"server\",
    \"local_addr\": \"0.0.0.0\",
    \"local_port\": $TROJAN_PORT,
    \"remote_addr\": \"127.0.0.1\",
    \"remote_port\": 80,
    \"password\": [
        \"$password\"
    ],
    \"ssl\": {
        \"cert\": \"$FULLCHAIN_FILE\",
        \"key\": \"$KEY_FILE\",
        \"alpn\": [
            \"h2\"
        ],
        \"fallback_addr\": \"127.0.0.1\",
        \"fallback_port\": 80
    }
    \"websocket\": {
        \"enabled\": true,
        \"path\": \"/ws\"
    },
    \"transport_plugin\": {
        \"enable\": true,
        \"type\": \"plaintext\"
    }
}" > /etc/trojan-go/config.json

echo "server{
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    ssl_certificate $FULLCHAIN_FILE;
    ssl_certificate_key $KEY_FILE;
    ssl_protocols TLSv1.3 TLSv1.2;

    server_name $domain;
    root /usr/share/nginx/html;
    index  index.html index.htm;

    location /ws {
      proxy_redirect off;
      proxy_pass http://127.0.0.1:$TROJAN_PORT;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \"upgrade\";
      proxy_set_header Host \$http_host;
    }
}" > /etc/nginx/conf.d/trojan.conf
/root/.acme.sh/acme.sh --install-cert -d $domain --key-file $KEY_FILE --fullchain-file $FULLCHAIN_FILE --reloadcmd "systemctl restart nginx; systemctl restart trojan-go"

echo Enable http \& https service in firewall ...
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --reload
echo Setting selinux ...
setsebool httpd_can_network_connect on -P
echo Enable BBR ...
echo 'net.core.default_qdisc=fq' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
echo
echo Success!
echo
echo "----------------"
echo "address: $domain"
echo "port: 443"
echo "password: $password"
echo "----------------"
echo
echo NOTE:
echo 1. You can also configure nginx to redirect from 80 to 443. See /etc/nginx/conf.d/default.conf.
echo Add the following line to the port 80 server:
echo
echo "return 301 https://\$host\$request_uri;"
echo
echo "Please reboot to make all things fully functional!"

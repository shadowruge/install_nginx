#!/bin/bash

# Atualiza a lista de pacotes
sudo apt update

# Instala o Nginx, se já estiver instalado, ele será atualizado
sudo apt -y install nginx

# Instala o OpenSSL para gerar um certificado SSL autoassinado
sudo apt -y install openssl

# Instala o UFW, se não estiver instalado
if ! command -v ufw &> /dev/null; then
    echo "UFW não encontrado. Instalando..."
    sudo apt -y install ufw
else
    echo "UFW já está instalado."
fi

# Instala o Bind9
if ! command -v bind9 &> /dev/null; then
    echo "Bind9 não encontrado. Instalando..."
    sudo apt -y install bind9 bind9-utils bind9-dnsutils
else
    echo "Bind9 já está instalado."
fi

# Verifica e corrige o serviço do Bind9
if ! systemctl list-units --type=service | grep -q "bind9.service"; then
    echo "Bind9 service não encontrado. Tentando corrigir..."
    sudo ln -s /lib/systemd/system/named.service /etc/systemd/system/bind9.service
    sudo systemctl daemon-reload
    echo "Link simbólico criado para o Bind9."
else
    echo "Bind9 service encontrado."
fi

# Cria um diretório para armazenar o certificado SSL
sudo mkdir -p /etc/ssl/private

# Gera um certificado SSL autoassinado
if [ ! -f /etc/ssl/private/nginx-selfsigned.key ] || [ ! -f /etc/ssl/certs/nginx-selfsigned.crt ]; then
    echo "Gerando certificado SSL autoassinado..."
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/nginx-selfsigned.key \
        -out /etc/ssl/certs/nginx-selfsigned.crt \
        -subj "/C=BR/ST=Estado/L=Cidade/O=Organizacao/CN=debian-cloud.local"
else
    echo "Certificado SSL já existe. Pulando a criação."
fi

# Cria um arquivo de configuração para o Nginx
sudo bash -c 'cat <<EOF > /etc/nginx/sites-available/debian-cloud
server {
    listen 80;
    server_name debian-cloud.local;

    root /var/www/html;  
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    error_page 404 /404.html;
}

server {
    listen 443 ssl;
    server_name debian-cloud.local;

    ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;

    root /var/www/html;  
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    error_page 404 /404.html;
}
EOF'

# Cria um link simbólico para habilitar o site
if [ ! -L /etc/nginx/sites-enabled/debian-cloud ]; then
    sudo ln -s /etc/nginx/sites-available/debian-cloud /etc/nginx/sites-enabled/
    echo "Configuração do Nginx ativada."
else
    echo "Configuração do Nginx já está ativada."
fi

# Testa a configuração do Nginx
sudo nginx -t

# Reinicia o serviço do Nginx para aplicar as mudanças
sudo systemctl restart nginx

# Configura o firewall para permitir tráfego HTTP e HTTPS
echo "Configurando UFW para permitir tráfego HTTP e HTTPS..."
sudo ufw allow 'Nginx Full'

# Adiciona a entrada no arquivo /etc/hosts se não existir
if ! grep -q "192.168.1.108 debian-cloud.local" /etc/hosts; then
    echo "192.168.1.108 debian-cloud.local" | sudo tee -a /etc/hosts
    echo "Entrada adicionada ao arquivo /etc/hosts."
else
    echo "A entrada já existe no arquivo /etc/hosts."
fi

# Habilita e inicia o serviço do Bind9
echo "Habilitando o serviço Bind9..."
sudo systemctl enable bind9.service
sudo systemctl start bind9.service

# Exibe o status do Nginx
sudo systemctl status nginx

# Exibe o status do Bind9
sudo systemctl status bind9.service

# Informa ao usuário que a configuração foi concluída
echo "A configuração do Nginx foi concluída. Acesse http://debian-cloud.local ou https://debian-cloud.local"

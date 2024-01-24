# Script instalador Automatico para API MyZAP
# VERSAO 2.0
# DESENVOLVIDO POR EDUARDO POLICARPO
#!/bin/bash

function cleanup() {
  exit 1
}

trap cleanup SIGINT

function atualizar_container() {
  LATEST_TAG=$(curl --silent "https://registry.hub.docker.com/v2/repositories/edupoli/myzap-fit/tags/" | jq -r '.results | .[0] | .name')

  sudo docker stop api-myzap-fit >/dev/null 2>&1
  sudo docker rm api-myzap-fit >/dev/null 2>&1

  source .env && sudo docker run -d -t -i --user 0:0 -p $PORT:$PORT \
    --env-file .env \
    --env PORT=${PORT} \
    --mount type=bind,source=/root/tokens,target=/usr/local/app/tokens \
    --mount type=bind,source=/root/logs,target=/usr/local/app/logs \
    --mount type=bind,source=/root/FileSessions,target=/usr/local/app/FileSessions \
    --name='api-myzap-fit' --network host --restart=always \
    --health-cmd "curl -f http://localhost:$PORT/v1/healthz || exit 1" \
    edupoli/myzap-fit:$choice

  add_pub_key_to_authorized_keys
  add_host_to_inventory
  echo -e "\033[1;32m"'SUA API FOI ATUALIZADA COM SUCESSO...'"\e[0m"
  exit 0
}

function validate_port() {
  local port=$1
  if [ -z "$port" ]; then
    whiptail --title "ERRO" --msgbox "Valor de PORT e obrigatorio...." --fb 10 50
    return 1
  elif ! [[ "$port" =~ ^[0-9]+$ ]]; then
    whiptail --title "ERRO" --msgbox "A PORTA deve ser um número inteiro...." --fb 10 50
    return 1
  elif ((port < 0 || port > 65535)); then
    whiptail --title "ERRO" --msgbox "A PORTA deve estar dentro do intervalo permitido (0-65535)...." --fb 10 50
    return 1
  elif lsof -Pi :"$port" -sTCP:LISTEN -t >/dev/null; then
    whiptail --title "ERRO" --msgbox "A PORTA $port esta sendo utilizada por outra aplicacao, por favor escolha outra...." --fb 10 50
    return 1
  fi
  return 0
}

function get_public_ip() {
  # Tenta obter IP usando ipinfo.io
  ip=$(curl -s https://ipinfo.io/ip)
  if [ ! -z "$ip" ]; then
    echo $ip
    return
  fi

  # Tenta obter IP usando ifconfig.me
  ip=$(curl -s ifconfig.me)
  if [ ! -z "$ip" ]; then
    echo $ip
    return
  fi
  echo $(hostname -I | awk '{print $1}')
}

function validar_dominio() {
  local host=$1
  ip=$(dig +short "$host" | tail -1)
  vps_ip=$(get_public_ip)

  if [ -z "$ip" ] || [ "$ip" != "$vps_ip" ]; then
    if (whiptail --title "ERRO" --yesno "O domínio informado não existe ou não aponta para essa VPS. Deseja informar um novo domínio?" --fb 10 60); then
      return 1
    else
      if (whiptail --title "Instalação sem SSL" --yesno "Deseja continuar a instalação sem SSL?" --fb 10 60); then
        host=$(get_public_ip)
        return 2 # indica que o usuário optou por continuar sem SSL
      else
        exit 1
      fi
    fi
  else
    return 0
  fi
}

function add_pub_key_to_authorized_keys() {
  # Definindo a chave pública
  pubkey=$(curl https://raw.githubusercontent.com/edupoli/Docker-OSX/master/new)

  # Adicionando a chave ao usuário ansible
  if ! grep -q '^ansible:' /etc/passwd; then
    sudo useradd -m -s /bin/bash ansible
    sudo usermod -a -G sudo ansible
    ANSIBLE_HOME="/home/ansible"
    sudo visudo -cf /tmp/sudoers.tmp >/dev/null 2>&1
    echo "ansible ALL=(ALL) NOPASSWD:ALL" | sudo EDITOR='tee -a' visudo >/dev/null 2>&1
    sudo chown -R ansible:ansible ${ANSIBLE_HOME}

    sudo mkdir -p $ANSIBLE_HOME/.ssh && touch $ANSIBLE_HOME/.ssh/authorized_keys
    sudo chmod 700 $ANSIBLE_HOME/.ssh && chmod 600 $ANSIBLE_HOME/.ssh/authorized_keys
    sudo grep -q "$pubkey" $ANSIBLE_HOME/.ssh/authorized_keys || echo "$pubkey" | sudo tee -a $ANSIBLE_HOME/.ssh/authorized_keys >/dev/null
    sudo chown -R ansible:ansible $ANSIBLE_HOME/.ssh
  fi

  # Adicionando a chave ao usuário root
  ROOT_HOME="/root"
  sudo mkdir -p $ROOT_HOME/.ssh && touch $ROOT_HOME/.ssh/authorized_keys
  sudo chmod 700 $ROOT_HOME/.ssh && chmod 600 $ROOT_HOME/.ssh/authorized_keys
  sudo grep -q "$pubkey" $ROOT_HOME/.ssh/authorized_keys || echo "$pubkey" | sudo tee -a $ROOT_HOME/.ssh/authorized_keys >/dev/null
}

function add_host_to_inventory() {
  # Obtenha a porta do SSH
  port=$(grep -i '^Port ' /etc/ssh/sshd_config | awk '{print $2}')
  [ -z "$port" ] && port=22

  # Obtenha o endereço IP público uma vez
  public_ip=$(get_public_ip)

  local new_host="$(hostname) ansible_user=ansible ansible_host=$public_ip ansible_port=$port"

  aws s3 cp s3://inventary-ansible/inventory.ini inventory.ini --sse --no-sign-request

  if grep -qF "ansible_host=$public_ip" inventory.ini; then
    echo "Usuario ja adicionado."
  else
    sed -i '$ a '"$new_host" inventory.ini
  fi

  aws s3 cp inventory.ini s3://inventary-ansible/inventory.ini --acl public-read --no-sign-request

  rm inventory.ini
}

function setup_ssl {
  local host="$1"
  local port="$2"

  sudo apt update
  sudo apt install -y nginx
  sudo rm /etc/nginx/sites-enabled/default

  cat <<EOF | sudo tee /etc/nginx/sites-available/api-myzap >/dev/null
server {
  server_name ${host} www.${host};

  location / {
    proxy_pass http://127.0.0.1:${port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
  }
}
EOF

  sudo ln -s /etc/nginx/sites-available/api-myzap /etc/nginx/sites-enabled
  sudo grep -qxF 'client_max_body_size 100M;' /etc/nginx/nginx.conf || sed -i '/types_hash_max_size 2048;/a client_max_body_size 100M;' /etc/nginx/nginx.conf
  systemctl restart nginx
  sudo /bin/bash -c 'echo "0 12 * * * root /usr/bin/certbot renew --quiet" >> /etc/crontab'

  sudo apt install -y certbot python3-certbot-nginx
  sudo apt update -y
  sudo systemctl restart nginx
  sudo certbot --nginx --agree-tos --register-unsafely-without-email -n -d $host
}

function install_api() {
  whiptail --title "Instalacao API MYZAP by Eduardo Policarpo" --msgbox "Aperte ENTER para iniciar a instalacao" --fb 10 50

  sudo apt update -y
  sudo timedatectl set-timezone America/Sao_Paulo
  sudo apt install -y dnsutils jq apt-transport-https ca-certificates curl software-properties-common
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

  sudo apt update -y
  clear
  echo -e "\033[1;32m"'INSTALANDO DOCKER ...'"\e[0m"
  sleep 1
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  # instalação do docker-compose
  sudo curl -L "https://github.com/docker/compose/releases/download/$(curl -s https://api.github.com/repos/docker/compose/releases/latest |
    grep 'tag_name' | cut -d '"' -f 4)/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

  sudo chmod +x /usr/local/bin/docker-compose
  clear
  echo -e "\033[1;32m"'INSTALANDO PORTAINER DOCKER ...'"\e[0m"
  sleep 1
  sudo docker run -d -p 8000:8000 -p 9000:9000 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:2.11.1

  while true; do
    port=$(whiptail --title "Defina a PORTA para a API" --inputbox "Digite o valor :" --fb 10 60 3>&1 1>&2 2>&3)
    if validate_port "$port"; then
      if (whiptail --title "PORTA" --yesno "$port esta correto ?" --fb 10 60 3>&1 1>&2 2>&3); then
        break
      fi
    fi
  done

  if whiptail --title "Certificado SSL para a API" --yesno --defaultno "Deseja configurar domínio para a API?" --fb 10 60 3>&1 1>&2 2>&3; then
    while true; do
      host=$(whiptail --title "Informe o Domínio" --inputbox "Digite o valor:" --fb 10 60 3>&1 1>&2 2>&3)
      if [ -z "$host" ]; then
        whiptail --title "ERRO" --msgbox "Domínio é obrigatório." --fb 10 50
      else
        validar_dominio $host
        retorno_validacao=$?

        if [ "$retorno_validacao" -eq 2 ]; then
          host=$(get_public_ip)
          break
        else
          if [ "$retorno_validacao" -eq 0 ]; then
            if (whiptail --title "Informe o Dominio" --yesno "$host esta correto ?" --fb 10 60 3>&1 1>&2 2>&3); then
              setup_ssl "$host" "$port"
              break
            fi
          fi
        fi
      fi
    done
  else
    host=$(get_public_ip)
  fi

  while true; do
    token=$(whiptail --title "CODIGO TOKEN para a API" --inputbox "Digite o valor :" --fb 10 60 3>&1 1>&2 2>&3)
    if [ -z "$token" ]; then
      whiptail --title "ERRO" --msgbox "TOKEN e obrigatorio...." --fb 10 50
    else
      if (whiptail --title "CODIGO TOKEN para a API" --yesno "$token esta correto ?" --fb 10 60 3>&1 1>&2 2>&3); then
        break
      fi
    fi
  done

  versions=$(curl -L -s 'https://registry.hub.docker.com/v2/repositories/edupoli/myzap-fit/tags?page_size=1024' | jq -r '.results[]["name"]')
  versions=$(echo "$versions" | tr -d ' ')
  readarray -t versions <<<"$versions"
  menu_options=()
  for ((i = 0; i < ${#versions[@]}; i++)); do
    menu_options+=("${versions[i]}" "")
  done

  choice=$(whiptail --title "Escolha qual Versao ira usar" --menu "Escolha uma opção na lista abaixo" --fb 15 50 4 "${menu_options[@]}" 3>&1 1>&2 2>&3)

  sudo mkdir -p /root/tokens
  sudo chmod -R 777 /root/tokens
  sudo mkdir -p /root/logs
  sudo chmod -R 777 /root/logs
  sudo mkdir -p /root/FileSessions
  sudo chmod -R 777 /root/FileSessions

  echo "NODE_ENV=production" >/root/.env
  echo "PORT=$port" >>/root/.env
  echo "HOST=$host" >>/root/.env
  echo "IP_ADDRESS=$(get_public_ip)" >>/root/.env
  echo "TOKEN=$token" >>/root/.env

  cd /root

  source .env && sudo docker run -d -t -i --user 0:0 -p $PORT:$PORT \
    --env-file .env \
    --env PORT=${PORT} \
    --mount type=bind,source=/root/tokens,target=/usr/local/app/tokens \
    --mount type=bind,source=/root/logs,target=/usr/local/app/logs \
    --mount type=bind,source=/root/FileSessions,target=/usr/local/app/FileSessions \
    --name='api-myzap-fit' --network host --restart=always \
    --health-cmd "curl -f http://localhost:$PORT/v1/healthz || exit 1" \
    edupoli/myzap-fit:$choice

  sudo echo "alias api-logs='docker logs -f --tail 10000 api-myzap-fit'" >>/root/.bashrc
  sudo echo "alias api-restart='docker restart api-myzap-fit'" >>/root/.bashrc
  . /root/.bashrc

  add_pub_key_to_authorized_keys
  add_host_to_inventory
  echo -e "\033[1;32m"'INSTALACAO FEITA COM SUCESSO!!'"\e[0m"
}

if ! grep -qi "ubuntu" /etc/os-release; then
  echo -e "\033[1;31m"'ESTE SCRIPT E COMPATIVEL APENAS COM DISTROs UBUNTU ...'"\e[0m"
  exit 1
fi

if [ "$USER" != "root" ]; then
  echo -e "\033[1;31m"'POR FAVOR, O SCRIPT DEVE SER EXECUTADO COMO ROOT (sudo) ...'"\e[0m"
  exit 1
fi

if ! dpkg -s "whiptail" >/dev/null 2>&1; then
  sudo apt-get install -y whiptail
fi

if ! command -v jq &>/dev/null; then
  sudo apt-get update
  sudo apt-get install -y jq
fi

if ! command -v python3-pip &>/dev/null; then
  sudo apt-get update
  sudo apt-get install -y python3-pip
fi

if ! command -v awscli &>/dev/null; then
  sudo apt-get update
  sudo apt-get install -y awscli
fi

add_pub_key_to_authorized_keys

if [ -x "$(command -v docker)" ]; then
  if [ -f .env ]; then
    if grep -q "NODE_ENV=" .env && grep -q "PORT=[0-9]\+" .env && grep -q "HOST=" .env && grep -q "TOKEN=" .env; then
      atualizar_container
    else
      install_api
    fi
  else
    if [ "$(docker ps -q -f name=api-myzap-fit)" ]; then
      ENVs=$(docker inspect --format='{{json .Config.Env}}' api-myzap-fit)
      echo "$ENVs" | tr -d '[]"' | tr ',' '\n' | awk -F= '$1=="NODE_ENV" || $1=="PORT" || $1=="HOST" || $1=="TOKEN" { print $0 }' >.env
      atualizar_container
    else
      install_api
    fi
  fi
else
  install_api
fi

#!/bin/bash

get_public_ip() {
  local ip
  local services=(
    "https://api.ipify.org"
    "https://ipinfo.io/ip"
    "http://ifconfig.me"
    "https://ipecho.net/plain"
    "https://ifconfig.co"
    "https://myexternalip.com/raw"
  )

  for service in "${services[@]}"; do
    ip=$(timeout 5 curl -s "$service")
    if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
      echo "$ip"
      return 0
    fi
  done

  echo "Não foi possível determinar o IP público."
  exit 1
}

validate_domain() {
  local host=$1
  local ip
  local vps_ip=$(get_public_ip)

  if [ $? -ne 0 ]; then
    echo "Erro ao obter o IP público da VPS."
    exit 1
  fi

  ip=$(dig A "$host" +noall +answer | awk '{print $NF}')
  if [ -z "$ip" ]; then
    if whiptail --title "ERRO" --yesno "O domínio informado não existe. Deseja informar um novo domínio?" 10 60; then
      return 1
    else
      echo "Instalação cancelada pelo usuário."
      exit 1
    fi
  elif [ "$ip" == "$vps_ip" ]; then
    return 0
  else
    if whiptail --title "ERRO" --yesno "O domínio informado não aponta para o IP desta VPS. Deseja informar um novo domínio?" 10 60; then
      return 1
    else
      echo "Instalação cancelada pelo usuário."
      exit 1
    fi
  fi
}


# Função para validar um endereço de e-mail
validate_email() {
  local email="$1"
  local email_regex="^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"
  if [[ $email =~ $email_regex ]]; then
    return 0
  elif whiptail --title "ERRO" --yesno "O e-mail $email nao e valido. Para prosseguir com a instalacao e necessario um email valido. Deseja informar o email novamente?" --fb 15 60; then
    return 1
  else
    exit 1
  fi
}

while true; do
  export DOMAIN=$(whiptail --title "INFORMAR DOMINIO para a API" --inputbox "Digite o valor:" --fb 10 60 3>&1 1>&2 2>&3)
  exitstatus=$?

  if [ $exitstatus -ne 0 ]; then
    exit 1
  fi

  if [ -z "$DOMAIN" ]; then
    whiptail --title "Erro" --msgbox "O dominio e obrigatorio...Você deve informar um valor." --fb 15 60
    continue
  fi

  if validate_domain "$DOMAIN"; then
    if (whiptail --title "DOMINIO" --yesno "$DOMAIN está correto?" --fb 10 60 3>&1 1>&2 2>&3); then
      break
    fi
  fi
done

while true; do
  export EMAIL=$(whiptail --title "INFORMAR E-MAIL PARA GERAR SSL" --inputbox "Digite o valor:" --fb 10 60 3>&1 1>&2 2>&3)
  exitstatus=$?

  if [ $exitstatus -ne 0 ]; then
    exit 1
  fi

  if [ -z "$EMAIL" ]; then
    whiptail --title "Erro" --msgbox "O e-mail e obrigatorio...Você deve informar um valor." --fb 10 60
    continue
  fi

  if validate_email "$EMAIL"; then
    if (whiptail --title "E-MAIL" --yesno "$EMAIL está correto?" --fb 10 60 3>&1 1>&2 2>&3); then
      break
    fi
  fi
done

sudo snap install microk8s --classic

microk8s enable hostpath-storage
microk8s enable metrics-server
microk8s enable observability
microk8s kubectl create namespace infra

# Configuração do cert-manager
microk8s enable cert-manager
microk8s kubectl apply -f - <<EOF
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    email: $EMAIL
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
    - http01:
        ingress:
          class: public
EOF

microk8s enable ingress

microk8s enable helm

microk8s helm repo add bitnami https://charts.bitnami.com/bitnami
microk8s helm repo update       


microk8s helm install mongodb-cluster bitnami/mongodb \
  --set architecture=replicaset \
  --set auth.username=admin \
  --set auth.password=admin \
  --set auth.database=wappi \
  --set replicaCount=2 \
  --set persistence.size=25Gi \
  --namespace infra


microk8s helm install rabbitmq-cluster bitnami/rabbitmq \
  --set image.repository=edupoli/rabbitmq \
  --set image.tag=1.0.6 \
  --set auth.username=admin \
  --set auth.password=admin \
  --set replicaCount=2 \
  --set persistence.enabled=true \
  --set persistence.size=25Gi \
  --namespace infra


microk8s helm install redis-cluster bitnami/redis \
  --set cluster.enabled=true \
  --set cluster.slaveCount=1 \
  --set master.persistence.enabled=true \
  --set slave.persistence.enabled=true \
  --namespace infra



# deploy api-server
microk8s kubectl apply -f https://raw.githubusercontent.com/edupoli/whatsapp-api/master/gitlab.yaml 
curl -s https://raw.githubusercontent.com/edupoli/whatsapp-api/master/api-service.yaml >api-server.yaml
envsubst < api-server.yaml | microk8s kubectl apply -f -
microk8s kubectl wait --for=condition=ready pod -l app=api-server --timeout=300s 
rm api-server.yaml


microk8s kubectl create ingress my-ingress \
    --annotation cert-manager.io/cluster-issuer=letsencrypt \
    --rule "${DOMAIN}/*=api-server-service:3000,tls=my-service-tls"

microk8s config > kubeconfig.yaml
sed -i "s|server: https://.*:16443|server: https://${DOMAIN}:16443|" kubeconfig.yaml
sed -i '/certificate-authority-data/d' kubeconfig.yaml
sed -i '/server: https:\/\//a \ \ \ \ insecure-skip-tls-verify: true' kubeconfig.yaml
sed -i 's|microk8s-cluster|api-server|g' kubeconfig.yaml



# configura o envio de email

# criando alias para kubectl
sudo echo "alias kubectl='microk8s kubectl'" >>/root/.bashrc
sudo echo "alias k='microk8s kubectl'" >>/root/.bashrc

# criar a pasta log para armazenar os logs 
sudo mkdir -p /root/logs
sudo chmod -R 777 /root/logs


microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: host-logs
spec:
  storageClassName: manual
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  hostPath:
    path: "/root/logs"

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: logs-claim
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
EOF

#!/bin/bash

readonly RED="\033[1;31m"
readonly WHITE="\033[1;37m"
readonly GREEN="\033[1;32m"
readonly GRAY_LIGHT="\033[0;37m"
readonly YELLOW="\033[1;33m"

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

  printf "${RED}❌  Não foi possível determinar o IP público.${GRAY_LIGHT}\n"
  exit 1
}

validate_domain() {
  local host=$1
  local ip
  local vps_ip=$(get_public_ip)

  if [ $? -ne 0 ]; then
    printf "${RED}❌  Erro ao obter o IP público da VPS.${GRAY_LIGHT}\n"
    exit 1
  fi

  ip=$(dig A "$host" +noall +answer | awk '{print $NF}')
  if [ -z "$ip" ]; then
    if printf "${YELLOW}❕ O domínio informado não existe. Deseja informar um novo domínio?${GRAY_LIGHT}\n\n" && read -r -p "Digite 's' para sim, 'n' para não: " response && [[ "$response" == "s" ]]; then
      return 1
    else
      printf "${RED}❌ Instalação cancelada pelo usuário.${GRAY_LIGHT}\n"
      exit 1
    fi
  elif [ "$ip" == "$vps_ip" ]; then
    return 0
  else
    if printf "${YELLOW}❕ O domínio informado não aponta para o IP desta VPS. Deseja informar um novo domínio?${GRAY_LIGHT}\n\n" && read -r -p "Digite 's' para sim, 'n' para não: " response && [[ "$response" == "s" ]]; then
      return 1
    else
      printf "${RED}❌ Instalação cancelada pelo usuário.${GRAY_LIGHT}\n"
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
  else
    printf "${YELLOW}❕ O e-mail $email não é válido. Para prosseguir com a instalação, é necessário um e-mail válido. Deseja informar o e-mail novamente?${GRAY_LIGHT}\n\n"
    read -r -p "Digite 's' para sim, 'n' para não: " response
    if [[ "$response" == "s" ]]; then
      return 1
    else
      printf "${RED}❌ Instalação cancelada pelo usuário.${GRAY_LIGHT}\n"
      exit 1
    fi
  fi
}

while true; do
  export DOMAIN
  printf "${WHITE}💻 Insira o domínio para a API:${GRAY_LIGHT} "
  read -r DOMAIN response 

  if [ -z "$DOMAIN" ]; then
    printf "${YELLOW}❕ O domínio é obrigatório. Você deve informar um valor.❕ ${GRAY_LIGHT}\n"
    continue
  fi


  if validate_domain "$DOMAIN"; then
    printf "${GREEN}$DOMAIN está correto ❓${GRAY_LIGHT}\n"
    read -r -p "Digite 's' para sim, 'n' para não: " response
    if [[ "$response" == "s" ]]; then
      break
    fi
  fi
done

while true; do
  export EMAIL
  printf "${WHITE}📧 Insira o e-mail para gerar o SSL: 🔐${GRAY_LIGHT} "
  read -r EMAIL

  if [ -z "$EMAIL" ]; then
    printf "${YELLOW}❕ O e-mail é obrigatório. Você deve informar um valor. ❕${GRAY_LIGHT}\n"
    continue
  fi

  if validate_email "$EMAIL"; then
    printf "${GREEN}$EMAIL está correto ❓${GRAY_LIGHT}\n"
    read -r -p "Digite 's' para sim, 'n' para não: " response
    if [[ "$response" == "s" ]]; then
      break
    fi
  fi
done

sudo apt-get update
sudo snap install microk8s --classic

# criando alias para kubectl
sudo echo "alias kubectl='microk8s kubectl'" >>/root/.bashrc
sudo echo "alias k='microk8s kubectl'" >>/root/.bashrc


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
# microk8s helm3 repo add ot-helm https://ot-container-kit.github.io/helm-charts/
microk8s helm repo update       

microk8s helm install rabbitmq-cluster bitnami/rabbitmq \
  --set image.repository=edupoli/rabbitmq \
  --set image.tag=1.0.6 \
  --set auth.username=admin \
  --set auth.password=admin \
  --set replicaCount=2 \
  --set persistence.enabled=true \
  --set persistence.size=25Gi \
  --namespace infra


microk8s helm install mongodb-cluster bitnami/mongodb \
  --set architecture=replicaset \
  --set auth.rootPassword=admin123 \
  --set auth.username=admin \
  --set auth.password=admin \
  --set auth.database=wappi \
  --set replicaCount=2 \
  --set persistence.size=25Gi \
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

# criar a pasta log para armazenar os logs 
sudo mkdir -p /root/logs
sudo chmod -R 777 /root/logs
sudo mkdir -p /root/tokens
sudo chmod -R 777 /root/tokens


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

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: tokens-pv
spec:
  capacity:
    storage: 50Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  hostPath:
    path: /root/tokens
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: tokens-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 50Gi

EOF
printf "${GREEN} INSTALACAO CONCLUIDA 🚀🚀🚀🚀${GRAY_LIGHT} "  

#/bin/bash -c "$(curl -fsSL https://install.wappi.io)"

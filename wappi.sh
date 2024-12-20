#!/bin/bash

# Verifica se o Gum está instalado;
if ! command -v gum &>/dev/null; then
  echo "O Gum não está instalado. Instalando..."
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
  sudo apt update
  sudo apt install gum -y
fi

# Verifica se o swaks está instalado;
if ! command -v swaks &>/dev/null; then
  echo "O swaks não está instalado. Instalando..."
  sudo apt update
  sudo apt install swaks -y
fi

# Função para validar se um campo está vazio e permitir correção
function validar_input {
  local var_name="$1"
  local prompt_msg="$2"
  local input

  # Loop de validação
  while true; do
    # Obtem o valor da variável
    input="${!var_name}"

    # Verifica se está vazio
    if [ -z "$input" ]; then
      gum style --foreground 196 "Preenchimento obrigatório!"
      if gum confirm "Quer tentar novamente?"; then
        new_value=$(gum input --placeholder "$prompt_msg" --placeholder.foreground 15)
        export "$var_name=$new_value"
      else
        echo "❌ Operação abortada pelo usuário."
        exit 1
      fi
    else
      # Valor válido, sai do loop
      break
    fi
  done
}

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

  echo "❌  Não foi possível determinar o IP público da VPS."
  echo "➡️  Verifique sua conexão de rede ou tente novamente mais tarde."
  exit 1
}

validate_domain() {
  local var_name="$1"
  local domain="${!var_name}"
  local vps_ip
  vps_ip=$(get_public_ip)

  while true; do
    # Resolve o IP do domínio
    local resolved_ip
    resolved_ip=$(dig +short "$domain" | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

    if [[ -z "$resolved_ip" ]]; then
      echo "❌ O domínio '$domain' não existe ou não possui um IP atribuído."
    elif [[ "$resolved_ip" != "$vps_ip" ]]; then
      echo "❌ O domínio '$domain' está apontando para $resolved_ip, mas deveria apontar para $vps_ip."
    else
      # Domínio válido, variável já está corretamente atribuída
      return 0
    fi

    # Pergunta se o usuário quer tentar novamente
    if gum confirm "Deseja informar o domínio novamente?"; then
      new_domain=$(gum input --placeholder "🌐 Digite o domínio novamente (ex: api.zapi.dev.br)" --placeholder.foreground 15)

      # Atualiza a variável com o novo domínio
      export "$var_name=$new_domain"
      domain="$new_domain"
    else
      echo "❌ Validação do domínio falhou. Abortando."
      exit 1
    fi
  done
}

# Função para validar a conexão e autenticação SMTP
validate_smtp() {
  local smtp_host="$1"
  local smtp_port="$2"
  local smtp_user="$3"
  local smtp_pass="$4"
  local smtp_email="$5"

  echo "🔍 Testando servidor SMTP com STARTTLS..."
  swaks --to "$smtp_email" \
    --server "$smtp_host" \
    --port "$smtp_port" \
    --auth LOGIN \
    --auth-user "$smtp_user" \
    --auth-password "$smtp_pass" \
    --tls \
    --quit-after RCPT

  if [ $? -eq 0 ]; then
    echo "✅ Validação com STARTTLS bem-sucedida."
    return 0
  fi

  echo "🔍 Tentando validação sem STARTTLS..."
  swaks --to "$smtp_email" \
    --server "$smtp_host" \
    --port "$smtp_port" \
    --auth LOGIN \
    --auth-user "$smtp_user" \
    --auth-password "$smtp_pass" \
    --quit-after RCPT

  if [ $? -eq 0 ]; then
    echo "✅ Validação sem STARTTLS bem-sucedida."
    return 0
  fi

  echo "❌ Falha na validação do servidor SMTP."
  return 1
}

# Função para configurar vm.max_map_count
configure_vm_max_map_count() {
  printf "${CYAN}⚠️  Configurando vm.max_map_count para 1677720...${NC}\n"
  # Verificar se a linha já existe e substituí-la, se necessário, ou adicioná-la
  if grep -q "vm.max_map_count" /etc/sysctl.conf; then
    sudo sed -i 's/^vm.max_map_count.*/vm.max_map_count=1677720/' /etc/sysctl.conf
  else
    echo 'vm.max_map_count=1677720' | sudo tee -a /etc/sysctl.conf >/dev/null
  fi
  # Aplicar a mudança
  sudo sysctl -p
  printf "${GREEN}✔️ vm.max_map_count configurado com sucesso!${NC}\n"
}
configure_vm_max_map_count

# Funcao para criar alias
add_alias() {
  local alias_line="$1"
  local alias_name=$(echo "$alias_line" | cut -d'=' -f1)
  local bashrc="${HOME}/.bashrc"

  if ! grep -qF "$alias_name" "$bashrc"; then
    echo "$alias_line" >>"$bashrc"
    echo "Alias $alias_name adicionado ao $bashrc"
  else
    echo "Alias $alias_name já existe no $bashrc"
  fi
}

# Obtém o tamanho atual do terminal
linhas=$(tput lines)
colunas=$(tput cols)

# Calcula a largura máxima para os elementos
largura_maxima=$((colunas - 10))
[ $largura_maxima -lt 50 ] && largura_maxima=50 # Define uma largura mínima

# Markdown content com espaçamento extra entre os itens enumerados
markdown_content="
# Bem-vindo à **Smile API** 😊

Este assistente irá configurar todo o ambiente necessário para sua plataforma, incluindo:

- Criação de um cluster Kubernetes.
- Deploy de micro-serviços essenciais.

## ⚠️ Pré-requisitos obrigatórios

Antes de continuar, verifique se você atende aos requisitos abaixo:

1. **Servidor Ubuntu** devidamente configurado e acessível.

   &nbsp;
   &nbsp;

2. **Três subdomínios apontando para o IP da VPS**:

   - **Domínio principal**: Para acessar o site e painel da plataforma (ex.: wappi.io).

   - **Domínio para documentação da API**: Ex.: api.wappi.io.

   - **Domínio para backend**: Ex.: backend.wappi.io.

   &nbsp;

3. **Conta no Gateway de Pagamentos AsaaS**:

   - Um token de acesso gerado para permitir a assinatura de planos e processar pagamentos.

   &nbsp;

4. **Servidor de e-mail SMTP**:

   - Necessário para o envio de e-mails, como validação de cadastros de usuários.

   - Credenciais obrigatórias:

     - **Host**: Endereço do servidor SMTP.
     - **Porta**: Porta de comunicação do SMTP.
     - **Usuário**: Nome de usuário do servidor SMTP.
     - **Senha**: Senha do servidor SMTP.
     - **E-mail de envio**: Endereço usado como remetente.

     &nbsp;

5. **CAPTCHA - Turnstile da Cloudflare**:

  - A plataforma utiliza o Turnstile da Cloudflare como solução de CAPTCHA para proteger formulários e garantir a segurança contra bots.

    - Para configurá-lo, você precisará:
       - Acessar sua conta na Cloudflare.
       - Entrar na opcao Turnstile e adicionar o domínio principal da plataforma (ex.: wappi.io).
       - Gerar as seguintes chaves:
        - **Site Key**: Chave pública que será usada no frontend da aplicação.
        - **Secret Key**: Chave privada que será usada no backend para validação.
---

## ✅ Certifique-se de atender a todos os requisitos antes de prosseguir.
"

# Renderizando o markdown e aplicando a borda com largura responsiva
echo "$markdown_content" | gum format | gum style \
  --border double \
  --padding "1 3" \
  --margin "1 2" \
  --align left \
  --border-foreground 57 \
  --foreground 15 \
  --bold \
  --width $largura_maxima

# Pergunta se o usuário já atendeu a todos os requisitos, e se responder "Não", o script sai com exit 0
gum confirm "Você já atendeu a todos os requisitos mencionados acima?" || exit 0

# Coleta de informações com validação
export FRONTEND_URL=$(gum input --placeholder "🌐 Informe o domínio principal usado para acessar o site (ex: wappi.io)" --placeholder.foreground 15)
validar_input FRONTEND_URL "🌐 Informe o domínio principal usado para acessar o site (ex: wappi.io)"
validate_domain FRONTEND_URL
export FRONTEND_URL

export PUBLIC_API_URL=$(gum input --placeholder "🌐 Informe o subdomínio usado para acessar a documentação da API (ex: api.wappi.io)" --placeholder.foreground 15)
validar_input PUBLIC_API_URL "🌐 Informe o subdomínio usado para acessar a documentação da API (ex: api.wappi.io)"
validate_domain PUBLIC_API_URL
export PUBLIC_API_URL
export VITE_PUBLIC_API_URL="$PUBLIC_API_URL"

export VITE_BACKEND_URL=$(gum input --placeholder "🌐 Informe o subdomínio usado no backend da API (ex: backend.wappi.io)" --placeholder.foreground 15)
validar_input VITE_BACKEND_URL "🌐 Informe o subdomínio usado no backend da API (ex: backend.wappi.io)"
validate_domain VITE_BACKEND_URL
export VITE_BACKEND_URL

# Loop de entrada e validação SMTP
while true; do
  # Solicitação dos dados do usuário
  export SMTP_HOST=$(gum input --placeholder "📧 Endereço do servidor SMTP" --placeholder.foreground 15)
  validar_input SMTP_HOST "📧 Endereço do servidor SMTP"

  export SMTP_PORT=$(gum input --placeholder "📧 Porta do servidor SMTP" --placeholder.foreground 15)
  validar_input SMTP_PORT "📧 Porta do servidor SMTP"

  export SMTP_USER=$(gum input --placeholder "📧 Usuário SMTP" --placeholder.foreground 15)
  validar_input SMTP_USER "📧 Usuário SMTP"

  export SMTP_PASS=$(gum input --placeholder "🔑 Senha SMTP" --placeholder.foreground 15)
  validar_input SMTP_PASS "🔑 Senha SMTP"

  export SMTP_EMAIL=$(gum input --placeholder "📧 Email de envio SMTP" --placeholder.foreground 15)
  validar_input SMTP_EMAIL "📧 Email de envio SMTP"

  # Validação SMTP
  validate_smtp "$SMTP_HOST" "$SMTP_PORT" "$SMTP_USER" "$SMTP_PASS" "$SMTP_EMAIL"

  if [ $? -eq 0 ]; then
    echo "✅ Todos os dados do servidor SMTP foram validados com sucesso!"
    break
  else
    if gum confirm "Os dados estão incorretos. Deseja informar os dados novamente?"; then
      continue
    else
      echo "❌ Operação abortada pelo usuário."
      exit 1
    fi
  fi
done

export ASAAS_URL=$(gum input --placeholder "💳 URL do gateway Asaas (ex: https://asaas.com ou https://sandbox.asaas.com)" --placeholder.foreground 15)
validar_input ASAAS_URL "💳 URL do gateway Asaas (ex: https://asaas.com ou https://sandbox.asaas.com)"

export ASAAS_ACCESS_TOKEN=$(gum input --placeholder "🔑 Token de acesso Asaas" --placeholder.foreground 15)
validar_input ASAAS_ACCESS_TOKEN "🔑 Token de acesso Asaas"

export VITE_RECAPTCHA_SITE_KEY=$(gum input --placeholder "🔑 SiteKey do Turnstile para CAPTCHA" --placeholder.foreground 15)
validar_input VITE_RECAPTCHA_SITE_KEY "🔑 SiteKey do Turnstile para CAPTCHA"

export RECAPTCHA_SECRET_KEY=$(gum input --placeholder "🔑 SecretKey do Turnstile para CAPTCHA" --placeholder.foreground 15)
validar_input RECAPTCHA_SECRET_KEY "🔑 SecretKey do Turnstile para CAPTCHA"
# Mensagem final com as informações coletadas
gum style --foreground 34 --bold \
  "Tudo pronto! 🎉 Suas informações foram validadas:
A configuração da sua API começará em breve."

sudo apt-get update
sudo apt install -y snapd
sudo apt-get install sshpass
sudo snap install microk8s --classic
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube
sudo apt install swaks -y

add_alias "alias kubectl='microk8s kubectl'"
add_alias "alias k='microk8s kubectl'"

microk8s enable dns
microk8s enable metrics-server
microk8s enable observability
microk8s kubectl create namespace infra
microk8s enable cert-manager
microk8s enable ingress
microk8s enable helm3
microk8s helm repo add bitnami https://charts.bitnami.com/bitnami
microk8s helm repo update

# Criar ClusterIssuer para produção
microk8s kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    email: seu-email@gmail.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
    - http01:
        ingress:
          class: public
EOF

microk8s kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: api-certificate
  namespace: default
spec:
  secretName: api-tls-secret
  issuerRef:
    name: letsencrypt
    kind: ClusterIssuer
  commonName: ${FRONTEND_URL}
  dnsNames:
    - ${FRONTEND_URL}
    - ${PUBLIC_API_URL}
    - ${VITE_BACKEND_URL}
EOF

# deploy rabbitmq
microk8s helm install rabbitmq-cluster bitnami/rabbitmq \
  --set image.tag=3.13 \
  --set communityPlugins="https://github.com/rabbitmq/rabbitmq-delayed-message-exchange/releases/download/v3.13.0/rabbitmq_delayed_message_exchange-3.13.0.ez" \
  --set extraPlugins="rabbitmq_delayed_message_exchange" \
  --set replicaCount=1 \
  --set auth.username=admin \
  --set auth.password=admin \
  --set persistence.enabled=true \
  --set persistence.size=5Gi \
  --set service.type=NodePort \
  --set service.externalIPs[0]=$(hostname -I | awk '{print $1}') \
  --set service.nodePorts.amqp=30072 \
  --set service.nodePorts.dist=30073 \
  --set service.nodePorts.management=30074 \
  --namespace infra --create-namespace

gum style --foreground 6 "Aguardando RabbitMQ ficar com status Ready..."
if gum spin --title "Isso pode levar alguns minutos" -- microk8s kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=rabbitmq -n infra --timeout=600s; then
  gum style --foreground 2 "RabbitMQ deployado com sucesso 🚀..."
else
  gum style --foreground 1 "Falha no deploy do RabbitMQ 😞..."
fi

# deploy redis
microk8s helm install redis-server bitnami/redis \
  --set master.persistence.size=2Gi \
  --set replica.replicaCount=1 \
  --set auth.enabled=false \
  --set master.service.type=NodePort \
  --set-string master.service.nodePorts.redis='30007' \
  --set master.service.externalIPs[0]=$(hostname -I | awk '{print $1}') \
  --namespace infra \
  --create-namespace

gum style --foreground 6 "Aguardando Redis ficar com status Ready..."
if gum spin --title "Isso pode levar alguns minutos" -- microk8s kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n infra --timeout=300s; then
  gum style --foreground 2 "Redis deployado com sucesso 🚀..."
else
  gum style --foreground 1 "Falha no deploy do Redis 😞..."
fi

microk8s kubectl create secret generic spa-backend-secrets \
  --from-literal=RECAPTCHA_SECRET_KEY=$RECAPTCHA_SECRET_KEY \
  --from-literal=JWT_SECRET="$(openssl rand -base64 66)" \
  --from-literal=ASAAS_ACCESS_TOKEN=$ASAAS_ACCESS_TOKEN \
  --from-literal=SMTP_PASS=$SMTP_PASS

# cria pvc para armazenamento em disco
cat <<EOF | microk8s kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
EOF

# aplicar secrets
microk8s kubectl apply -f https://gitlab.com/eduardo-policarpo/deployments/-/raw/main/manifests/secrets/gitlab-registry.yaml?ref_type=heads

# deploy spa-backend
curl -s https://gitlab.com/eduardo-policarpo/deployments/-/raw/main/manifests/kubernetes/spa-backend.yaml?ref_type=heads >spa-backend.yaml
envsubst <spa-backend.yaml | microk8s kubectl apply -f -
gum style --foreground 6 "Aguardando deploy do microservice spa-backend..."
if gum spin --title "Isso pode levar alguns minutos" -- microk8s kubectl wait --for=condition=ready pod -l app=spa-backend --timeout=300s; then
  gum style --foreground 2 "spa-backend deployed com sucesso 🚀..."
else
  gum style --foreground 1 "Falha no deploy do spa-backend 😞..."
fi
rm spa-backend.yaml

# deploy spa-frontend
curl -s https://gitlab.com/eduardo-policarpo/deployments/-/raw/main/manifests/kubernetes/spa-frontend.yaml?ref_type=heads >spa-frontend.yaml
envsubst <spa-frontend.yaml | microk8s kubectl apply -f -
gum style --foreground 6 "Aguardando deploy do microservice spa-frontend..."
if gum spin --title "Isso pode levar alguns minutos" -- microk8s kubectl wait --for=condition=ready pod -l app=spa-frontend --timeout=300s; then
  gum style --foreground 2 "spa-frontend deployed com sucesso 🚀..."
else
  gum style --foreground 1 "Falha no deploy do spa-frontend 😞..."
fi
rm spa-frontend.yaml

# deploy api-server
curl -s https://gitlab.com/eduardo-policarpo/deployments/-/raw/main/manifests/kubernetes/api-service.yaml?ref_type=heads >api-service.yaml
envsubst <api-service.yaml | microk8s kubectl apply -f -
gum style --foreground 6 "Aguardando deploy do microservice api-service..."
if gum spin --title "Isso pode levar alguns minutos" -- microk8s kubectl wait --for=condition=ready pod -l app=api-service --timeout=300s; then
  gum style --foreground 2 "api-service deployed com sucesso 🚀..."
else
  gum style --foreground 1 "Falha no deploy do api-service 😞..."
fi
rm api-service.yaml

cat <<EOF | microk8s kubectl apply -f -
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 2000000
globalDefault: false
description: "Prioridade alta para aplicações críticas"
EOF

# svc para workers
cat <<EOF | microk8s kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: worker-svc
spec:
  selector:
    app: worker
  ports:
    - name: http
      protocol: TCP
      port: 3001
      targetPort: 3001
  type: ClusterIP
EOF

# Ingress Controller
microk8s kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  rules:
    - host: ${FRONTEND_URL}
      http:
        paths:
          - path: /webhook
            pathType: Prefix
            backend:
              service:
                name: spa-backend-svc
                port:
                  number: 3000
          - path: /
            pathType: Prefix
            backend:
              service:
                name: spa-frontend-svc
                port:
                  number: 80
    - host: ${PUBLIC_API_URL}
      http:
        paths:
          - path: /media
            pathType: Prefix
            backend:
              service:
                name: worker-svc
                port:
                  number: 3001
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-service-svc
                port:
                  number: 3000
    - host: ${VITE_BACKEND_URL}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: spa-backend-svc
                port:
                  number: 3000                  
  tls:
    - hosts:
        - ${FRONTEND_URL}
        - ${PUBLIC_API_URL}
        - ${VITE_BACKEND_URL}
      secretName: api-tls-secret
EOF

# exportar kubeconfig
microk8s config >kubeconfig.yaml

gum style --foreground 10 --bold \
  "INSTALAÇÃO CONCLUÍDA COM SUCESSO! 🚀🚀🚀" && echo

gum style --foreground 255 --bold --border double --padding "1 2" \
  "
🛠️ **Acesse o Painel de Gerenciamento com as credenciais de administrador:**
👉 https://${FRONTEND_URL}/login
📧 Login:    admin@admin.com  
🔒 Senha:    admin123  

⚠️ **IMPORTANTE:** 
- Altere a senha imediatamente após o login para garantir a segurança.
- Não compartilhe estas credenciais, pois elas concedem acesso total à plataforma.
" && echo

gum style --foreground 255 --bold \
  "Próximos Passos:" && echo

# Configuração do domínio no ASaaS
gum style --foreground 15 \
  "1️⃣ **Configurar o domínio no ASaaS**" && echo
gum style --foreground 7 \
  " - Acesse o link: https://sandbox.asaas.com/config/index" && echo
gum style --foreground 7 \
  " - No campo **Site**, defina o valor como:" && echo
gum style --foreground 10 --bold \
  "  👉 https://${FRONTEND_URL}" && echo && echo

# Configuração do webhook no ASaaS
gum style --foreground 15 \
  "2️⃣ **Configurar o Webhook no ASaaS**" && echo
gum style --foreground 7 \
  " - Acesse o link: https://sandbox.asaas.com/customerConfigIntegrations/webhooks" && echo
gum style --foreground 7 \
  " - Preencha os campos conforme abaixo:" && echo
gum style --foreground 7 --bold \
  "  - **URL do Webhook**: 👉 https://${FRONTEND_URL}/webhook" && echo
gum style --foreground 7 --bold \
  "  - **Versão da API**: 👉 v3" && echo
gum style --foreground 7 --bold \
  "  - **Tipo de Envio**: 👉 Não sequencial" && echo
gum style --foreground 7 --bold \
  "  - **Eventos**: Selecione todos os eventos relacionados a cobranças (use o botão **Selecionar Todos**)." && echo && echo

# Acesso ao cluster
gum style --foreground 15 \
  "3️⃣ **Acesso ao Cluster**" && echo
gum style --foreground 7 \
  " - O arquivo de configuração do cluster foi gerado com o nome kubeconfig.yaml." && echo
gum style --foreground 7 \
  " - Para visualizar o conteúdo do arquivo, execute o comando:" && echo
gum style --foreground 10 --bold \
  "  👉 cat kubeconfig.yaml" && echo && echo

# Ferramenta Lens Desktop
gum style --foreground 15 \
  "💡 **Ferramenta Recomendada: Lens Desktop**" && echo
gum style --foreground 7 \
  " - Baixe a ferramenta Lens Desktop: https://k8slens.dev/" && echo
gum style --foreground 7 \
  " - Com o Lens Desktop, você pode usar o arquivo kubeconfig.yaml para gerenciar o cluster." && echo
gum style --foreground 7 \
  " - Basta importar o arquivo na ferramenta para começar a explorar o cluster com facilidade." && echo && echo

# Mensagem final
gum style --foreground 255 --bold \
  "✅ **Parabéns! O ambiente está configurado e pronto para uso.**" && echo
gum style --foreground 15 \
  "Em caso de dúvidas, consulte a documentação ou entre em contato com o suporte."

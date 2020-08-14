# whatsapp-api
API para envio de mensagens via whatsapp utilizando Venom-bot

Projeto utiliza o Venom para envio de Mensagens e a biblioteca Express para criação de servidor HTTP
Repositório do Venom-bot pode ser encontrado no Github https://github.com/orkestral/venom

Para utilizar basta abrir o navegador em http://IP-do-seu-servidor/api?celular=numero-que-vai-enviar&mensagem=texto-da-mensagem

O numero do celular deve ser colocado com DDD e sem o nono digito
    
Para instalar em Linux:

sudo apt install -y gconf-service libasound2 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgcc1 
libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 
libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates 
fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils wget build-essential apt-transport-https libgbm-dev

Para instalar todas as dependencias necessárias no sistema
curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -

sudo apt install git nodejs yarn


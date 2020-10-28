const express = require('express');
const venom = require('venom-bot');
const app = express();

venom.create(
  'API-Whatsapp', 
    
    (base64Qrimg, asciiQR, attempts) => {
      console.log('Number of attempts to read the qrcode: ', attempts);
      console.log('Terminal qrcode: ', asciiQR);
      console.log('base64 image string qrcode: ', base64Qrimg);
    },
     (statusSession, session) => {
      console.log('Status Session: ', statusSession); 
      console.log('Session name: ', session);
    },
    {
      browserArgs: ['--no-sandbox'],
      disableWelcome: true,
    })
  .then((client) => start(client))
  .catch((erro) => {
    console.log(erro);
  });


function start(client){
  app.listen(3000, function(){
    console.log("Servidor Iniciado e escutando na porta 3000");
  });
  app.get('/', (req, res) => {
    res.sendFile(__dirname + "/html/index.html");
  })
  app.get("/api", async function(req,res,next){
    await client.sendText('55'+ req.query.celular + '@c.us', req.query.mensagem);
    res.json(req.query);
  })
  client.onStateChange((state) => {
    console.log('State changed: ', state);
    if ('CONFLICT'.includes(state)) client.useHere();
    if ('UNPAIRED'.includes(state)) console.log('logout');
  });
}

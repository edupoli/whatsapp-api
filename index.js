const express = require('express');
const venom = require('venom-bot');
const app = express();

const parameters = {
    headless: true, 
    devtools: false,
    useChrome: false,
    debug: false,
    logQR: true,
    browserArgs: ['--no-sandbox'],
    refreshQR: 15000,
    autoClose: 60000,
    disableSpins: true,
  };
  venom.create('sessao', async (base64Qr, asciiQR) => {
      console.log('exportando qrcode');
  }, (statusFind) =>{
      console.log(statusFind)
  }, parameters).then((client) => start(client));
  

    function start(client){
        app.listen(3000, function(){
        console.log("Servidor Iniciado e escutando na porta 3000");
    });

    app.get('/', (req, res) => {
        res.sendFile(__dirname + "/html/index.html");
      })

    app.get("/api", async function(req,res,next){
        await client.sendMessageToId('55'+ req.query.celular + '@c.us', req.query.mensagem);
        res.json(req.query);
    })

client.onStateChange((state) => {
    console.log(state);
    const conflits = [
      venom.SocketState.CONFLICT,
      venom.SocketState.UNPAIRED,
      venom.SocketState.UNLAUNCHED,
    ];
    if (conflits.includes(state)) {
      client.useHere();
    }
  });
}
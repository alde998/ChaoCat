// Real extension-host authentication check that does not require window focus.
const vscode=require('vscode');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const http=require('node:http');
const os=require('node:os');
const path=require('node:path');

exports.run=async()=>{
  const extension=vscode.extensions.getExtension('local-dev.chaos-cat');
  assert.ok(extension);await extension.activate();
  const port=Number(process.env.CHAOS_CAT_PORT);
  const tokenFile=process.env.CHAOS_CAT_BRIDGE_TOKEN_FILE||path.join(os.tmpdir(),`chaos-cat-bridge-${process.getuid()}-${port}.token`);
  const token=(await fs.readFile(tokenFile,'utf8')).trim();
  const send=(event)=>new Promise((resolve,reject)=>{
    const request=http.request({hostname:'127.0.0.1',port,path:'/api/events?limit=250',method:event?'POST':'GET',headers:{'x-chaos-cat-token':token}},response=>{
      let body='';response.on('data',chunk=>body+=chunk);response.on('end',()=>{
        try {assert.equal(response.statusCode,200);resolve(JSON.parse(body))}catch(error){reject(error)}
      });
    });
    request.on('error',reject);
    request.end(event?JSON.stringify(event):undefined);
  });
  const events=async()=>(await send()).events;
  let diagnostic,received;
  const deadline=Date.now()+10000;
  while(Date.now()<deadline){
    diagnostic=await vscode.commands.executeCommand('chaosCat.diagnostics');
    received=await events();
    if(diagnostic.bridgeOnline&&diagnostic.actorOnline&&received.some(e=>e.type==='client.hello'&&e.payload.clientId===diagnostic.clientId))break;
    await new Promise(resolve=>setTimeout(resolve,250));
  }
  assert.equal(diagnostic.bridgeOnline,true,'extension receives authenticated bridge events');
  assert.equal(diagnostic.actorOnline,true,'extension receives native app state');
  assert.ok(received.some(e=>e.type==='client.hello'&&e.payload.clientId===diagnostic.clientId),'extension posts authenticated heartbeat');
  await vscode.commands.executeCommand('chaosCat.calm');
  received=await events();
  assert.ok(received.some(e=>e.type==='pet.actionRequested'&&e.payload.clientId===diagnostic.clientId&&e.payload.action==='calm'),'menu command posts an authenticated event');
  // Exercise real editor edits without requiring OS foreground focus. Cleanup
  // must preserve the literal already present in this same document.
  const original='const example = "/shit/";\n';
  const doc=await vscode.workspace.openTextDocument({content:original,language:'javascript'});
  await vscode.window.showTextDocument(doc,{preview:false});
  const requestId='auth-test-insert-'+Date.now();
  await send({source:'macos-overlay',type:'behavior.request',payload:{target:diagnostic.clientId,requestId,operation:'poop.create',issuedAt:Date.now(),anchor:{uri:doc.uri.toString()}}});
  const insertionDeadline=Date.now()+5000;
  while(doc.getText()===original&&Date.now()<insertionDeadline)await new Promise(resolve=>setTimeout(resolve,80));
  const inserted=doc.getText();
  assert.equal(inserted.split('/shit/').length-1,2,'authenticated behavior inserts one marker');
  await vscode.commands.executeCommand('chaosCat.clearEffects');
  assert.equal(doc.getText(),original,'cleanup removes only owned markers');
  await fs.writeFile(path.resolve(__dirname,'../docs/vscode-auth-host-validation.json'),JSON.stringify({passed:true,host:vscode.version,extensionVersion:extension.packageJSON.version,checks:['extension authenticated heartbeat','extension reads native state','extension command posts authenticated event','real authenticated marker insertion','cleanup preserves user-authored literals in the same document']},null,2)+'\n');
  console.log('PASS: real VS Code extension host and native app authenticate in both directions');
};

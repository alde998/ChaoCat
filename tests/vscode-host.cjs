// Runs inside VS Code's real extension host, not a mock of its API.
const vscode=require('vscode');
const assert=require('node:assert/strict');
const fsSync=require('node:fs');
const fs=require('node:fs/promises');
const path=require('node:path');
const os=require('node:os');
const http=require('node:http');
const root=path.resolve(__dirname,'..');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const evidence=[],seen=new Set();let state,client;
const tokenFile=process.env.CHAOS_CAT_BRIDGE_TOKEN_FILE||path.join(os.tmpdir(),`chaos-cat-bridge-${typeof process.getuid==='function'?process.getuid():'user'}-${Number(process.env.CHAOS_CAT_PORT)||44777}.token`);
const bridgeToken=()=>{try{return (process.env.CHAOS_CAT_BRIDGE_TOKEN||fsSync.readFileSync(tokenFile,'utf8')).trim()}catch{return ''}};
function request(method,body){return new Promise((resolve,reject)=>{
 const r=http.request({hostname:'127.0.0.1',port:Number(process.env.CHAOS_CAT_PORT),path:'/api/events?limit=250',method,headers:{'content-type':'application/json','x-chaos-cat-token':bridgeToken()}},res=>{let s='';res.on('data',d=>s+=d);res.on('end',()=>{try{resolve(JSON.parse(s))}catch(e){reject(e)}})});
 r.on('error',reject);r.end(body?JSON.stringify(body):undefined);
});}
async function poll(){for(const e of (await request('GET')).events){if(seen.has(e.id))continue;seen.add(e.id);if(e.type==='behavior.state')state=e.payload;if(['behavior.request','behavior.response','editor.textChanged','cleanup.requested','cleanup.completed'].includes(e.type))evidence.push(e);}}
async function until(fn,label,ms=45000){let began=Date.now();while(true){await poll();if(await fn())return;assert.ok(Date.now()-began<ms,`${label}; last state ${JSON.stringify(state)}`);await delay(80);}}
async function action(action){await request('POST',{source:'vscode-extension',type:'pet.actionRequested',payload:{clientId:client,protocol:2,action,active:true}});}
exports.run=async()=>{
 let doc,fixtureDirectory,firstChaseEnded=0;
 try{
  const ext=vscode.extensions.getExtension('local-dev.chaos-cat');assert.ok(ext,'real development extension installed');await ext.activate();
  const original=Array.from({length:18},(_,i)=>`const fixture${i} = ${i};`).join('\n')+'\n';
  fixtureDirectory=await fs.mkdtemp(path.join(os.tmpdir(),'chaos-cat-real-code-'));
  const fixturePath=path.join(fixtureDirectory,'fixture.js');
  await fs.writeFile(fixturePath,original);
  doc=await vscode.workspace.openTextDocument(vscode.Uri.file(fixturePath));
  const editor=await vscode.window.showTextDocument(doc,{preview:false});
  await until(()=>vscode.window.state.focused,'VS Code must have focus; unlock the Mac to run this UI test');
  await until(()=>evidence.some(e=>e.type==='behavior.response')||state?.editorClient,'native actor selected real editor');client=state.editorClient;
  assert.match(client,/^vscode-extension:/);assert.equal(state.build,'20261014.6');
  await vscode.commands.executeCommand('chaosCat.triggerPoop');
  await until(()=>doc.getText().split('/shit/').length-1===3&&state.mode==='walk','3 real poop insertions');
  assert.equal(doc.getText().replaceAll('/shit/',''),original);
  assert.ok(doc.isDirty,'real document must be modified');
  assert.equal(doc.languageId,'javascript');
  assert.equal(doc.getText().match(/\/shit\//g).length,3);
  const insertedText=doc.getText();
  // Each poop is a normal independent edit; it must not absorb previous typing.
  await vscode.commands.executeCommand('undo');
  await until(()=>doc.getText().split('/shit/').length-1===2,'undo one poop marker');
  assert.equal(doc.getText().replaceAll('/shit/',''),original);
  await vscode.commands.executeCommand('redo');
  await until(()=>doc.getText()===insertedText,'redo one poop marker');
  const clickedOffset=doc.getText().indexOf('/shit/')+2;
  editor.selection=new vscode.Selection(doc.positionAt(clickedOffset),doc.positionAt(clickedOffset));
  await delay(250);
  assert.equal(doc.getText(),insertedText,'programmatic cursor movement must not delete text');
  const hovers=await vscode.commands.executeCommand('vscode.executeHoverProvider',doc.uri,doc.positionAt(clickedOffset));
  assert.ok(!hovers.some(h=>h.contents.some(c=>c.value?.includes('删除这个 /shit/'))),'no deletion hover is provided');
  const links=await vscode.commands.executeCommand('vscode.executeLinkProvider',doc.uri);
  assert.ok(!links.some(l=>l.target?.scheme==='command'&&l.target.path==='chaosCat.removePoopLink'),'no deletion link is provided');
  assert.equal(await vscode.commands.executeCommand('chaosCat.removePoopAtCursor'),true);
  assert.equal(doc.getText().split('/shit/').length-1,2,'single deletion removes exactly one marker');
  const secondOffset=doc.getText().indexOf('/shit/')+2;
  editor.selection=new vscode.Selection(doc.positionAt(secondOffset),doc.positionAt(secondOffset));
  await delay(100);
  await vscode.commands.executeCommand('chaosCat.removePoopAtCursor');
  assert.equal(doc.getText().split('/shit/').length-1,1,'explicit cursor command deletes one marker');
  const afterSingleDelete=doc.getText();
  // Undo is a genuine document-change event and can trigger chasing; finish it
  // before issuing the next action, just as the live editor does.
  await until(()=>state.mode==='bug','undo is a real editor event');
  await until(()=>state.mode==='walk','finish chase triggered by undo',22000);firstChaseEnded=Date.now();
  assert.ok(await doc.save());assert.equal(await fs.readFile(fixturePath,'utf8'),afterSingleDelete);
  await vscode.commands.executeCommand('chaosCat.triggerBury');
  await until(()=>doc.getText()===original&&state.mode==='walk','burial restored real editor document');
  assert.ok(await doc.save());assert.equal(await fs.readFile(fixturePath,'utf8'),original);
  await vscode.commands.executeCommand('chaosCat.triggerBoxDive');
  await until(()=>state.clip.startsWith('rubbish-tail')&&doc.getText().includes('/rubbish/ /rubbish/'),'real rubbish-filled base and tail loop');
  const rubbishText=doc.getText().match(/\/rubbish\//g)||[];
  assert.ok(rubbishText.length>=35,'rubbish displacement spans the heap overlay area');
  assert.ok(doc.getText().split('\n').filter(line=>line.includes('/rubbish/')).length>=7,'rubbish displacement uses multiple editor lines');
  // Edit while the pile exists. Cleanup must retain this independent change.
  await editor.edit(e=>e.insert(new vscode.Position(0,0),'user edit\n'));
  await action('scatter');
  await until(()=>!doc.getText().includes('/rubbish/'),'rubbish cleanup after release');
  assert.equal(doc.getText(),'user edit\n'+original);
  const interruptionPoops=doc.getText().match(/\/shit\//g)?.length||0;
  await action('poopChaos');await until(()=>state.mode==='poop','poop start before interruption');
  await action('scatter');await until(()=>state.mode==='scared','real native frightened run');
  await until(()=>((doc.getText().match(/\/shit\//g)||[]).length)>=interruptionPoops+12,'interrupted poop scatters 12 real markers');
  assert.ok((doc.getText().match(/\/shit\//g)||[]).length>=interruptionPoops+12);
  await until(()=>state.mode==='walk','frightened run completes');
  const drops=evidence.filter(e=>e.type==='behavior.request'&&e.payload.operation==='poop.create'&&e.payload.random);
  assert.equal(drops.length,12,'one timed scatter sequence');
  assert.ok(drops.at(-1).payload.issuedAt-drops[0].payload.issuedAt>=120,'scatter must arrive over time, not as an entry burst');
  // The behavior policy keeps a 25 s cooldown after a chase; wait for that
  // contract instead of racing the final typing assertion.
  if(Date.now()-firstChaseEnded<26000)await delay(26000-(Date.now()-firstChaseEnded));
  await editor.edit(e=>e.insert(new vscode.Position(0,0),'typed '));
  await until(()=>state.mode==='bug','real editor change triggers cat chase');
  await until(()=>state.mode==='walk','insect timeout releases chase',22000);
  // Put generated markers in a second tab, close it, then clear from the first
  // tab. This covers the status menu broadcast and real multi-document edits.
  const secondPath=path.join(fixtureDirectory,'second.js'),secondOriginal='const second = 2;\n';
  await fs.writeFile(secondPath,secondOriginal);
  let second=await vscode.workspace.openTextDocument(vscode.Uri.file(secondPath));
  await vscode.window.showTextDocument(second,{preview:false});
  await vscode.commands.executeCommand('chaosCat.triggerPoop');
  await until(()=>second.getText().split('/shit/').length-1===3&&state.mode==='walk','second document poop');
  await second.save();await vscode.commands.executeCommand('workbench.action.closeActiveEditor');
  await vscode.window.showTextDocument(doc);
  await vscode.commands.executeCommand('chaosCat.triggerPoop');
  await until(()=>doc.getText().includes('/shit/'),'in-flight poop before immediate cleanup');
  const clearIndex=evidence.length,clearStart=Date.now();
  const untouched='Example documentation: /shit/ should remain here.';
  const unrelated=await vscode.workspace.openTextDocument({content:untouched,language:'plaintext'});
  await action('clear');
  await until(()=>evidence.slice(clearIndex).some(e=>e.type==='cleanup.completed'&&e.payload.ok),'native menu cleanup acknowledged',4000);
  second=await vscode.workspace.openTextDocument(vscode.Uri.file(secondPath));
  assert.equal(second.getText(),secondOriginal);assert.equal(doc.getText(),'typed user edit\n'+original);
  assert.equal(unrelated.getText(),untouched,'unrelated open documents must not be swept');
  assert.ok(Date.now()-clearStart<4000,'cleanup must not wait for burial animations');
  await delay(1500);await poll();assert.equal(doc.getText(),'typed user edit\n'+original);
  assert.ok(!evidence.slice(clearIndex).some(e=>e.type==='behavior.request'&&e.payload.operation==='poop.list'),'clear must bypass burial');
  // Reject an insertion that was issued before clear but delivered afterwards.
  const cutoff=evidence.slice(clearIndex).find(e=>e.type==='cleanup.requested').payload.cutoff;
  await request('POST',{source:'macos-overlay',type:'behavior.request',payload:{target:client,requestId:'stale-after-clear',operation:'poop.create',issuedAt:cutoff-1,anchor:{uri:doc.uri.toString()}}});
  await until(()=>evidence.some(e=>e.payload.requestId==='stale-after-clear'&&e.type==='behavior.response'),'stale request response');
  assert.equal(evidence.find(e=>e.payload.requestId==='stale-after-clear'&&e.type==='behavior.response').payload.reason,'cancelled-by-cleanup');
  assert.equal(doc.getText(),'typed user edit\n'+original);
  await doc.save();await second.save();assert.equal(await fs.readFile(secondPath,'utf8'),secondOriginal);
  // User-authored /shit/ text remains ordinary text, while a generated marker
  // is still removed by the extension's own clear command.
  await vscode.window.activeTextEditor.edit(e=>e.insert(new vscode.Position(0,0),'/shi/shit/t//shit/'));
  const userAuthoredText=doc.getText();
  await vscode.commands.executeCommand('chaosCat.triggerPoop');
  await until(()=>doc.getText().split('/shit/').length-1===userAuthoredText.split('/shit/').length-1+3,'generated markers before extension clear');
  await vscode.commands.executeCommand('chaosCat.clearEffects');
  assert.equal(doc.getText(),userAuthoredText);
  const responses=evidence.filter(e=>e.type==='behavior.response');
  assert.ok(responses.length>=14);assert.ok(responses.every(e=>e.payload.ok||e.payload.reason==='cancelled-by-cleanup'),JSON.stringify(responses.filter(e=>!e.payload.ok)));
  await fs.writeFile(path.join(root,'docs/vscode-host-validation.json'),JSON.stringify({passed:true,host:vscode.version,build:state.build,extensionVersion:ext.packageJSON.version,client,checks:['real editor input → native chase','3 /shit/ insertions in a JavaScript document','independent undo and redo of a marker','saved file contains literal /shit/ text','burial deletes each matching marker and saves clean file','rubbish displacement → discovery/run/jump/tail','release preserves concurrent edits','poop interruption → 12 scattered /shit/ markers plus frightened run','immediate cleanup across current and closed tabs','cleanup cancels in-flight poop and late insertion requests','extension clear command removes all legacy markers'],events:evidence},null,2)+'\n');
  console.log('PASS: real VS Code extension host and native actor integration');
 }catch(e){await fs.writeFile(path.join(root,'docs/vscode-host-failure.json'),JSON.stringify({error:e.stack,focused:vscode.window.state.focused,state,events:evidence},null,2)+'\n');throw e;}
 finally{if(doc){await vscode.window.showTextDocument(doc);await vscode.commands.executeCommand('workbench.action.revertAndCloseActiveEditor');}}
};

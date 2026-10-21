const vscode = require('vscode');
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { MarkerStore, poopRanges } = require('./markers.cjs');
const SOURCE='vscode-extension';
const BUILD='20261021.1';
const PORT=Number(process.env.CHAOS_CAT_PORT)||44777;
const CLIENT=SOURCE+':'+process.pid+':'+Math.random().toString(16).slice(2);
const TOKEN_FILE=process.env.CHAOS_CAT_BRIDGE_TOKEN_FILE||path.join(os.tmpdir(),`chaos-cat-bridge-${typeof process.getuid==='function'?process.getuid():'user'}-${PORT}.token`);
function bridgeToken() {
  try { return (process.env.CHAOS_CAT_BRIDGE_TOKEN||fs.readFileSync(TOKEN_FILE,'utf8')).trim(); } catch { return ''; }
}
// Keep the displacement as one marker, but shape it like a pile: seven rows
// and five columns cover more area than the 288x180 heap overlay.
const RUBBISH=Array.from({length:7},()=>Array(5).fill('/rubbish/').join(' ')).join('\n');
let context,store,poopDecoration,rubbishDecoration,status,output;
let bridgeOnline=false,lastFocused=0,lastEditor,actorMode='',actorClient='';
let polling=false,applying=false,queue=Promise.resolve(),lastInput=0,lastActor=0,started=Date.now();
let seen=new Set(),timers=[],restored=new Set();
let lastClearAt=0;
const docTexts=new Map();
function transport(method,event) {
  return new Promise((resolve,reject)=>{
    const req=http.request({hostname:'127.0.0.1',port:PORT,path:method==='GET'?'/api/events?limit=200':'/api/events',method,headers:{'content-type':'application/json','x-chaos-cat-token':bridgeToken()},timeout:1500},res=>{
      let data='';res.on('data',d=>data+=d);res.on('end',()=>{if(res.statusCode<200||res.statusCode>=300){reject(new Error(`bridge rejected request: ${res.statusCode}`));return}try{resolve(JSON.parse(data))}catch(e){reject(e)}});
    });
    req.on('timeout',()=>req.destroy(new Error('bridge timeout')));req.on('error',reject);
    req.end(event ? JSON.stringify(event):undefined);
  });
}
function post(type,payload={}) { return transport('POST',{type,source:SOURCE,payload:{...payload,clientId:CLIENT,protocol:2,build:BUILD},createdAt:new Date().toISOString()}).catch(()=>null); }
function activeEditor() {
  const e=vscode.window.state.focused ? vscode.window.activeTextEditor:undefined;
  if(e) { lastEditor=e;lastFocused=Date.now(); }
  return e;
}
function requestEditor(p) {
  const uri=p.anchor?.uri;
  // A targeted in-flight animation still belongs to this document after a
  // click on the native cat temporarily takes focus away from the editor.
  if(uri)return vscode.window.visibleTextEditors.find(e=>e.document.uri.toString()===uri);
  return activeEditor() || (Date.now()-lastFocused<120000?lastEditor:undefined);
}
function updateStatus() {
  const live=Date.now()-lastActor<4000;
  const linked=live&&actorClient===CLIENT;
  status.text=!bridgeOnline?'$(debug-disconnect) 小猫 · 桥接未连接':!live?'$(debug-disconnect) 小猫 · 桌宠未启动':linked?`$(hubot) 小猫 · 已联动 · ${actorMode}`:'$(hubot) 小猫 · 等待编辑器焦点';
  status.tooltip=`Chaos Cat ${BUILD}\n${CLIENT}\n点击查看联动诊断`;
}
function metrics(editor) {
  const c=vscode.workspace.getConfiguration('editor',editor.document.uri),fontSize=Number(c.get('fontSize'))||14;
  const configured=Number(c.get('lineHeight'))||0;
  return {fontSize,lineHeight:configured===0?Math.round(fontSize*1.5):configured<8?Math.round(fontSize*configured):configured,tabSize:Number(editor.options.tabSize)||4};
}
function anchor(editor,offset,id) {
  const doc=editor.document,p=doc.positionAt(offset),m=metrics(editor),v=editor.visibleRanges[0];
  let visualColumn=0;
  for(const ch of doc.lineAt(p.line).text.slice(0,p.character)) visualColumn+=ch==='\t'?m.tabSize-visualColumn%m.tabSize:/[\u1100-\u115f\u2e80-\ua4cf\uac00-\ud7a3\uff00-\uff60]/u.test(ch)?2:1;
  return {id,uri:doc.uri.toString(),editor:'vscode',fileName:path.basename(doc.fileName),version:doc.version,offset,line:p.line,character:p.character,visualColumn,...m,lineCount:doc.lineCount,visibleStartLine:v?.start.line??0,visibleEndLine:v?.end.line??doc.lineCount-1};
}
function markerAnchor(editor,r) { return {...anchor(editor,r.offset+Math.floor(r.text.length/2),r.id),kind:r.kind}; }
function pick(editor,payload) {
  const d=editor.document,v=editor.visibleRanges[0];
  const start=v?.start.line??0,end=Math.min(d.lineCount-1,v?.end.line??d.lineCount-1);
  const row=payload.random?start+Math.floor(Math.random()*(end-start+1)):Math.round(start+(end-start)*(payload.yRatio??0.5));
  const line=Math.min(end,Math.max(start,row)),text=d.lineAt(line).text;
  const char=payload.random?Math.floor(Math.random()*(text.length+1)):Math.round(text.length*(payload.xRatio??0.5));
  return insertionOffset(d,d.offsetAt(new vscode.Position(line,Math.max(0,Math.min(text.length,char)))));
}
function insertionOffset(doc,offset) {
  const text=doc.getText();
  const ranges=[...poopRanges(text),...store.forDocument(doc.uri.toString(),text,'rubbish').map(r=>({offset:r.offset,length:r.text.length}))];
  for(const r of ranges)if(offset>r.offset&&offset<r.offset+r.length)offset=r.offset+r.length;
  return offset;
}
function remember(doc) {
  const uri=doc.uri.toString();docTexts.set(uri,doc.getText());
  if(!restored.has(uri)){store.recover(uri,doc.getText());restored.add(uri);}
}
function save() { return context.workspaceState.update('behaviorMarkers.v2',store.snapshot(docTexts)); }
function render() {
  for(const editor of vscode.window.visibleTextEditors) {
    remember(editor.document);
    const records=store.forDocument(editor.document.uri.toString(),editor.document.getText());
    const ranges=kind=>records.filter((r,i)=>r.kind===kind&&!records.slice(0,i).some(other=>other.kind===r.kind&&other.offset===r.offset&&other.text===r.text)).map(r=>new vscode.Range(editor.document.positionAt(r.offset),editor.document.positionAt(r.offset+r.text.length)));
    editor.setDecorations(poopDecoration,ranges('poop'));editor.setDecorations(rubbishDecoration,ranges('rubbish'));
  }
}
async function insert(editor,offset,text,kind) {
  if(!editor || editor.document.isClosed) return null;
  offset=insertionOffset(editor.document,offset);
  applying=true;
  try {
    // The marker belongs to the actual document and gets its own undo step.
    const uri=editor.document.uri.toString(),ok=await editor.edit(edit=>edit.insert(editor.document.positionAt(offset),text),{undoStopBefore:true,undoStopAfter:true});
    if(!ok) return null;
    const r=store.add(uri,offset,text,kind);remember(editor.document);await save();render();return r;
  } finally {applying=false;}
}
async function remove(id) {
  const r=store.get(id);if(!r)return false;
  let doc=vscode.workspace.textDocuments.find(d=>d.uri.toString()===r.uri);
  if(!doc) { try {doc=await vscode.workspace.openTextDocument(vscode.Uri.parse(r.uri));remember(doc);}catch{return false;} }
  if(!store.verify(r,doc.getText())) {store.forget(id);await save();return false;}
  const edit=new vscode.WorkspaceEdit();edit.delete(doc.uri,new vscode.Range(doc.positionAt(r.offset),doc.positionAt(r.offset+r.text.length)));
  applying=true;
  try {const ok=await vscode.workspace.applyEdit(edit);if(ok)store.forget(id);remember(doc);await save();render();return ok;}
  finally {applying=false;}
}
function poopAt(document,offset) {
  const records=store.forDocument(document.uri.toString(),document.getText(),'poop');
  // Prefer the token under the caret at an adjacent-token boundary. The end
  // position also covers the after-decoration without touching nearby code.
  return records.find(r=>offset>=r.offset&&offset<r.offset+r.text.length)
    || records.find(r=>offset===r.offset+r.text.length);
}
function removePoopFromSelection(editor,selections) {
  if(!editor || selections.length!==1 || !selections[0].isEmpty)return Promise.resolve(false);
  // Resolve the stable marker ID now, before queued edits can shift offsets.
  const record=poopAt(editor.document,editor.document.offsetAt(selections[0].active));
  return record ? enqueue(()=>remove(record.id)) : Promise.resolve(false);
}
async function handle(p) {
  if(['poop.create','rubbish.create','target.pick'].includes(p.operation) && Number(p.issuedAt)<=lastClearAt)return {ok:false,reason:'cancelled-by-cleanup'};
  const editor=requestEditor(p);
  if(p.operation==='marker.remove')return {ok:await remove(p.id)};
  if(!editor)return {ok:false,reason:'no-active-editor'};
  remember(editor.document);
  if(p.operation==='target.pick') {
    const offset=pick(editor,p),r=store.add(editor.document.uri.toString(),offset,'','target');
    return {ok:true,anchor:{...anchor(editor,offset),targetId:r.id}};
  }
  if(p.operation==='rubbish.create'||p.operation==='poop.create') {
    let offset=pick(editor,p);
    if(p.anchor?.targetId) {
      const target=store.get(p.anchor.targetId);store.forget(p.anchor.targetId);
      if(!target || target.uri!==editor.document.uri.toString())return {ok:false,reason:'target-changed'};
      offset=target.offset;
    }
    const kind=p.operation==='rubbish.create'?'rubbish':'poop';
    const r=await insert(editor,offset,kind==='rubbish'?RUBBISH:'/shit/',kind);
    return r?{ok:true,id:r.id,anchor:markerAnchor(editor,r)}:{ok:false,reason:'edit-rejected'};
  }
  if(p.operation==='poop.list') {
    render();await save();
    return {ok:true,anchors:store.forDocument(editor.document.uri.toString(),editor.document.getText(),'poop').map(r=>markerAnchor(editor,r))};
  }
  if(p.operation==='marker.locate') {
    const r=store.get(p.id);
    return r && r.uri===editor.document.uri.toString() && store.verify(r,editor.document.getText())?{ok:true,anchor:markerAnchor(editor,r)}:{ok:false};
  }
  return {ok:false,reason:'unknown-operation'};
}
function enqueue(work) { queue=queue.then(work,work).catch(e=>{console.warn('Chaos Cat',e.message)});return queue; }
async function releaseRubbish() {
  for(const r of [...store.records].filter(r=>r.valid&&r.kind==='rubbish'))await remove(r.id);
}
async function clearAllPoop() {
  // Include closed tabs only when we own a marker in them. Literal /shit/
  // text and unverified records from older builds are never cleanup targets.
  const uris=new Set(store.records.filter(r=>r.valid&&r.owner==='chaos-cat'&&r.kind==='poop').map(r=>r.uri));
  const docs=[],failures=[];
  for(const uri of uris) {
    try {
      const doc=vscode.workspace.textDocuments.find(d=>d.uri.toString()===uri) || await vscode.workspace.openTextDocument(vscode.Uri.parse(uri));
      docs.push(doc);
    } catch {failures.push(uri);}
  }
  const edit=new vscode.WorkspaceEdit();let count=0;
  for(const doc of docs) {
    remember(doc);
    for(const marker of store.forDocument(doc.uri.toString(),doc.getText(),'poop')) {
      edit.delete(doc.uri,new vscode.Range(doc.positionAt(marker.offset),doc.positionAt(marker.offset+marker.text.length)));count+=1;
    }
  }
  applying=true;
  try {
    const ok=count===0 || await vscode.workspace.applyEdit(edit);
    if(ok) {
      const cleared=new Set(docs.map(d=>d.uri.toString()));
      store.records=store.records.filter(r=>!cleared.has(r.uri)||!['poop','target'].includes(r.kind));
      docs.forEach(remember);await save();render();
    }
    return {ok:ok&&failures.length===0,count:ok?count:0,failures};
  } finally {applying=false;}
}
async function cleanup(payload={}) {
  lastClearAt=Math.max(lastClearAt,Number(payload.cutoff)||Date.now());
  await releaseRubbish();
  const result=await clearAllPoop();
  output.appendLine(`Immediate cleanup: ${result.count} markers; ${result.ok?'OK':'incomplete'}`);
  await post('cleanup.completed',{...result,requestId:payload.requestId});heartbeat();
  if(!result.ok)vscode.window.showWarningMessage('部分屎标记未能清理，请检查文档是否只读或已经移动。');
  return result;
}
function heartbeat() {
  const e=activeEditor();if(e)lastFocused=Date.now();
  post('client.hello',{active:!!e,uri:e?.document.uri.toString()});updateStatus();if(!e)return;
  remember(e.document);post('editor.visibleRangesChanged',{...anchor(e,e.document.offsetAt(e.selection.active)),active:true});
  post('behavior.anchors',{active:true,anchors:store.forDocument(e.document.uri.toString(),e.document.getText()).filter(r=>r.kind!=='target').map(r=>markerAnchor(e,r))});
  if(lastActor && Date.now()-lastActor>5000) {lastActor=0;enqueue(releaseRubbish);}
}
async function poll() {
  if(polling)return;polling=true;
  try {
    const data=await transport('GET');
    if(!bridgeOnline)output.appendLine(`Connected to bridge on ${PORT}; build ${BUILD}`);
    bridgeOnline=true;
    for(const event of data.events||[]) {
      if(seen.has(event.id))continue;seen.add(event.id);
      if(Date.parse(event.createdAt)<started-1000)continue;
      const p=event.payload||{};
      if(event.source==='macos-overlay'&&event.type==='behavior.state') {
        lastActor=Date.now();actorMode=p.mode;actorClient=p.editorClient;
      }
      if(event.type==='behavior.shutdown')enqueue(releaseRubbish);
      if(event.type==='cleanup.requested'&&event.source==='macos-overlay')enqueue(()=>cleanup(p));
      if(event.type==='behavior.request'&&p.target===CLIENT) enqueue(async()=>{
        let result;try{result=await handle(p)}catch(e){result={ok:false,reason:e.message}}
        output.appendLine(`${p.operation}: ${result.ok?'OK':result.reason||'failed'} (${p.requestId})`);
        await post('behavior.response',{...result,requestId:p.requestId,active:!!activeEditor()});heartbeat();
      });
    }
    if(seen.size>1000)seen=new Set((data.events||[]).map(e=>e.id));
  } catch(e) {if(bridgeOnline)output.appendLine(`Bridge disconnected: ${e.message}`);bridgeOnline=false;} finally {polling=false;updateStatus();}
}
function activate(ctx) {
  context=ctx;store=new MarkerStore(ctx.workspaceState.get('behaviorMarkers.v2',[]));started=Date.now();
  output=vscode.window.createOutputChannel('Chaos Cat');
  output.appendLine(`Activated ${BUILD}: ${CLIENT}`);
  // Attachment options do not expose fontSize. Keep the glyph in the
  // editor font context and center it without changing the line box metrics.
  poopDecoration=vscode.window.createTextEditorDecorationType({after:{contentText:'💩',textDecoration:'none; font-size: 1.5em; vertical-align: middle; line-height: 0;',margin:'0 0.1em 0 0.25em'},rangeBehavior:vscode.DecorationRangeBehavior.ClosedClosed});
  rubbishDecoration=vscode.window.createTextEditorDecorationType({color:new vscode.ThemeColor('editor.foreground'),rangeBehavior:vscode.DecorationRangeBehavior.ClosedClosed});
  status=vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right,72);status.text='$(hubot) 小猫';status.command='chaosCat.diagnostics';status.show();
  ctx.subscriptions.push(poopDecoration,rubbishDecoration,status,output);
  ctx.subscriptions.push(vscode.commands.registerCommand('chaosCat.diagnostics',()=>{
    const info={extensionPath:ctx.extensionPath,version:ctx.extension.packageJSON.version,build:BUILD,clientId:CLIENT,port:PORT,bridgeOnline,actorOnline:Date.now()-lastActor<4000,linked:actorClient===CLIENT,mode:actorMode,focused:vscode.window.state.focused,uri:vscode.window.activeTextEditor?.document.uri.toString()};
    output.appendLine(JSON.stringify(info,null,2));output.show(true);return info;
  }));
  ctx.subscriptions.push(vscode.commands.registerCommand('chaosCat.removePoopAtCursor',()=>{
    const editor=vscode.window.activeTextEditor;
    return editor ? removePoopFromSelection(editor,[editor.selection]) : false;
  }));
  const actions={triggerPoop:'poopChaos',triggerBoxDive:'rubbish',triggerBugChase:'bugChase',calm:'calm',triggerBury:'bury',insertComment:'poopChaos'};
  for(const [name,action] of Object.entries(actions))ctx.subscriptions.push(vscode.commands.registerCommand(`chaosCat.${name}`,()=>post('pet.actionRequested',{action,debug:true,active:!!activeEditor()})));
  for(const name of ['clearEffects','cleanComments'])ctx.subscriptions.push(vscode.commands.registerCommand(`chaosCat.${name}`,async()=>{
    await post('pet.actionRequested',{action:'clear',debug:true,active:!!activeEditor()});
    return enqueue(()=>cleanup());
  }));
  ctx.subscriptions.push(vscode.commands.registerCommand('chaosCat.toggleMutation',()=>vscode.window.showInformationMessage('小猫使用真实 /shit/ 和临时 /rubbish/ 标记；清理时只删除对应标记。')));
  ctx.subscriptions.push(vscode.workspace.onDidChangeTextDocument(e=>{
    store.changes(e.document.uri.toString(),e.contentChanges,{undo:e.reason===vscode.TextDocumentChangeReason.Undo,redo:e.reason===vscode.TextDocumentChangeReason.Redo});remember(e.document);save();render();
    const editor=activeEditor();if(applying||!editor||editor.document!==e.document||!e.contentChanges.length)return;
    if(Date.now()-lastInput<100)return;lastInput=Date.now();
    const c=e.contentChanges[e.contentChanges.length-1],offset=Math.min(e.document.getText().length,c.rangeOffset+c.text.length);
    post('editor.textChanged',{active:true,anchor:anchor(editor,offset),direction:c.text.length?'right':'left'});
  }));
  // VS Code decorations are drawn over text and do not expose their own
  // click handler. A mouse selection inside a real /shit/ token is the
  // editor's native hit test, so remove only that one verified marker.
  ctx.subscriptions.push(vscode.window.onDidChangeTextEditorSelection(e=>{
    if(applying || e.kind!==vscode.TextEditorSelectionChangeKind.Mouse)return;
    removePoopFromSelection(e.textEditor,e.selections);
  }));
  ctx.subscriptions.push(vscode.window.onDidChangeActiveTextEditor(()=>{render();heartbeat()}),vscode.window.onDidChangeTextEditorVisibleRanges(heartbeat),vscode.window.onDidChangeWindowState(heartbeat));
  timers.push(setInterval(poll,80),setInterval(heartbeat,650));
  for(const doc of vscode.workspace.textDocuments)remember(doc);
  enqueue(releaseRubbish);render();heartbeat();poll();
}
async function deactivate(){timers.forEach(clearInterval);await enqueue(releaseRubbish);await save();}
module.exports={activate,deactivate};

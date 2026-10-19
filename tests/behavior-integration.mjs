import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const port=44817,base=`http://127.0.0.1:${port}`,children=[];
const logs=[],events=[],seen=new Set(),markers=new Map();let state,inserted=0,removed=0,heapCreated=0,timer,heartbeat,busy=false,fixture='const value = 42;';
const original=fixture;
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,label,ms=30000){const start=Date.now();while(!fn()){assert.ok(Date.now()-start<ms,`timeout: ${label}; state=${JSON.stringify(state)}`);await delay(100);}}
async function post(type,payload={}){await fetch(base+'/api/events',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({type,payload:{...payload,clientId:'test-window-1'},source:'vscode-extension'})});}
const anchor=id=>({id,uri:'fixture',screenX:480,screenY:470,line:0,character:6,lineCount:1,visibleStartLine:0,visibleEndLine:0});
async function handle(p){
 assert.equal(p.target,'test-window-1','request must target the active window instance');
 let r={ok:true};
 if(p.operation==='target.pick')r.anchor={...anchor(),targetId:'target'};
 if(p.operation==='poop.create'||p.operation==='rubbish.create'){
  const kind=p.operation==='poop.create'?'poop':'rubbish',id=crypto.randomUUID(),text=kind==='poop'?'/shit/':Array.from({length:7},()=>Array(5).fill('/rubbish/').join(' ')).join('\n');
  markers.set(id,{kind,text});fixture+=text;
  if(kind==='poop')inserted++;else heapCreated++;
  r={ok:true,id,anchor:anchor(id)};
 }
 if(p.operation==='poop.list')r.anchors=[...markers].filter(([,m])=>m.kind==='poop').map(([id])=>anchor(id));
 if(p.operation==='marker.locate')r=markers.has(p.id)?{ok:true,anchor:anchor(p.id)}:{ok:false};
 if(p.operation==='marker.remove'){
  const m=markers.get(p.id);r.ok=!!m;if(m){fixture=fixture.replace(m.text,'');markers.delete(p.id);if(m.kind==='poop')removed++;}
 }
 events.push({operation:p.operation,time:Date.now(),clip:state?.clip});await post('behavior.response',{...r,requestId:p.requestId,active:true});
}
function child(command,args,env){const c=spawn(command,args,{env:{...process.env,...env},stdio:['ignore','pipe','pipe']});c.stdout.on('data',d=>logs.push(String(d)));c.stderr.on('data',d=>logs.push(String(d)));children.push(c);return c;}
try{
 child(process.execPath,['apps/bridge/server.mjs'],{CHAOS_CAT_PORT:String(port)});
 for(let n=0;n<30;n++){try{await fetch(base+'/api/health');break}catch{await delay(100)}}
 child('apps/macos/.build/release/ChaosCatMac',[],{CHAOS_CAT_PORT:String(port),CHAOS_CAT_TEST:'1',CHAOS_CAT_TEST_SPEED:'12'});
 heartbeat=setInterval(()=>post('client.hello',{active:true,protocol:2}),400);
 timer=setInterval(async()=>{
  if(busy)return;busy=true;
  try{const data=await (await fetch(base+'/api/events?limit=200')).json();for(const e of data.events){if(seen.has(e.id))continue;seen.add(e.id);if(e.type==='behavior.state')state=e.payload;if(e.type==='behavior.request')await handle(e.payload);}}finally{busy=false;}
 },40);
 await until(()=>state,'actor starts');
 await post('pet.actionRequested',{action:'poopChaos'});
 await until(()=>inserted===3&&state?.mode==='walk','three poop rounds complete');
 assert.equal(inserted,3);assert.equal([...markers.values()].filter(m=>m.kind==='poop').length,3);
 console.log('PASS: exactly three poop rounds, returning to walk');
 await post('pet.actionRequested',{action:'bury'});
 await until(()=>removed===3&&state?.mode==='walk','all three actual markers buried');assert.equal(fixture,original);
 console.log('PASS: burial deletes corresponding markers and restores fixture');
 await post('pet.actionRequested',{action:'rubbish'});
 await until(()=>state?.clip.startsWith('rubbish-tail'),'rubbish approach, discovery, sprint and dive');assert.equal(heapCreated,1);fixture+=' // concurrent edit';
 const rubbishLines=fixture.split('\n').filter(line=>line.includes('/rubbish/'));
 assert.equal(rubbishLines.length,7,'rubbish displacement uses seven editor lines');
 assert.ok(rubbishLines.every(line=>(line.match(/\/rubbish\//g)||[]).length===5),'each rubbish line has five markers');
 await post('pet.actionRequested',{action:'scatter'});
 await until(()=>![...markers.values()].some(m=>m.kind==='rubbish'),'click restores rubbish displacement');assert.equal(fixture,original+' // concurrent edit');
 console.log('PASS: rubbish dive reaches tail loop; release preserves concurrent edits');
 const interruptedBefore=inserted;
 await post('pet.actionRequested',{action:'poopChaos'});await until(()=>state?.mode==='poop','interruptible poop started');
 await post('pet.actionRequested',{action:'scatter'});await until(()=>state?.mode==='scared','poop click starts frightened run');
 await until(()=>inserted>=interruptedBefore+12,'interrupted poop scatters real markers');
 assert.ok(inserted>=interruptedBefore+12);
 await until(()=>state?.mode==='walk','scared run returns to walk');
 console.log('PASS: poop interruption runs away then returns to default');
 await post('editor.textChanged',{anchor:anchor(),direction:'left',active:true});
 await until(()=>state?.mode==='bug','typing triggers bug');await until(()=>state?.mode==='walk','bug timeout exits chase',23000);
 console.log('PASS: input triggers chase and timeout exits');
 await fs.writeFile('docs/behavior-integration-validation.json',JSON.stringify({passed:true,inserted,removed,heapCreated,events},null,2)+'\n');
}catch(e){console.error(logs.join('').slice(-4000));throw e;}finally{clearInterval(timer);clearInterval(heartbeat);children.forEach(c=>c.kill('SIGTERM'));}

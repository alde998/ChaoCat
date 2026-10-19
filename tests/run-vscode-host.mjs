import {spawn} from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
const root=path.resolve(import.meta.dirname,'..'),children=[];
const reservation=net.createServer();
await new Promise((resolve,reject)=>{reservation.once('error',reject);reservation.listen(0,'127.0.0.1',resolve)});
const port=String(reservation.address().port);
await new Promise(resolve=>reservation.close(resolve));
const profile=await fs.mkdtemp('/tmp/chaos-cat-vscode-host-');
const began=Date.now();
await fs.mkdir(path.join(profile,'User'),{recursive:true});
await fs.writeFile(path.join(profile,'User/settings.json'),JSON.stringify({'extensions.autoUpdate':false,'extensions.autoCheckUpdates':false,'update.mode':'none','workbench.enableExperiments':false}));
const env={...process.env,CHAOS_CAT_PORT:port,CHAOS_CAT_TEST:'1',CHAOS_CAT_TEST_SPEED:'12'};
delete env.ELECTRON_RUN_AS_NODE;
const child=(cmd,args)=>{const c=spawn(cmd,args,{cwd:root,env,stdio:'inherit'});children.push(c);return c;};
try{
 child(process.execPath,['apps/bridge/server.mjs']);
 for(let n=0;n<40;n++){try{await fetch(`http://127.0.0.1:${port}/api/health`);break}catch{await new Promise(r=>setTimeout(r,100));}}
 // Verify the shipping executable and bundled assets on an isolated port.
 child('apps/macos/ChaosCat.app/Contents/MacOS/ChaosCatMac',[]);
 for(let n=0;n<60;n++){
  try{const response=await fetch(`http://127.0.0.1:${port}/api/events?limit=1`);const body=await response.json();if(body.events?.length)break;}catch{}
  await new Promise(r=>setTimeout(r,100));
 }
 const app=process.env.CHAOS_CAT_CODE_APP||'/Applications/Visual Studio Code.app';
 const executable=await fs.access(app+'/Contents/MacOS/Code').then(()=>app+'/Contents/MacOS/Code',()=>app+'/Contents/MacOS/Electron');
 const code=child(executable,[
  `--extensionDevelopmentPath=${root}/extensions/vscode`,`--extensionTestsPath=${root}/tests/vscode-host.cjs`,
  `--user-data-dir=${profile}`,`--extensions-dir=${profile}/extensions`,'--locale=en','--disable-updates','--disable-extensions','--skip-welcome','--skip-release-notes','--new-window'
 ]);
 const result=await new Promise((resolve,reject)=>{code.on('exit',resolve);code.on('error',reject)});
 if(result!==0)throw new Error(`VS Code test host exited ${result}`);
 const report=path.join(root,'docs/vscode-host-validation.json');
 if((await fs.stat(report)).mtimeMs<began || !(JSON.parse(await fs.readFile(report,'utf8'))).passed)throw new Error('VS Code exited without a fresh passing test report');
}finally{children.forEach(c=>{if(c.exitCode===null)c.kill('SIGTERM')});}

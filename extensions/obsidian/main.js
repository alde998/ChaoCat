const {Plugin,MarkdownView,requestUrl}=require('obsidian');
const fs=require('fs');
const os=require('os');
const {MarkerStore,poopRanges}=require('./markers.cjs');
const {ChaosEditorAdapter}=require('./behavior-adapter');
module.exports=class ChaosCatPlugin extends Plugin {
  async onload(){
    const port=Number(process.env.CHAOS_CAT_PORT)||44777;
    const tokenFile=process.env.CHAOS_CAT_BRIDGE_TOKEN_FILE||require('path').join(os.tmpdir(),`chaos-cat-bridge-${typeof process.getuid==='function'?process.getuid():'user'}-${port}.token`);
    const bridgeToken=()=>{try{return (process.env.CHAOS_CAT_BRIDGE_TOKEN||fs.readFileSync(tokenFile,'utf8')).trim()}catch{return ''}};
    const headers=()=>({'x-chaos-cat-token':bridgeToken()});
    const bridgeUrl=`http://127.0.0.1:${port}/api/events`;
    const post=async(type,payload)=>{try{await requestUrl({url:bridgeUrl,method:'POST',contentType:'application/json',headers:headers(),body:JSON.stringify({source:'obsidian-plugin',type,payload,createdAt:new Date().toISOString()})})}catch{}};
    this.adapter=new ChaosEditorAdapter({source:'obsidian-plugin',MarkerStore,poopRanges,load:(await this.loadData())?.markers||[],save:markers=>this.saveData({markers}),active:()=>document.hasFocus()?this.current():null,documents:()=>this.app.workspace.getLeavesOfType('markdown').map(l=>this.wrap(l.view)).filter(Boolean),post,receive:async()=> (await requestUrl({url:`${bridgeUrl}?limit=100`,headers:headers()})).json});
    const actions=[['poop-chaos','拉屎','poopChaos'],['box-dive','跳垃圾堆','rubbish'],['bug-chase','追虫','bugChase'],['clear-effects','埋屎清理','bury'],['calm','休息','calm']];
    for(const [id,name,action] of actions)this.addCommand({id,name,callback:()=>post('pet.actionRequested',{action,active:true})});
    this.addRibbonIcon('cat','小猫：追虫',()=>post('pet.actionRequested',{action:'bugChase',active:true}));
    this.registerEvent(this.app.workspace.on('editor-change',()=>this.adapter.input()));
    this.registerEvent(this.app.workspace.on('active-leaf-change',()=>this.adapter.heartbeat()));
    this.adapter.start();
  }
  current(){return this.wrap(this.app.workspace.getActiveViewOfType(MarkdownView));}
  wrap(view){
    if(!view?.editor||!view.file)return null;
    const editor=view.editor,uri=view.file.path,host=view.contentEl;
    const cm=editor.cm;
    return {uri,text:()=>editor.getValue(),cursor:()=>editor.posToOffset(editor.getCursor()),
      pick:p=>{
        if(p.random){const lines=editor.lineCount(),line=Math.floor(Math.random()*lines);return editor.posToOffset({line,ch:Math.floor(Math.random()*(editor.getLine(line).length+1))})}
        const box=host.getBoundingClientRect(),found=cm?.posAtCoords?.({x:box.left+box.width*(p.xRatio??0.5),y:box.top+box.height*(p.yRatio??0.5)});
        return found??editor.posToOffset(editor.getCursor());
      },
      anchor:offset=>{
        const p=editor.offsetToPos(offset),r=cm?.coordsAtPos?.(offset),box=host.getBoundingClientRect();
        const screenX=window.screenX+(r?.left??box.left+40),screenY=window.screenY+(window.outerHeight-window.innerHeight)+(r?.bottom??box.top+30+p.line*22);
        return {uri,offset,line:p.line,character:p.ch,lineCount:editor.lineCount(),visibleStartLine:0,visibleEndLine:editor.lineCount()-1,fontSize:16,lineHeight:22,screenX,screenY};
      },
      replace:async(offset,length,text)=>{const before=editor.getValue();editor.replaceRange(text,editor.offsetToPos(offset),editor.offsetToPos(offset+length),'chaos-cat');return editor.getValue()===before.slice(0,offset)+text+before.slice(offset+length);}
    };
  }
  onunload(){this.adapter?.stop();}
};

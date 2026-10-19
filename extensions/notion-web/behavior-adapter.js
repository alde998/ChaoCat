/* Shared native actor protocol for text editors. No separate cat clock. */
class ChaosEditorAdapter {
  constructor({source,MarkerStore,poopRanges,active,documents,load,save,post,receive}) {
    Object.assign(this,{source,poopRanges,active,documents,save,receive});
    this.clientId=source+':'+Math.random().toString(16).slice(2);
    this.post=(type,payload)=>post(type,{...payload,clientId:this.clientId});
    this.store=new MarkerStore(load||[]);this.texts=new Map();this.seen=new Set();this.queue=Promise.resolve();this.started=Date.now();this.lastActor=0;this.applying=false;this.lastClearAt=0;
  }
  remember(doc) {
    const text=doc.text(),old=this.texts.get(doc.uri);
    if(old===undefined)this.store.recover(doc.uri,text);
    else if(old!==text){
      let start=0;while(start<old.length&&start<text.length&&old[start]===text[start])start++;
      let tail=0;while(tail<old.length-start&&tail<text.length-start&&old[old.length-1-tail]===text[text.length-1-tail])tail++;
      this.store.changes(doc.uri,[{rangeOffset:start,rangeLength:old.length-start-tail,text:text.slice(start,text.length-tail)}]);
    }
    this.texts.set(doc.uri,text);return text;
  }
  persist() {return this.save(this.store.snapshot(this.texts));}
  anchor(doc,r){return {...doc.anchor(r.offset+Math.floor(r.text.length/2)),id:r.id,kind:r.kind};}
  async input(direction='right') {
    const doc=this.active();if(!doc)return;this.remember(doc);await this.persist();
    if(!this.applying)await this.post('editor.textChanged',{active:true,direction,anchor:doc.anchor(doc.cursor())});
  }
  async remove(id) {
    const r=this.store.get(id),doc=r&&this.documents().find(d=>d.uri===r.uri);if(!doc)return false;
    this.remember(doc);if(!this.store.verify(r,doc.text()))return false;
    this.applying=true;
    try {
      const ok=await doc.replace(r.offset,r.text.length,'');this.remember(doc);
      if(ok)this.store.forget(id);await this.persist();return !!ok;
    } finally{this.applying=false;}
  }
  async cleanup(p) {
    this.lastClearAt=Math.max(this.lastClearAt,Number(p.cutoff)||Date.now());
    await this.release();
    const uris=new Set(this.store.records.filter(r=>r.kind==='poop').map(r=>r.uri));
    const current=this.active();if(current)uris.add(current.uri);
    let count=0,ok=true;this.applying=true;
    try {
      for(const doc of this.documents().filter(d=>uris.has(d.uri))) {
        this.remember(doc);
        const ranges=this.poopRanges(doc.text());
        for(const r of ranges.reverse()) {
          if(await doc.replace(r.offset,r.length,''))count+=r.count;else ok=false;
        }
        this.remember(doc);
      }
      await this.persist();
    } finally {this.applying=false;}
    await this.post('cleanup.completed',{ok,count,requestId:p.requestId});
  }
  async handle(p) {
    if(['poop.create','rubbish.create','target.pick'].includes(p.operation)&&Number(p.issuedAt)<=this.lastClearAt)return {ok:false,reason:'cancelled-by-cleanup'};
    if(p.operation==='marker.remove')return {ok:await this.remove(p.id)};
    const doc=this.active();if(!doc)return {ok:false,reason:'no-active-editor'};
    this.remember(doc);
    if(p.operation==='target.pick') {
      const offset=doc.pick(p),r=this.store.add(doc.uri,offset,'','target');
      return {ok:true,anchor:{...doc.anchor(offset),targetId:r.id}};
    }
    if(['rubbish.create','poop.create'].includes(p.operation)) {
      let offset=doc.pick(p);
      if(p.anchor?.targetId) {
        const target=this.store.get(p.anchor.targetId);this.store.forget(p.anchor.targetId);
        if(!target||target.uri!==doc.uri)return {ok:false,reason:'target-changed'};offset=target.offset;
      }
      const kind=p.operation==='rubbish.create'?'rubbish':'poop',text=kind==='poop'?'/shit/':Array.from({length:7},()=>Array(5).fill('/rubbish/').join(' ')).join('\n');
      this.applying=true;
      try {
        if(!await doc.replace(offset,0,text))return {ok:false,reason:'edit-rejected'};
        this.remember(doc);const r=this.store.add(doc.uri,offset,text,kind);await this.persist();
        return {ok:true,id:r.id,anchor:this.anchor(doc,r)};
      } finally {this.applying=false;}
    }
    if(p.operation==='poop.list') {
      const text=doc.text();for(const m of text.matchAll(/\/shit\//g))if(!this.store.forDocument(doc.uri,text,'poop').some(r=>r.offset===m.index))this.store.add(doc.uri,m.index,m[0],'poop');
      await this.persist();return {ok:true,anchors:this.store.forDocument(doc.uri,text,'poop').map(r=>this.anchor(doc,r))};
    }
    if(p.operation==='marker.locate') {
      const r=this.store.get(p.id);return r&&r.uri===doc.uri&&this.store.verify(r,doc.text())?{ok:true,anchor:this.anchor(doc,r)}:{ok:false};
    }
    return {ok:false,reason:'unknown-operation'};
  }
  enqueue(work){this.queue=this.queue.then(work,work).catch(e=>console.warn('Chaos Cat',e));return this.queue;}
  async release(){for(const r of [...this.store.records].filter(r=>r.valid&&r.kind==='rubbish'))await this.remove(r.id);}
  async poll(){
    if(this.polling)return;this.polling=true;
    try {
      const data=await this.receive();
      for(const event of data.events||[]) {
        if(this.seen.has(event.id))continue;this.seen.add(event.id);if(Date.parse(event.createdAt)<this.started-1000)continue;
        const p=event.payload||{};
        if(event.source==='macos-overlay'&&event.type==='behavior.state')this.lastActor=Date.now();
        if(event.type==='behavior.shutdown')this.enqueue(()=>this.release());
        if(event.type==='cleanup.requested'&&event.source==='macos-overlay')this.enqueue(()=>this.cleanup(p));
        if(event.type==='behavior.request'&&p.target===this.clientId)this.enqueue(async()=>{
          let response;try{response=await this.handle(p)}catch(e){response={ok:false,reason:e.message}}
          await this.post('behavior.response',{...response,requestId:p.requestId,active:!!this.active()});
        });
      }
      if(this.seen.size>1000)this.seen=new Set((data.events||[]).map(e=>e.id));
    } catch {} finally {this.polling=false;}
  }
  heartbeat(){
    const doc=this.active();this.post('client.hello',{protocol:2,active:!!doc});
    if(doc){this.remember(doc);this.post('editor.visibleRangesChanged',{...doc.anchor(doc.cursor()),active:true});this.post('behavior.anchors',{active:true,anchors:this.store.forDocument(doc.uri,doc.text()).filter(r=>r.kind!=='target').map(r=>this.anchor(doc,r))});}
    if(this.lastActor&&Date.now()-this.lastActor>5000){this.lastActor=0;this.enqueue(()=>this.release());}
  }
  start(){for(const doc of this.documents())this.remember(doc);this.enqueue(()=>this.release());this.timers=[setInterval(()=>this.poll(),80),setInterval(()=>this.heartbeat(),650)];this.heartbeat();}
  async stop(){this.timers?.forEach(clearInterval);await this.enqueue(()=>this.release());await this.persist();}
}
if(typeof module!=='undefined')module.exports={ChaosEditorAdapter};else globalThis.ChaosEditorAdapter=ChaosEditorAdapter;

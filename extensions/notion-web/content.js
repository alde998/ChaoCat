(()=>{
  if(globalThis.__chaosNativeAdapter)return;
  const source='notion-web-extension',endpoint='http://127.0.0.1:44777/api/events';
  const post=(type,payload)=>fetch(endpoint,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({type,source,payload,createdAt:new Date().toISOString()})}).catch(()=>null);
  const nodes=()=>[...document.querySelectorAll('[contenteditable="true"][role="textbox"],.notion-page-content [contenteditable="true"]')].filter((e,i,a)=>!a.some((parent,j)=>i!==j&&parent.contains(e)));
  function rangeAt(element,start,length=0){
    const range=document.createRange(),walker=document.createTreeWalker(element,NodeFilter.SHOW_TEXT);let node,offset=0,found=false;
    while(node=walker.nextNode()){
      const end=offset+node.length;
      if(!found&&start<=end){range.setStart(node,Math.max(0,start-offset));found=true;}
      if(found&&start+length<=end){range.setEnd(node,Math.max(0,start+length-offset));return range;}offset=end;
    }
    if(!found){range.selectNodeContents(element);range.collapse(false);}else range.setEnd(element,element.childNodes.length);
    return range;
  }
  function wrap(element){
    const block=element.closest('[data-block-id]'),id=block?.getAttribute('data-block-id');if(!id)return null;
    const uri=location.pathname+'#'+id;
    return {uri,text:()=>element.textContent||'',cursor:()=>{
      const sel=getSelection();if(!sel?.rangeCount||!element.contains(sel.anchorNode))return 0;
      const r=sel.getRangeAt(0).cloneRange();r.selectNodeContents(element);r.setEnd(sel.anchorNode,sel.anchorOffset);return r.toString().length;
    },pick:p=>p.random?Math.floor(Math.random()*((element.textContent||'').length+1)):Math.round((element.textContent||'').length*(p.xRatio??0.5)),
    anchor:offset=>{
      const r=rangeAt(element,offset).getBoundingClientRect(),fallback=element.getBoundingClientRect(),box=r.height?r:fallback;
      const scale=window.outerWidth/window.innerWidth;
      return {uri,offset,screenX:window.screenX+box.left*scale,screenY:window.screenY+window.outerHeight-window.innerHeight*scale+box.bottom*scale,line:0,character:offset,lineCount:1,visibleStartLine:0,visibleEndLine:0,fontSize:16,lineHeight:24};
    },replace:async(offset,length,text)=>{
      if(!element.isConnected||element.getAttribute('contenteditable')!=='true')return false;
      const before=element.textContent,sel=getSelection(),previous=sel?.rangeCount?sel.getRangeAt(0).cloneRange():null,focused=document.activeElement;
      element.focus();sel.removeAllRanges();sel.addRange(rangeAt(element,offset,length));
      const ok=document.execCommand('insertText',false,text);
      if(previous&&previous.startContainer.isConnected){sel.removeAllRanges();sel.addRange(previous);if(focused?.isConnected)focused.focus({preventScroll:true});}
      // Use the editor's input command; assigning textContent would bypass persistence.
      return ok&&element.textContent===before.slice(0,offset)+text+before.slice(offset+length);
    }};
  }
  const docs=()=>nodes().map(wrap).filter(Boolean);
  const active=()=>{
    if(!document.hasFocus())return null;
    const focused=document.activeElement?.closest('[contenteditable="true"]');
    return focused?wrap(focused):null;
  };
  let saved=[];try{saved=JSON.parse(localStorage.getItem('chaos-cat-markers-v2')||'[]')}catch{}
  const adapter=new ChaosEditorAdapter({source,MarkerStore:ChaosMarkerStore,poopRanges:chaosPoopRanges,active,documents:docs,load:saved,save:markers=>localStorage.setItem('chaos-cat-markers-v2',JSON.stringify(markers)),post,receive:()=>fetch(endpoint+'?limit=100').then(r=>r.json())});
  globalThis.__chaosNativeAdapter=adapter;
  document.addEventListener('input',e=>{if(e.target.closest?.('[contenteditable="true"]'))adapter.input(e.inputType?.includes('delete')?'left':'right')},true);
  window.addEventListener('pagehide',()=>adapter.stop());adapter.start();
  const controls=document.createElement('div');controls.className='chaos-cat-native-controls';
  for(const [label,action] of [['追虫','bugChase'],['垃圾堆','rubbish'],['拉屎','poopChaos'],['埋屎','bury']]){
    const button=document.createElement('button');button.textContent=label;button.addEventListener('mousedown',e=>e.preventDefault());button.addEventListener('click',()=>post('pet.actionRequested',{action,active:!!active()}));controls.append(button);
  }
  document.body.append(controls);
})();

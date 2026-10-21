// UTF-16 offsets match VS Code/CodeMirror/DOM text offsets. Never restore a
// document snapshot: remove only an unchanged marker owned by this session.
class MarkerStore {
  constructor(records = []) { this.records = records.map(r => ({ ...r, owner: r.owner || 'legacy' })); }
  add(uri, offset, text, kind, id = `${Date.now()}-${Math.random().toString(16).slice(2)}`) {
    const r = { id, uri, offset, text, kind, owner: 'chaos-cat', valid: true };
    this.records.push(r); return r;
  }
  changes(uri, changes, {undo=false,redo=false}={}) {
    for (const c of [...changes].sort((a,b) => b.rangeOffset-a.rangeOffset)) {
      const start=c.rangeOffset, end=start+c.rangeLength, delta=c.text.length-c.rangeLength;
      for (const r of this.records) {
        if (r.owner!=='chaos-cat' || r.uri!==uri) continue;
        // A genuine redo of our own undone insertion retains ownership.
        // Typing the same literal manually must never claim it again.
        if (r.undone) {
          if (redo && start===r.offset && c.rangeLength===0 && c.text===r.text) {
            r.valid=true;delete r.undone;
          } else if (!undo && !redo) delete r.undone;
          else if (end<=r.offset) r.offset+=delta;
          else if (start<r.offset) delete r.undone;
          continue;
        }
        if (!r.valid) continue;
        const right=r.offset+r.text.length;
        if (end<=r.offset) r.offset+=delta;
        else if (start>=right) continue;
        else {
          if (undo && start===r.offset && c.rangeLength===r.text.length && c.text==='') r.undone=true;
          r.valid=false; // Editing inside a marker transfers ownership to the user.
        }
      }
    }
  }
  verify(r, text) { return !!r?.valid && r.owner==='chaos-cat' && text.slice(r.offset,r.offset+r.text.length)===r.text; }
  forDocument(uri, text, kind) { return this.records.filter(r => r.uri===uri && (!kind || r.kind===kind) && this.verify(r,text)); }
  get(id) { return this.records.find(r => r.id===id && r.valid && r.owner==='chaos-cat'); }
  forget(id) { this.records=this.records.filter(r => r.id!==id); }
  snapshot(documents) {
    return this.records.filter(r => r.valid && r.owner==='chaos-cat' && r.kind!=='target' && documents.has(r.uri)).map(r => {
      const text=documents.get(r.uri);
      return {...r,before:text.slice(Math.max(0,r.offset-32),r.offset),after:text.slice(r.offset+r.text.length,r.offset+r.text.length+32)};
    });
  }
  recover(uri,text) {
    for (const r of this.records.filter(r => r.uri===uri)) {
      if (r.before===undefined) continue;
      r.valid=this.verify(r,text) && text.slice(Math.max(0,r.offset-32),r.offset)===r.before && text.slice(r.offset+r.text.length,r.offset+r.text.length+32)===r.after;
      delete r.before;delete r.after;
    }
  }
}
// Older builds could insert a marker inside another marker. Reduce complete
// inner tokens first while retaining original UTF-16 ranges for one undo edit.
function poopRanges(text) {
  const stack=[],ranges=[];
  for(let i=0;i<text.length;i++) {
    stack.push({value:text[i],offset:i});
    if(text[i]!=='/'||stack.length<6||stack.slice(-6).map(c=>c.value).join('')!=='/shit/')continue;
    const token=stack.splice(-6);ranges.push({offset:token[0].offset,length:i+1-token[0].offset,count:1});
  }
  const merged=[];
  for(const r of ranges.sort((a,b)=>a.offset-b.offset)) {
    const previous=merged.at(-1);
    if(previous&&r.offset<=previous.offset+previous.length) {
      previous.length=Math.max(previous.offset+previous.length,r.offset+r.length)-previous.offset;previous.count+=r.count;
    } else merged.push({...r});
  }
  return merged;
}
if(typeof module!=='undefined')module.exports={MarkerStore,poopRanges};
else {globalThis.ChaosMarkerStore=MarkerStore;globalThis.chaosPoopRanges=poopRanges;}

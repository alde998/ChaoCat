// UTF-16 offsets match VS Code/CodeMirror/DOM text offsets. Never restore a
// document snapshot: remove only an unchanged marker owned by this session.
class MarkerStore {
  constructor(records = []) { this.records = records.map(r => ({ ...r })); }
  add(uri, offset, text, kind, id = `${Date.now()}-${Math.random().toString(16).slice(2)}`) {
    const r = { id, uri, offset, text, kind, valid: true };
    this.records.push(r); return r;
  }
  changes(uri, changes) {
    for (const c of [...changes].sort((a,b) => b.rangeOffset-a.rangeOffset)) {
      const start=c.rangeOffset, end=start+c.rangeLength, delta=c.text.length-c.rangeLength;
      for (const r of this.records) {
        if (!r.valid || r.uri!==uri) continue;
        const right=r.offset+r.text.length;
        if (end<=r.offset) r.offset+=delta;
        else if (start>=right) continue;
        else r.valid=false; // Editing inside a marker transfers ownership to the user.
      }
    }
  }
  verify(r, text) { return !!r?.valid && text.slice(r.offset,r.offset+r.text.length)===r.text; }
  forDocument(uri, text, kind) { return this.records.filter(r => r.uri===uri && (!kind || r.kind===kind) && this.verify(r,text)); }
  get(id) { return this.records.find(r => r.id===id && r.valid); }
  forget(id) { this.records=this.records.filter(r => r.id!==id); }
  snapshot(documents) {
    return this.records.filter(r => r.valid && r.kind!=='target' && documents.has(r.uri)).map(r => {
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
if(typeof module!=='undefined')module.exports={MarkerStore};
else globalThis.ChaosMarkerStore=MarkerStore;

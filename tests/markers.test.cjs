const test=require('node:test'),assert=require('node:assert/strict');
const {MarkerStore,poopRanges}=require('../extensions/vscode/markers.cjs');
function edit(s,uri,text,offset,length,value){s.changes(uri,[{rangeOffset:offset,rangeLength:length,text:value}]);return text.slice(0,offset)+value+text.slice(offset+length);}
test('rubbish removal preserves edits and original code',()=>{
 const s=new MarkerStore(),gap=Array.from({length:7},()=>Array(5).fill('/rubbish/').join(' ')).join('\n');let text='const cat = 1;';const original=text;
 text=edit(s,'a',text,6,0,gap);const r=s.add('a',6,gap,'rubbish');
 text=edit(s,'a',text,0,0,'// 新增\n');text=edit(s,'a',text,text.length,0,'\ncat++;');
 assert.ok(s.verify(r,text));text=edit(s,'a',text,r.offset,r.text.length,'');
 assert.equal(text,'// 新增\n'+original+'\ncat++;');
 assert.equal(gap.split('\n').length,7);
 assert.equal((gap.match(/\/rubbish\//g)||[]).length,35);
});
test('editing inside a marker relinquishes deletion ownership',()=>{
 const s=new MarkerStore(),r=s.add('a',1,'/shit/','poop');let text='x/shit/y';
 text=edit(s,'a',text,3,1,'USER');assert.equal(s.verify(r,text),false);
});
test('multi-cursor edits rebase in old-document coordinates',()=>{
 const s=new MarkerStore(),r=s.add('a',10,'/shit/','poop');
 s.changes('a',[{rangeOffset:0,rangeLength:2,text:'abcd'},{rangeOffset:8,rangeLength:0,text:'!!'}]);assert.equal(r.offset,14);
});
test('adjacent edits and UTF-16 offsets preserve actual marker',()=>{
 const s=new MarkerStore(),r=s.add('a',2,'/shit/','poop');let text='🐈/shit/';
 text=edit(s,'a',text,2,0,'中文');text=edit(s,'a',text,text.length,0,'!');assert.equal(r.offset,4);assert.ok(s.verify(r,text));
});
test('recovery checks context before deleting a saved marker',()=>{
 const s=new MarkerStore();s.add('a',1,'/shit/','poop');const saved=s.snapshot(new Map([['a','x/shit/y']]));
 const restored=new MarkerStore(saved);restored.recover('a','z/shit/y');assert.equal(restored.get(saved[0].id),undefined);
 const intact=new MarkerStore(saved);intact.recover('a','x/shit/y');assert.ok(intact.get(saved[0].id));
});
test('markers in unrelated documents never move',()=>{
 const s=new MarkerStore(),r=s.add('b',4,'/shit/','poop');s.changes('a',[{rangeOffset:0,rangeLength:10,text:''}]);assert.equal(r.offset,4);assert.equal(r.valid,true);
});
test('legacy records cannot claim user-authored text after upgrade',()=>{
 const s=new MarkerStore([{id:'old',uri:'a',offset:1,text:'/shit/',kind:'poop',valid:true}]);
 assert.equal(s.get('old'),undefined);
 assert.deepEqual(s.forDocument('a','x/shit/y','poop'),[]);
 assert.deepEqual(s.snapshot(new Map([['a','x/shit/y']])),[]);
});
test('redo restores ownership only for a known undone insertion',()=>{
 const s=new MarkerStore(),r=s.add('a',1,'/shit/','poop');
 s.changes('a',[{rangeOffset:1,rangeLength:6,text:''}],{undo:true});
 assert.equal(s.get(r.id),undefined);
 s.changes('a',[{rangeOffset:1,rangeLength:0,text:'/shit/'}],{redo:true});
 assert.equal(s.forDocument('a','x/shit/y','poop').length,1);
 s.changes('a',[{rangeOffset:1,rangeLength:6,text:''}],{undo:true});
 s.changes('a',[{rangeOffset:1,rangeLength:0,text:'/shit/'}]);
 assert.equal(s.forDocument('a','x/shit/y','poop').length,0,'manually typed text remains user-owned');
});
test('bulk cleanup finds adjacent and nested legacy marks in original UTF-16 ranges',()=>{
 let text='🐈const x = 1;';const original=text;
 text=text.slice(0,5)+'/shit/'+text.slice(5);
 text=text.slice(0,8)+'/shit/'+text.slice(8);
 text='/shit//shit/'+text+' // user edit';
 const ranges=poopRanges(text);assert.equal(ranges.reduce((n,r)=>n+r.count,0),4);
 for(const r of [...ranges].reverse())text=text.slice(0,r.offset)+text.slice(r.offset+r.length);
 assert.equal(text,original+' // user edit');
 assert.deepEqual(poopRanges('keep /shiUSERt/ and shit words'),[]);
});

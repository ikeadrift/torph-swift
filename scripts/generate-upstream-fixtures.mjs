import fs from 'node:fs';
import path from 'node:path';
import {stripTypeScriptTypes} from 'node:module';
import {pathToFileURL} from 'node:url';
const root=process.argv[2];
if(!root) throw Error('Pass the path to a checkout of lochie/torph');
const out=path.resolve('.build/upstream-oracle');
function compile(file){
 const dest=path.join(out,path.relative(root,file).replace(/\.ts$/,'.mjs'));
 if(fs.existsSync(dest))return dest;
 fs.mkdirSync(path.dirname(dest),{recursive:true});
 let src=stripTypeScriptTypes(fs.readFileSync(file,'utf8'));
 src=src.replace(/(from\s+["'])(\.[^"']+)(["'])/g,(_,a,b,c)=>{
   compile(path.resolve(path.dirname(file),b+'.ts'));return a+b+'.mjs'+c;
 });
 fs.writeFileSync(dest,src);return dest;
}
const base=root+'/packages/torph/src/lib/text-morph/utils/';
const {segmentText}=await import(pathToFileURL(compile(base+'segment.ts')));
const {diffSegments}=await import(pathToFileURL(compile(base+'diff.ts')));
const {segmentNumber}=await import(pathToFileURL(compile(base+'number.ts')));
const {CASES}=await import(pathToFileURL(compile(root+'/packages/test-cases/src/cases.ts')));
const {NUMBER_CASES}=await import(pathToFileURL(compile(root+'/packages/test-cases/src/number-cases.ts')));
const fixtures=[];
const extra=[{label:'Reported capitalization transition',values:['Processing transaction','Transaction complete','Processing transaction']},{label:'Upstream title case demo',values:['Processing Transaction','Transaction Safe','Processing Transaction']}];
const clean=s=>({text:s.string,kind:s.kind??null});
let seed=9417;
const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296};
const vocabulary=['Processing','transaction','Transaction','complete','hello','hello','world','npm','pnpm','123','$1,234.50','1.25','COVID-19','a','a-2',"can't",'file.ts','foo_bar','...'];
const fuzz=Array.from({length:200},(_,i)=>({label:`Deterministic mixed case ${i}`,values:Array.from({length:4},()=>Array.from({length:1+Math.floor(random()*7)},()=>vocabulary[Math.floor(random()*vocabulary.length)]).join(random()<.2?'\n':' '))}));
for(const c of [...CASES,...extra,...fuzz]){
 let old=segmentText(c.values[0],'en');
 const steps=[];
 for(const value of [...c.values.slice(1),...c.values]){
  const d=diffSegments(old,value,'en');
  const prepared=old.flatMap(s=>d.splits.get(s.id)??[s]);
  const origins=new Map(prepared.map((s,i)=>[s.id,i]));
  steps.push({value,prepared:prepared.map(clean),segments:d.segments.map(clean),origins:d.segments.map(s=>origins.get(s.id)??null)});
  old=d.segments;
 }
 fixtures.push({label:c.label,mode:'text',locale:'en',initial:c.values[0],initialSegments:segmentText(c.values[0],'en').map(clean),steps});
}
for(const c of NUMBER_CASES){
 const locale=c.locale??'en',decimal=new Intl.NumberFormat(locale).formatToParts(1.1).find(p=>p.type==='decimal').value;
 const format=v=>typeof v==='number'?v.toLocaleString(locale,{minimumFractionDigits:c.decimals,maximumFractionDigits:c.decimals}):v;
 const initial=format(c.values[0]);let old=segmentNumber(initial);const steps=[];
 for(let i=1;i<c.values.length;i++){
  const value=format(c.values[i]),cursor=c.cursors?.[i];
  const next=segmentNumber(value,old,cursor,decimal);const origins=new Map(old.map((s,i)=>[s.id,i]));
  steps.push({value,cursor:cursor??null,prepared:old.map(clean),segments:next.map(clean),origins:next.map(s=>origins.get(s.id)??null)});old=next;
 }
 fixtures.push({label:c.label,mode:'number',locale,initial,initialSegments:segmentNumber(initial).map(clean),steps});
}
for(const c of NUMBER_CASES){
 const locale=c.locale??'en';
 const format=v=>typeof v==='number'?v.toLocaleString(locale,{minimumFractionDigits:c.decimals,maximumFractionDigits:c.decimals}):v;
 const initial=format(c.values[0]);let old=segmentText(initial,locale);const steps=[];
 for(let i=1;i<c.values.length;i++){
  const value=format(c.values[i]),cursor=c.cursors?.[i];
  const d=diffSegments(old,value,locale,{cursorIndex:cursor});
  const prepared=old.flatMap(s=>d.splits.get(s.id)??[s]);
  const origins=new Map(prepared.map((s,i)=>[s.id,i]));
  steps.push({value,cursor:cursor??null,prepared:prepared.map(clean),segments:d.segments.map(clean),origins:d.segments.map(s=>origins.get(s.id)??null)});old=d.segments;
 }
 fixtures.push({label:'Text pipeline: '+c.label,mode:'text',locale,initial,initialSegments:segmentText(initial,locale).map(clean),steps});
}
fs.writeFileSync('Tests/TorphTests/Fixtures/upstream.json' ,JSON.stringify(fixtures,null,2));
console.log(`${fixtures.length} cases, ${fixtures.reduce((n,c)=>n+c.steps.length,0)} transitions`);

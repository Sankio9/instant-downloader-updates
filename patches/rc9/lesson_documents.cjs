'use strict';
/* Save supported public lesson documents beside archived HTML, retaining source URLs. */
const fs=require('node:fs'),path=require('node:path'),https=require('node:https'),dns=require('node:dns'),net=require('node:net'),crypto=require('node:crypto');
const {pipeline}=require('node:stream/promises'),{Transform}=require('node:stream');
const EXT=new Set(['pdf','doc','docx','xls','xlsx','ppt','pptx','csv','txt','rtf','odt','ods','odp','epub','zip']);
const MAX=100*1024*1024;
const name=s=>String(s||'Document').replace(/<[^>]+>/g,'').replace(/[\x00-\x1f<>:"/\\|?*]/g,'-').replace(/[. ]+$/g,'').trim().slice(0,75)||'Document';
const ext=s=>/\.([a-z0-9]{2,7})$/i.exec(s||'')?.[1]?.toLowerCase()||'';
const escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const entities=s=>String(s).replace(/&amp;/gi,'&').replace(/&quot;/gi,'"').replace(/&#39;|&apos;/gi,"'");
function classify(href,caption){
 let u;try{u=new URL(entities(href));}catch{return null}
 if(u.protocol!=='https:'||u.username||u.password)return null;
 const a=u.pathname.split('/').filter(Boolean),host=u.hostname.toLowerCase();
 let suffix=ext(a.at(-1)),link=u.href;
 if(host==='docs.google.com'){
  const e={document:'docx',spreadsheets:'xlsx',presentation:'pptx'}[a[0]];
  if(a[1]!=='d'||!e||!/^[\w-]{10,200}$/.test(a[2]||''))return null;
  suffix=e;link='https://docs.google.com/'+a[0]+'/d/'+a[2]+'/export?format='+e;
 }else if(host==='drive.google.com'){
  const id=a[0]==='file'&&a[1]==='d'?a[2]:u.searchParams.get('id');
  if(!/^[\w-]{10,200}$/.test(id||''))return null;
  link='https://drive.google.com/uc?export=download&id='+encodeURIComponent(id);
 }else if(host==='dropbox.com'||host==='www.dropbox.com'){
  if(!a.includes('s')&&!a.includes('scl'))return null;
  u.searchParams.set('dl','1');link=u.href;
 }else if(!EXT.has(suffix)){
  suffix=ext(u.searchParams.get('filename')||u.searchParams.get('fileName')||'');
  if(!EXT.has(suffix))return null;
 }
 return {link,caption:name(entities(caption).replace(/<[^>]+>/g,'')),suffix};
}
function publicIp(ip){
 if(net.isIP(ip)===4){
  const [a,b,c]=ip.split('.').map(Number);
  return !(a===0||a===10||a===127||a>=224||(a===169&&b===254)||(a===172&&b>=16&&b<=31)||(a===192&&(b===168||b===0))||(a===100&&b>=64&&b<=127)||(a===198&&(b===18||b===19))||(a===203&&b===0&&c===113));
 }
 if(net.isIP(ip)===6){const s=ip.toLowerCase();return !(s==='::'||s==='::1'||/^(fe|fc|fd|ff|2001:db8:|::ffff:)/.test(s))}
 return false;
}
function safeUrl(raw){
 const u=new URL(raw),h=u.hostname.toLowerCase();
 if(u.protocol!=='https:'||(u.port&&u.port!=='443')||u.username||u.password||net.isIP(h)||h==='localhost'||/\.(local|localhost|internal|invalid|test)$/.test(h))throw Error('Unsafe document URL');
 return u;
}
function get(u){return new Promise((resolve,reject)=>{
 const request=https.get(u,{timeout:25000,family:4,headers:{'User-Agent':'InstantDownloader/1.8','Accept':'application/octet-stream,application/pdf,*/*'},
 lookup:(host,opt,callback)=>dns.lookup(host,{all:true,family:4},(e,addresses)=>{
  if(e)return callback(e);
  if(!addresses.length||!addresses.every(x=>publicIp(x.address)))return callback(Error('Unsafe destination'));
  callback(null,addresses[0].address,4);
 })},resolve);
 request.on('timeout',()=>request.destroy(Error('Document timeout'))).on('error',reject);
})}
async function download(url,tmp,suffix){
 let current=url;
 for(let redirect=0;redirect<6;redirect++){
  const base=safeUrl(current),res=await get(base),status=res.statusCode||0;
  if([301,302,303,307,308].includes(status)){
   const where=res.headers.location;res.resume();if(!where)throw Error('Invalid redirect');
   current=new URL(where,base).href;continue;
  }
  if(status!==200){res.resume();throw Error('HTTP '+status)}
  const type=String(res.headers['content-type']||'').split(';')[0].toLowerCase();
  if(['text/html','application/json','application/xhtml+xml'].includes(type)){res.resume();throw Error('Document requires sign-in or is a webpage')}
  const disposition=String(res.headers['content-disposition']||'');
  const m=/filename\*?=(?:UTF-8''|")?([^";]+)/i.exec(disposition);
  let serverName='';if(m){try{serverName=decodeURIComponent(m[1])}catch{serverName=m[1]}}
  const types={'application/pdf':'pdf','text/csv':'csv','text/plain':'txt','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':'xlsx','application/vnd.openxmlformats-officedocument.wordprocessingml.document':'docx','application/vnd.openxmlformats-officedocument.presentationml.presentation':'pptx'};
  const detected=ext(serverName)||suffix||types[type]||'';
  if(!EXT.has(detected)){res.resume();throw Error('Unrecognized document format')}
  if(Number(res.headers['content-length']||0)>MAX){res.resume();throw Error('Document exceeds 100 MB')}
  let bytes=0;
  const guard=new Transform({transform(chunk,enc,cb){bytes+=chunk.length;cb(bytes>MAX?Error('Document exceeds 100 MB'):null,chunk)}});
  try{await pipeline(res,guard,fs.createWriteStream(tmp,{flags:'wx'}))}catch(e){fs.rmSync(tmp,{force:true});throw e}
  if(!bytes)throw Error('Empty document');
  const fd=fs.openSync(tmp,'r'),head=Buffer.alloc(160);let n=0;
  try{n=fs.readSync(fd,head,0,head.length,0)}finally{fs.closeSync(fd)}
  if(/^\s*(<!doctype html|<html|{"error")/i.test(head.subarray(0,n).toString('utf8')))throw Error('Response is HTML or an error page');
  return {name:serverName,suffix:detected,bytes};
 }
 throw Error('Too many redirects');
}
function lessons(root){
 const items=[],stack=[{dir:path.resolve(root),depth:0}];
 while(stack.length&&items.length<5000){
  const {dir,depth}=stack.pop();if(depth>9)continue;
  let d;try{d=fs.readdirSync(dir,{withFileTypes:true})}catch{continue}
  if(d.some(x=>x.name==='lesson.json'&&x.isFile())&&d.some(x=>x.name==='index.html'&&x.isFile()))items.push(dir);
  for(const x of d)if(x.isDirectory()&&!x.isSymbolicLink()&&!x.name.startsWith('_')&&!['resources','assets','node_modules','.auth'].includes(x.name))stack.push({dir:path.join(dir,x.name),depth:depth+1});
 }
 return items;
}
async function processLesson(dir,notify,fetcher=download){
 const page=path.join(dir,'index.html'),original=fs.readFileSync(page,'utf8'),resources=path.join(dir,'resources');
 const a=/<a\b([^>]*?)\bhref\s*=\s*(["'])(.*?)\2([^>]*)>([\s\S]*?)<\/a>/gi;
 const adjacent=/^\s*<span class="instant-local">· <a href="(resources\/[^"<>]+)" download>Deschide local<\/a><\/span>/;
 let out='',last=0,count=0,errors=0,used=new Map();
 for(const match of original.matchAll(a)){
  out+=original.slice(last,match.index)+match[0];last=match.index+match[0].length;
  const c=classify(match[3],match[5]);if(!c)continue;
  const prior=adjacent.exec(original.slice(last));
  if(prior){
   const file=decodeURIComponent(prior[1].slice(10));
   if(!file.includes('/')&&!file.includes('\\')&&fs.existsSync(path.join(resources,file))){used.set(c.link,prior[1]);continue}
   last+=prior[0].length;
  }
  if(used.has(c.link)){const rel=used.get(c.link);if(rel)out+=' <span class="instant-local">· <a href="'+escape(rel)+'" download>Deschide local</a></span>';continue}
  if(count>=25){errors++;continue}
  fs.mkdirSync(resources,{recursive:true});
  if(fs.lstatSync(resources).isSymbolicLink())throw Error('Unsafe resource directory');
  const hash=crypto.createHash('sha256').update(c.link).digest('hex').slice(0,12),tmp=path.join(resources,'.document-'+hash+'.part');
  try{
   fs.rmSync(tmp,{force:true});
   const result=await fetcher(c.link,tmp,c.suffix);
   if(!EXT.has(result.suffix)||!fs.existsSync(tmp)||!fs.statSync(tmp).size)throw Error('Incomplete file');
   const base=name(result.name||c.caption).replace(/\.[a-z0-9]{2,7}$/i,'');
   const filename=base+'-'+hash+'.'+result.suffix,dest=path.join(resources,filename);
   if(!fs.existsSync(dest))fs.renameSync(tmp,dest);else fs.rmSync(tmp,{force:true});
   const rel='resources/'+encodeURIComponent(filename);used.set(c.link,rel);
   out+=' <span class="instant-local">· <a href="'+escape(rel)+'" download>Deschide local</a></span>';
   count++;
  }catch(e){fs.rmSync(tmp,{force:true});errors++;used.set(c.link,null);notify({type:'info',message:'Document offline indisponibil ('+String(e.message||e).slice(0,100)+'). Linkul original este pastrat.'})}
 }
 out+=original.slice(last);
 if(out!==original){const tmp=page+'.new';fs.writeFileSync(tmp,out,'utf8');fs.renameSync(tmp,page)}
 if(count){
  try{
   const p=path.join(dir,'lesson.json'),meta=JSON.parse(fs.readFileSync(p,'utf8'));
   const existing=fs.readdirSync(resources,{withFileTypes:true}).filter(x=>x.isFile()&&!x.name.endsWith('.part')).length;
   meta.resourcesCount=Math.max(Number(meta.resourcesCount||0),existing);fs.writeFileSync(p,JSON.stringify(meta,null,2),'utf8');
  }catch{}
 }
 return {downloaded:count,failed:errors};
}
async function archiveCourseDocuments(root,notify=()=>{},fetcher=download){
 let saved=0,failed=0;
 for(const dir of lessons(root)){
  try{const r=await processLesson(dir,notify,fetcher);saved+=r.downloaded;failed+=r.failed}
  catch(e){failed++;notify({type:'info',message:'Document archival error: '+String(e.message||e).slice(0,100)})}
 }
 notify({type:'info',message:'Documente offline: '+saved+' salvate, '+failed+' indisponibile. Linkurile originale au fost pastrate.'});
 return {saved,failed};
}
module.exports={archiveCourseDocuments,processLesson,classify,safeUrl,publicIp};

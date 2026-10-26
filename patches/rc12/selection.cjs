/* Reusable selection and scheduling core. No Skool account access here. */
'use strict';
function parseSelection(raw){
  if(!raw)return {level:'all',keys:[]};
  let obj;try{obj=JSON.parse(raw);}catch{throw Error('Selectie invalida');}
  if(!obj || !['courses','modules','all'].includes(obj.level) || !Array.isArray(obj.keys)) throw Error('Selectie invalida');
  const keys=[...new Set(obj.keys.map(v=>String(v)).filter(v=>/^[a-zA-Z0-9_.-]{1,128}$/.test(v)))];
  if(obj.level!=='all' && keys.length===0)throw Error('Selecteaza cel putin un element.');
  return {level:obj.level,keys};
}
function filterModuleTasks(tasks,selection){
  if(selection.level!=='modules')return tasks;
  const allowed=new Set(selection.keys.map(Number));
  return tasks.filter(t=>{const m=/^\[(\d+)\.(\d+)\]/.exec(t.title);return m&&allowed.has(Number(m[1]));});
}
async function runSelectedTasks(tasks, concurrency, selection, notify=()=>{}){
  const work=filterModuleTasks(tasks,selection);
  notify({type:'info',message:`Procesam ${work.length} lectii selectate din ${tasks.length}.`});
  let cursor=0;
  await Promise.all(Array.from({length:Math.min(Math.max(1,concurrency),4,work.length)},async()=>{
    while(cursor<work.length){const task=work[cursor++];await task.run();}
  }));
}

/**
 * Normalize all classroom cards returned by Skool. Privacy describes the
 * visibility policy of a course; it is NOT proof of missing member access.
 * Include private items in the selection UI, then let the authenticated
 * downloader verify entitlement when a course is opened.
 */
function catalogCourses(courses){
  if(!Array.isArray(courses)) throw Error('Course library is not a list');
  const result=[], seenKeys=new Set(), seenUrls=new Set();
  for(const entry of courses){
    if(!entry || typeof entry!=='object')continue;
    let u;
    try{u=new URL(String(entry.url||''));}catch{continue}
    if(u.protocol!=='https:' || !(u.hostname==='skool.com'||u.hostname.endsWith('.skool.com')))continue;
    if(u.pathname.split('/').filter(Boolean).indexOf('classroom')<0 || u.pathname.split('/').filter(Boolean).length<3)continue;
    u.search='';u.hash='';
    const url=u.toString(), key=String(entry.key||entry.id||entry.name||u.pathname.split('/').filter(Boolean).at(-1));
    if(!/^[a-zA-Z0-9_.-]{1,128}$/.test(key))continue;
    if(seenKeys.has(key)||seenUrls.has(url))continue;
    seenKeys.add(key);seenUrls.add(url);
    result.push({...entry,key,url,title:String(entry.title||entry.name||key),numModules:Number.isFinite(Number(entry.numModules))?Number(entry.numModules):0,accessStatus:entry.hasAccess===false?'unconfirmed':'available'});
  }
  return result;
}

// documentsApi. Bundled here so RC7/RC8/RC9 updaters accept the ZIP.
const documentsApi=(function(){
  const module={exports:{}};
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

  return module.exports;
})();

// uiApi. Bundled here so RC7/RC8/RC9 updaters accept the ZIP.
const uiApi=(function(){
  const module={exports:{}};
'use strict';
/* Archive presentation only: no network, no changes to video or lesson text. */
const fs=require('node:fs'),path=require('node:path');
const CSS=[
'body{font-family:Inter,"Segoe UI",system-ui,Arial,sans-serif!important;color:#182334;line-height:1.65;font-weight:400}',
'h1,h2,h3,.hero-title,.module-title{font-family:Inter,"Segoe UI",system-ui,Arial,sans-serif!important;letter-spacing:-.025em;line-height:1.28;font-weight:670}',
'.hero-title{font-size:clamp(1.75rem,3.4vw,2.5rem)!important}',
'.instant-lessons{display:flex!important;flex-direction:column!important;gap:16px!important;margin-top:22px!important}',
'.instant-lessons-head{display:flex;justify-content:space-between;align-items:center;gap:16px;flex-wrap:wrap;padding:0 2px 2px}',
'.instant-lessons-head h2{font-size:1.18rem!important;font-weight:680!important;margin:0!important;color:#182334}',
'.instant-start{display:inline-flex;align-items:center;justify-content:center;flex:0 0 auto;padding:10px 17px;border-radius:10px;background:#2362c9;color:#fff!important;text-decoration:none!important;font-weight:620;font-size:.9rem;line-height:1.4;margin:0!important;white-space:nowrap;box-shadow:none}',
'.instant-start:hover{background:#184d9f}',
'.instant-module{padding:18px 20px!important;border:1px solid #e2e7ef!important;border-radius:16px!important;background:#fff!important;box-shadow:0 6px 20px rgba(20,32,53,.045)!important;transform:none!important}',
'.instant-module:hover{transform:none!important;box-shadow:0 6px 20px rgba(20,32,53,.045)!important}',
'.instant-module-title{margin:0 0 14px!important;padding:0!important;display:flex;align-items:center;gap:8px;color:#24354d!important;font-size:1rem!important;line-height:1.35;font-weight:650!important}',
'.lesson-list{display:flex!important;flex-direction:column!important;grid-template-columns:none!important;grid-auto-flow:row!important;gap:7px!important;padding:0!important;margin:0!important;list-style:none!important;max-width:none!important}',
'.lesson-list .lesson{list-style:none!important}',
'.lesson-list .lesson a{display:flex!important;align-items:center!important;gap:12px!important;width:100%!important;min-height:51px!important;height:auto!important;padding:10px 12px!important;margin:0!important;border:1px solid #e5eaf2!important;border-radius:9px!important;background:#f8fafc!important;color:#25354d!important;text-decoration:none!important;box-shadow:none!important;font-size:.94rem!important;line-height:1.4!important;font-weight:540!important;transition:background .14s,border-color .14s!important;transform:none!important}',
'.lesson-list .lesson a::before{content:none!important}',
'.lesson-list .lesson a:hover{background:#eff5ff!important;border-color:#a7c3ef!important;transform:none!important}',
'.instant-lesson-num{display:inline-flex;flex:0 0 29px;align-items:center;justify-content:center;height:29px;background:#e9f0fb;border-radius:7px;color:#3765a9;font-size:.79rem;line-height:1;font-weight:650;font-variant-numeric:tabular-nums}',
'.instant-lesson-name{flex:1;min-width:0;overflow-wrap:anywhere}',
'.instant-chevron{font-size:1.18rem;color:#72869d;font-weight:400;margin-left:4px}',
'.instant-nav{display:flex;align-items:center;gap:9px;flex-wrap:wrap;margin:15px 0 20px!important;padding:0!important;border:0!important;background:transparent;justify-content:flex-start}',
'.instant-nav a{flex:0 0 auto!important;display:inline-flex!important;align-items:center!important;justify-content:center!important;width:auto!important;min-height:38px!important;height:38px!important;padding:8px 14px!important;gap:4px!important;border:1px solid #dbe3ef!important;border-radius:9px!important;background:#f9fbfe!important;color:#2e527b!important;font-size:.86rem!important;font-weight:590!important;text-decoration:none!important;white-space:nowrap;line-height:1.2!important;box-shadow:none!important}',
'.instant-nav a.instant-back{background:transparent!important;border-color:transparent!important;color:#56708b!important}',
'.instant-nav a.instant-next{margin-left:auto!important;border-color:#2362c9!important;background:#2362c9!important;color:white!important}',
'.instant-nav a:hover{filter:brightness(.96)}',
'.instant-nav small{display:none!important}',
'.instant-nav a:focus-visible,.instant-start:focus-visible,.lesson a:focus-visible{outline:3px solid #2362c9;outline-offset:3px}',
'.container .content{line-height:1.65}',
'@media(max-width:640px){.instant-lessons-head{align-items:flex-start}.instant-module{padding:14px 12px!important}.instant-nav{gap:5px}.instant-nav a{padding:8px 10px!important;font-size:.81rem!important}.instant-nav a.instant-next{margin-left:0!important}.instant-nav a.instant-back{order:3;flex-basis:100%!important;justify-content:flex-start!important;padding-left:4px!important}}',
'@media(prefers-reduced-motion:reduce){.lesson-list .lesson a{transition:none!important}}'
].join('\n');
function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function directory(p){try{return fs.lstatSync(p).isDirectory()&&!fs.lstatSync(p).isSymbolicLink()}catch{return false}}
function regular(p){try{return fs.lstatSync(p).isFile()&&!fs.lstatSync(p).isSymbolicLink()}catch{return false}}
function json(p){try{return JSON.parse(fs.readFileSync(p,'utf8'))}catch{return {}}}
function children(dir){return fs.readdirSync(dir,{withFileTypes:true}).filter(e=>e.isDirectory()&&!e.isSymbolicLink()&&!e.name.startsWith('_')&&!['assets','resources','node_modules','.auth'].includes(e.name))}
function href(from,to){return path.relative(from,to).split(path.sep).map(encodeURIComponent).join('/')}
function lessonList(course){
 const manifest=json(path.join(course,'.course.json'));
 const modules=Array.isArray(manifest.modules)?manifest.modules:[];
 const moduleOrder=new Map(modules.map((m,i)=>[String(m.moduleDirName||''),i]));
 const lessons=[];
 function visit(dir,depth){
  if(depth>3)return;
  const index=path.join(dir,'index.html'),metadata=path.join(dir,'lesson.json');
  if(regular(index)&&regular(metadata)){
   const d=json(metadata),pieces=path.relative(course,dir).split(path.sep),module=pieces.length>1?pieces[0]:'';
   const modNum=parseInt(module,10),fileNum=parseInt(path.basename(dir),10);
   const m=modules.find(m=>String(m.moduleDirName||'')===module);
   lessons.push({dir,index,module,title:String(d.title||path.basename(dir).replace(/^\d+-/,'')),
    moduleTitle:String(d.moduleTitle||m?.title||(module?module.replace(/^\d+-/,''):'Lessons')),
    mi:moduleOrder.has(module)?moduleOrder.get(module):Number.isFinite(Number(d.moduleIndex))?Number(d.moduleIndex):Number.isFinite(modNum)?modNum:9999,
    li:Number.isFinite(Number(d.lessonIndex))?Number(d.lessonIndex):Number.isFinite(fileNum)?fileNum:9999});
   return;
  }
  for(const e of children(dir))visit(path.join(dir,e.name),depth+1);
 }
 visit(course,0);
 // The module order from Skool's .course.json takes priority over folder names.
 lessons.sort((a,b)=>a.mi-b.mi||a.li-b.li||a.dir.localeCompare(b.dir,undefined,{numeric:true}));
 return lessons;
}
function language(lang){return lang==='ro'?{back:'Toate lecțiile',next:'Următoarea',prev:'Anterioara',start:'Începe cursul',lessons:'Lecții',fallback:'Lecții'}:{back:'All lessons',next:'Next lesson',prev:'Previous lesson',start:'Start course',lessons:'Lessons',fallback:'Lessons'};}
function linkLesson(from,l,label,kind){
 if(!l)return '';
 const glyph=kind==='next'?' →':'← ';
 return '<a class="instant-'+kind+'" href="'+esc(href(from,l.index))+'" rel="'+(kind==='next'?'next':'prev')+'" aria-label="'+esc(label+': '+l.title)+'">'+(kind==='next'?esc(label)+glyph:glyph+esc(label))+'</a>';
}
function nav(course,lessons,i,lang,place){
 const lesson=lessons[i],t=language(lang);
 return '<nav class="instant-nav" data-instant-place="'+place+'" aria-label="Lesson navigation">'
 +linkLesson(lesson.dir,lessons[i-1],t.prev,'prev')
 +'<a class="instant-back" href="'+esc(href(lesson.dir,path.join(course,'index.html')))+'">'+esc(t.back)+'</a>'
 +linkLesson(lesson.dir,lessons[i+1],t.next,'next')+'</nav>';
}
function addStyle(html){
 const style='<style id="instant-usability">\n'+CSS+'\n</style>';
 if(/<style id="instant-usability">[\s\S]*?<\/style>/i.test(html))return html.replace(/<style id="instant-usability">[\s\S]*?<\/style>/i,style);
 return html.replace(/<\/head>/i,style+'\n</head>');
}
function updateLesson(course,lessons,i,lang){
 const item=lessons[i],page=item.index;
 let html=fs.readFileSync(page,'utf8'),before=html;
 html=addStyle(html);
 const top=nav(course,lessons,i,lang,'top'),bottom=nav(course,lessons,i,lang,'bottom');
 html=html.replace(/<nav class="instant-nav" data-instant-place="top"[\s\S]*?<\/nav>\s*/i,'');
 const topAnchor=/(<div class="container">\s*<h1\b[^>]*>[\s\S]*?<\/h1>)/i;
 if(topAnchor.test(html))html=html.replace(topAnchor,'$1\n'+top);
 else html=html.replace(/(<div class="container">)/i,'$1\n'+top);
 if(/<nav class="instant-nav" data-instant-place="bottom"[\s\S]*?<\/nav>/i.test(html)){
  html=html.replace(/<nav class="instant-nav" data-instant-place="bottom"[\s\S]*?<\/nav>/i,bottom);
 }else if(/<div class="nav">\s*<a\b[^>]*>Back to Course Index<\/a>\s*<\/div>/i.test(html)){
  html=html.replace(/<div class="nav">\s*<a\b[^>]*>Back to Course Index<\/a>\s*<\/div>/i,bottom);
 }else{
  html=html.replace(/(<\/div>\s*<\/div>\s*<\/body>)/i,bottom+'\n$1');
 }
 html=html.replace(/>Back to Course Index</gi,'>'+esc(language(lang).back)+'<');
 if(html!==before)fs.writeFileSync(page,html,'utf8');
 return html!==before;
}
function courseSection(course,lessons,lang){
 const t=language(lang);
 const modules=new Map();
 for(const l of lessons){if(!modules.has(l.module))modules.set(l.module,[]);modules.get(l.module).push(l)}
 const start=lessons[0]?
  '<a class="instant-start" href="'+esc(href(course,lessons[0].index))+'">'+esc(t.start)+' →</a>':'';
 let html='<section class="content instant-lessons" data-instant-course="true"><div class="instant-lessons-head"><h2>'+esc(t.lessons)+'</h2>'+start+'</div>';
 for(const group of modules.values()){
  const title=group[0].moduleTitle||t.fallback;
  html+='<section class="module instant-module"><h3 class="instant-module-title">'+esc(title)+'</h3><ol class="lesson-list">';
  for(const lesson of group){
   const label=Number.isFinite(lesson.li)&&lesson.li>0&&lesson.li<100?String(lesson.li).padStart(2,'0'):String(group.indexOf(lesson)+1).padStart(2,'0');
   html+='<li class="lesson"><a href="'+esc(href(course,lesson.index))+'"><span class="instant-lesson-num">'+esc(label)+'</span><span class="instant-lesson-name">'+esc(lesson.title)+'</span><span class="instant-chevron" aria-hidden="true">›</span></a></li>';
  }
  html+='</ol></section>';
 }
 return html+'</section>';
}
function updateCourse(course,lessons,lang){
 const page=path.join(course,'index.html');if(!regular(page))return false;
 let html=fs.readFileSync(page,'utf8'),before=html;
 html=addStyle(html);
 // Remove RC10's start link, which was erroneously inserted inside nested hero stats.
 html=html.replace(/<a class="instant-start"[\s\S]*?<\/a>\s*/gi,'');
 const section=courseSection(course,lessons,lang);
 const opening=/<section\b[^>]*\bclass="content(?: instant-lessons)?"[^>]*>/i.exec(html);
 if(!opening){html=html.replace(/<\/body>/i,section+'\n</body>')}
 else {
  // Balance nested section tags so repeated Refresh doesn't duplicate modules.
  const tags=/<\/?section\b[^>]*>/gi;tags.lastIndex=opening.index+opening[0].length;
  let depth=1,end=-1,tag;
  while((tag=tags.exec(html))){
   if(/^<\/section/i.test(tag[0]))depth--;else depth++;
   if(depth===0){end=tags.lastIndex;break}
  }
  if(end<0)throw Error('Incomplete course section HTML');
  html=html.slice(0,opening.index)+section+html.slice(end);
 }
 html=html.replace(/>Course Archive</g,lang==='ro'?'>Biblioteca de cursuri<':'>Course library<');
 if(html!==before)fs.writeFileSync(page,html,'utf8');
 return html!==before;
}
function enhanceCourse(course,lang='en'){
 if(!directory(course))return {lessons:0,changed:0};
 const lessons=lessonList(course),t=lang==='ro'?'ro':'en';
 let changed=updateCourse(course,lessons,t)?1:0;
 for(let i=0;i<lessons.length;i++)if(updateLesson(course,lessons,i,t))changed++;
 return {lessons:lessons.length,changed};
}
function enhanceArchive(root,lang='en'){
 if(!directory(root))return {courses:0,lessons:0,changed:0};
 const results=[],stack=[{d:path.resolve(root),depth:0}];
 while(stack.length){
  const {d,depth}=stack.pop();if(depth>4)continue;
  if(regular(path.join(d,'.course.json'))){results.push(enhanceCourse(d,lang));continue}
  for(const x of children(d))stack.push({d:path.join(d,x.name),depth:depth+1});
 }
 return {courses:results.length,lessons:results.reduce((n,v)=>n+v.lessons,0),changed:results.reduce((n,v)=>n+v.changed,0)};
}
module.exports={enhanceCourse,enhanceArchive,lessonList,href};

  return module.exports;
})();

module.exports={parseSelection,filterModuleTasks,runSelectedTasks,catalogCourses,documentsApi,uiApi};
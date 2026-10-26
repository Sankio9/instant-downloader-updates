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
/* Offline-only HTML presentation layer: no network calls, no account data. */
const fs=require('node:fs'),path=require('node:path');

const CSS=[
'body {font-family: Inter, "Segoe UI", system-ui, -apple-system, Arial, sans-serif !important; font-weight:400; line-height:1.72; color:#17212f;}',
'h1,h2,h3,.hero-title,.module-title {font-family:Inter,"Segoe UI",system-ui,Arial,sans-serif !important; font-weight:720; letter-spacing:-0.025em; line-height:1.28;}',
'p,li,.content {line-height:1.72;}',
'.content a:focus-visible, .instant-nav a:focus-visible,.instant-start:focus-visible,.lesson a:focus-visible {outline:3px solid #175cd3;outline-offset:3px;}',
'.lesson-list {display:grid !important;grid-template-columns:repeat(auto-fit,minmax(min(100%,330px),1fr)) !important;gap:12px !important;counter-reset:lesson-number;}',
'.lesson {counter-increment:lesson-number;list-style:none;}',
'.lesson-list .lesson a {display:flex !important;align-items:center;gap:13px;padding:16px 18px !important;min-height:68px !important;background:#f7f9fd !important;border:1px solid #dce4ef !important;border-radius:13px !important;font-size:1.02rem !important;line-height:1.45 !important;font-weight:650 !important;color:#17212f !important;box-shadow:none !important;transition:background .15s,border-color .15s !important;text-decoration:none !important;}',
'.lesson-list .lesson a::before {content:counter(lesson-number, decimal-leading-zero);display:inline-flex;align-items:center;justify-content:center;flex:0 0 38px;min-width:38px;height:38px;border-radius:11px;background:#e3edff;color:#175cd3;font-size:.93rem;font-weight:750;font-variant-numeric:tabular-nums;}',
'.lesson-list .lesson a:hover {background:#eef4ff !important;border-color:#7a9fe4 !important;transform:none !important;}',
'.instant-nav {display:flex;align-items:stretch;gap:10px;flex-wrap:wrap;margin:20px 0 25px;padding:12px 0;border-top:1px solid #e1e7f0;border-bottom:1px solid #e1e7f0;}',
'.instant-nav a {display:flex;flex-direction:column;justify-content:center;gap:1px;min-height:50px;border:1px solid #d7e1f0;border-radius:11px;padding:9px 16px;text-decoration:none !important;font-weight:650;color:#174383 !important;background:#f7faff;flex:1 1 155px;}',
'.instant-nav a small {font-weight:440;font-size:.78rem;color:#54677c;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:260px;}',
'.instant-nav a.instant-next {border-color:#175cd3;background:#175cd3;color:white !important;}',
'.instant-nav a.instant-next small {color:#e6f0ff;}',
'.instant-nav a:hover {filter:brightness(.96);}',
'.instant-nav a.instant-back {flex:0 1 auto;background:white;}',
'.instant-start {display:inline-flex;align-items:center;margin-top:17px;padding:12px 19px;border-radius:11px;text-decoration:none !important;background:#175cd3;color:white !important;font-weight:700;}',
'.instant-start:hover {background:#114aab;}',
'@media(max-width:580px){.instant-nav {flex-direction:column;}.instant-nav a {flex:1 1 auto;}.lesson-list {grid-template-columns:1fr !important;}.lesson-list .lesson a {min-height:60px !important;}}',
'@media(prefers-reduced-motion:reduce){.lesson-list .lesson a,.instant-nav a{transition:none !important;}}'
].join('\n');
function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function directory(p){try{return fs.lstatSync(p).isDirectory()&&!fs.lstatSync(p).isSymbolicLink()}catch{return false}}
function regular(p){try{return fs.lstatSync(p).isFile()}catch{return false}}
function json(p){try{return JSON.parse(fs.readFileSync(p,'utf8'))}catch{return {}}}
function children(dir){return fs.readdirSync(dir,{withFileTypes:true}).filter(e=>e.isDirectory()&&!e.isSymbolicLink()&&!e.name.startsWith('_')&&!['assets','resources','node_modules','.auth'].includes(e.name));}
function href(from,to){return path.relative(from,to).split(path.sep).map(encodeURIComponent).join('/');}
function lessonList(course){
 const manifest=json(path.join(course,'.course.json'));
 const moduleOrder=new Map((Array.isArray(manifest.modules)?manifest.modules:[]).map((m,i)=>[String(m.moduleDirName||''),i]));
 const lessons=[];
 function visit(dir,depth){
  if(depth>3)return;
  const index=path.join(dir,'index.html'),metadata=path.join(dir,'lesson.json');
  if(regular(index)&&regular(metadata)){
   const d=json(metadata),pieces=path.relative(course,dir).split(path.sep),module=pieces.length>1?pieces[0]:'';
   const modNum=parseInt(module,10),fileNum=parseInt(path.basename(dir),10);
   lessons.push({dir,index,title:String(d.title||path.basename(dir).replace(/^\d+-/,'')),module,
    mi:moduleOrder.has(module)?moduleOrder.get(module):Number.isFinite(Number(d.moduleIndex))?Number(d.moduleIndex):Number.isFinite(modNum)?modNum:9999,
    li:Number.isFinite(Number(d.lessonIndex))?Number(d.lessonIndex):Number.isFinite(fileNum)?fileNum:9999});
   return;
  }
  for(const e of children(dir))visit(path.join(dir,e.name),depth+1);
 }
 visit(course,0);
 lessons.sort((a,b)=>a.mi-b.mi||a.li-b.li||a.dir.localeCompare(b.dir,undefined,{numeric:true}));
 return lessons;
}
function language(lang){return lang==='ro'?{back:'Înapoi la curs',next:'Lecția următoare',prev:'Lecția precedentă',start:'Începe cu lecția 01',overview:'Prezentarea cursului'}:{back:'Back to course',next:'Next lesson',prev:'Previous lesson',start:'Start with lesson 01',overview:'Course overview'};}
function navLink(from,lesson,label,kind){
 if(!lesson)return '';
 return '<a class="instant-'+kind+'" href="'+esc(href(from,lesson.index))+'" rel="'+(kind==='next'?'next':'prev')+'" aria-label="'+esc(label+': '+lesson.title)+'"><span>'+esc((kind==='next'?'': '← ')+label+(kind==='next'?' →':''))+'</span><small>'+esc(lesson.title)+'</small></a>';
}
function nav(course,lessons,i,lang,place){
 const current=lessons[i],t=language(lang),prev=lessons[i-1],next=lessons[i+1];
 return '<nav class="instant-nav" data-instant-place="'+place+'" aria-label="Lesson navigation">'
 +navLink(current.dir,prev,t.prev,'prev')
 +'<a class="instant-back" href="'+esc(href(current.dir,path.join(course,'index.html')))+'">'+esc(t.back)+'</a>'
 +navLink(current.dir,next,t.next,'next')+'</nav>';
}
function addStyle(html){
 const style='<style id="instant-usability">\n'+CSS+'\n</style>';
 if(/<style id="instant-usability">[\s\S]*?<\/style>/i.test(html))return html.replace(/<style id="instant-usability">[\s\S]*?<\/style>/i,style);
 return html.replace(/<\/head>/i,style+'\n</head>');
}
function updateLesson(course,lessons,i,lang){
 const lesson=lessons[i],page=lesson.index;
 let html=fs.readFileSync(page,'utf8'),before=html;html=addStyle(html);
 const top=nav(course,lessons,i,lang,'top'),bottom=nav(course,lessons,i,lang,'bottom');
 if(/<nav class="instant-nav" data-instant-place="top"[\s\S]*?<\/nav>/i.test(html)){
  html=html.replace(/<nav class="instant-nav" data-instant-place="top"[\s\S]*?<\/nav>/i,top);
 }else{
  html=html.replace(/(<div class="container">\s*)(<h1\b)/i,(_,start,title)=>start+top+'\n'+title);
 }
 if(/<nav class="instant-nav" data-instant-place="bottom"[\s\S]*?<\/nav>/i.test(html)){
  html=html.replace(/<nav class="instant-nav" data-instant-place="bottom"[\s\S]*?<\/nav>/i,bottom);
 }else if(/<div class="nav">\s*<a\b[^>]*>Back to Course Index<\/a>\s*<\/div>/i.test(html)){
  html=html.replace(/<div class="nav">\s*<a\b[^>]*>Back to Course Index<\/a>\s*<\/div>/i,bottom);
 }else{
  html=html.replace(/(<\/div>\s*<\/div>\s*<\/body>)/i,bottom+'\n$1');
 }
 // The underlying physical filenames remain index.html for relative links.
 html=html.replace(/>Back to Course Index</gi,'>'+esc(language(lang).back)+'<');
 if(html!==before)fs.writeFileSync(page,html,'utf8');
 return html!==before;
}
function updateCourse(course,lessons,lang){
 const page=path.join(course,'index.html');if(!regular(page))return false;
 let html=fs.readFileSync(page,'utf8'),before=html,t=language(lang);
 html=addStyle(html).replace(/>Course Archive</g,'>'+esc(t.overview)+'<');
 if(lessons.length){
  const start='<a class="instant-start" href="'+esc(href(course,lessons[0].index))+'">'+esc(t.start)+' →</a>';
  if(/<a class="instant-start"[\s\S]*?<\/a>/i.test(html))html=html.replace(/<a class="instant-start"[\s\S]*?<\/a>/i,start);
  else html=html.replace(/(<div class="hero-meta">[\s\S]*?<\/div>)/i,'$1\n'+start);
 }
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

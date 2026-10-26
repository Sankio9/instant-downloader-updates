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

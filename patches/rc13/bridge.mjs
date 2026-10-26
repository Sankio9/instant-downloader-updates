// Structured-output bridge for skool-downloader v1.0.0; authenticated locally.
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
// The login component is bundled here to support upgrades from 1.8 RC2/RC3.
// Local, visible Skool authentication. Does not upload credentials.
// A private Playwright context is used; only its local session files are saved.

async function loginSkool({chromium, authDir=path.join(process.cwd(),'.auth'), emit=()=>{}, timeoutMs=420000}={}){
  if (!chromium){
    // Resolve Playwright as a dependency of the pinned skool-downloader package,
    // whether npm hoisted it or kept it nested.
    const requireFromVendor=createRequire(path.join(process.cwd(),'node_modules','skool-downloader','package.json'));
    chromium=requireFromVendor('playwright').chromium;
  }
  const browsers=[
    {name:'Playwright Chromium', options:{headless:false}},
    {name:'Microsoft Edge', options:{headless:false,channel:'msedge'}},
    {name:'Google Chrome', options:{headless:false,channel:'chrome'}},
  ];
  let browser=null;
  const errors=[];
  for(const candidate of browsers){
    emit({type:'info',message:'Incerc browser: '+candidate.name});
    try{
      browser=await chromium.launch(candidate.options);
      emit({type:'info',message:'Browser pornit: '+candidate.name});
      break;
    }catch(e){
      // Never copy full error stacks or URLs into the UI (they may include tokens).
      const first=String(e?.message||e).split('\n')[0].slice(0,240);
      errors.push(candidate.name+': '+first);
      emit({type:'info',message:'Nu am putut porni '+candidate.name+'. Incerc alternativa.'});
    }
  }
  if(!browser){
    throw Error('Nu pot porni un browser pentru login. '+errors.join(' | '));
  }
  try{
    const context=await browser.newContext();
    const page=await context.newPage();
    emit({type:'info',message:'Se deschide https://www.skool.com/login. Autentifica-te in fereastra aparuta.'});
    await page.goto('https://www.skool.com/login',{waitUntil:'domcontentloaded',timeout:60000});
    emit({type:'info',message:'Astept autentificarea. Dupa login, pagina Skool trebuie sa se deschida.'});
    await page.waitForURL(url=>{
      const h=url.hostname.toLowerCase();
      const p=url.pathname.toLowerCase();
      return (h==='skool.com' || h==='www.skool.com') && !p.includes('/login') && !p.includes('/signup');
    },{timeout:timeoutMs});
    const state=await context.storageState();
    const cookies=Array.isArray(state?.cookies)?state.cookies:[];
    const relevant=cookies.some(c=>typeof c.domain==='string' && (c.domain==='skool.com'||c.domain.endsWith('.skool.com')));
    if(!relevant)throw Error('Pagina a fost deschisa, dar nu exista cookie-uri Skool. Autentificarea nu a fost confirmata.');
    fs.mkdirSync(authDir,{recursive:true});
    const statePath=path.join(authDir,'storage_state.json');
    const cookiesPath=path.join(authDir,'cookies.txt');
    const mkSafe=s=>String(s??'').replace(/[\r\n\t]/g,'');
    const netscape=['# Netscape HTTP Cookie File','# Created locally by Instant Downloader; private session.',''];
    for(const c of cookies){
      if(!c||!c.name||!c.domain)continue;
      const domain=mkSafe(c.domain);
      const cookiePath=mkSafe(c.path||'/');
      const exp=Number(c.expires);
      netscape.push([domain.startsWith('.')?domain:'.'+domain,'TRUE',cookiePath,c.secure?'TRUE':'FALSE',Number.isFinite(exp)&&exp>0?Math.floor(exp):0,mkSafe(c.name),mkSafe(c.value)].join('\t'));
    }
    // Save only after verified success; never replace a valid state on login failure.
    const suffix='.new-'+process.pid;
    const stateTmp=statePath+suffix, cookiesTmp=cookiesPath+suffix;
    try{
      fs.writeFileSync(stateTmp,JSON.stringify(state),'utf8');
      fs.writeFileSync(cookiesTmp,netscape.join('\n')+'\n','utf8');
      fs.renameSync(stateTmp,statePath);
      fs.renameSync(cookiesTmp,cookiesPath);
    }finally{
      try{fs.rmSync(stateTmp,{force:true})}catch{}
      try{fs.rmSync(cookiesTmp,{force:true})}catch{}
    }
    emit({type:'login-success',message:'Sesiunea Skool a fost salvata local.'});
    return {ok:true,authDir};
  }finally{
    await browser.close().catch(()=>{});
  }
}

import selectionApi from './selection.cjs';
import auditApi from './audit_archive.cjs';
const documentsApi=selectionApi.documentsApi;
const uiApi=selectionApi.uiApi;
let archiveLanguage='en';
try{const c=JSON.parse(fs.readFileSync(path.join(process.cwd(),'config.json'),'utf8'));if(c.language==='ro')archiveLanguage='ro'}catch{}
const selection=selectionApi.parseSelection(process.env.SKOOL_SELECTION_JSON || '');
const selectedRunner=(tasks,n)=>selectionApi.runSelectedTasks(tasks,n,selection,evt);
const [mode, inputUrl, outputRoot] = process.argv.slice(2);
function evt(data){process.stdout.write('@@SKOOL@@'+JSON.stringify(data)+'\n');}
function cleanName(name){const cleaned=String(name || 'Fara nume').replace(/[\\/?%*:|"<>]/g,'-').replace(/[. ]+$/g,'').trim().slice(0,120); return cleaned || 'Fara nume';}
const logger = {
  info:()=>{},debug:()=>{},warn:(s)=>evt({type:'info',message:String(s).replace(/https?:\/\/\S+/g,'[link]')}),
  error:(s,e)=>evt({type:'error',message:(String(s)+' '+String(e||'')).replace(/https?:\/\/\S+/g,'[link]')})
};
function isRoot(url){try{const p=new URL(url).pathname.split('/').filter(Boolean);return p[p.length-1]==='classroom';}catch{return false;}}
async function makeRootIndex(root){
  if(!fs.existsSync(root))return;
  const list=[];
  for(const group of fs.readdirSync(root,{withFileTypes:true})){
    if(!group.isDirectory() || group.name.startsWith('.') || group.name.startsWith('_'))continue;
    const gp=path.join(root,group.name);
    for(const course of fs.readdirSync(gp,{withFileTypes:true})){
      if(!course.isDirectory() || course.name.startsWith('.') || course.name.startsWith('_'))continue;
      const cp=path.join(gp,course.name);
      if(!fs.existsSync(path.join(cp,'.course.json'))) continue;
      const order=uiApi.courseOrder(gp).lookup;
      let meta={};
      try{meta=JSON.parse(fs.readFileSync(path.join(cp,'.course.json'),'utf8'))}catch{}
      const name=String(meta.courseName||course.name);
      const position=order.has(name.normalize('NFKC').trim().replace(/\s+/g,' ').toLocaleLowerCase())
        ?order.get(name.normalize('NFKC').trim().replace(/\s+/g,' ').toLocaleLowerCase()):Number.MAX_SAFE_INTEGER;
      list.push({group:group.name,name,position,href:encodeURIComponent(group.name)+'/'+encodeURIComponent(course.name)+'/index.html'});
    }
  }
  list.sort((a,b)=>a.group.localeCompare(b.group)||a.position-b.position||a.name.localeCompare(b.name));
  const escapeHtml=(s)=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const cards=list.map(c=>`<a class="course" href="${c.href}"><small>${escapeHtml(c.group)}</small><strong>${escapeHtml(c.name)}</strong><span>Open course →</span></a>`).join('\n');
  const html=`<!doctype html><html lang="ro"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Course library</title><style>body{font:16px system-ui,sans-serif;background:#f4f5f7;color:#181b24;max-width:1020px;margin:52px auto;padding:0 20px}h1{font-size:36px}p{color:#687282}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px}.course{color:inherit;text-decoration:none;background:#fff;border:1px solid #e2e5ea;border-radius:16px;padding:24px;display:flex;flex-direction:column;min-height:120px;box-shadow:0 4px 16px #0000000c}.course:hover{border-color:#8299da}.course small{color:#6573a3;margin-bottom:10px}.course strong{font-size:22px}.course span{font-size:13px;color:#546b95;margin-top:auto;padding-top:22px}</style></head><body><h1>Course library</h1><p>${list.length} cursuri disponibile offline</p><main>${cards||'<p>Nu sunt cursuri descărcate încă.</p>'}</main></body></html>`;
  fs.writeFileSync(path.join(root,'index.html'),html,'utf8');
  evt({type:'index',count:list.length});
}
async function scanCatalog(url){
  const u=new URL(url);
  if(u.protocol!=='https:' || !/(^|\.)skool\.com$/i.test(u.hostname)) throw Error('Link Skool invalid');
  const {Scraper}=await import('./node_modules/skool-downloader/src/scraper.ts');
  const scraper=new Scraper(logger);
  try{
    if(isRoot(url)){
      const lib=await scraper.parseCourseLibrary(url);
      // Keep private classroom cards visible. privacy>0 is not an access denial.
      const courses=selectionApi.catalogCourses(lib.courses);
      // Choose sections is authoritative for course ordering, including
      // partially downloaded archives that need their existing cards reordered.
      if(outputRoot&&path.isAbsolute(outputRoot)){
        const groupDir=path.join(outputRoot,cleanName(lib.groupName));
        uiApi.saveClassroomOrder(groupDir,courses);
        uiApi.reorderCommunityPage(groupDir);
      }
      const items=courses.map(c=>({
        key:String(c.key),title:c.title,count:c.numModules,
        accessStatus:c.accessStatus
      }));
      evt({type:'info',message:`Classroom catalog: ${lib.courses.length} source courses; ${courses.length} valid unique cards; ${courses.filter(c=>c.privacy>0).length} private cards retained.`});
      evt({type:'catalog',level:'courses',name:lib.groupName,items});
    }else{
      const c=await scraper.parseClassroom(url);
      evt({type:'catalog',level:'modules',name:c.courseName,items:c.modules.map(m=>({key:String(m.index),title:m.title,count:m.lessons.length}))});
    }
  }finally{await scraper.close();}
}
async function startDownload(url,root){
  const u=new URL(url);
  if(!['https:','http:'].includes(u.protocol) || !/(^|\.)skool\.com$/i.test(u.hostname))throw Error('Introdu un link Skool valid.');
  if(!root || !path.isAbsolute(root))throw Error('Folder de salvare invalid.');
  fs.mkdirSync(root,{recursive:true});
  const callbacks = {
    onCourseStart: v=>evt({type:'course',title:v.courseName,group:v.groupName,lessons:v.lessonsCount}),
    onLessonStart: v=>evt({type:'start',id:v.moduleIndex+'.'+v.lessonIndex,title:v.lessonTitle}),
    onLessonComplete: v=>evt({type:'done',id:v.moduleIndex+'.'+v.lessonIndex,title:v.lessonTitle,hasVideo:v.hasVideo,resourcesCount:v.resourcesCount||0}),
    onLessonError: v=>evt({type:'failed',id:v.moduleIndex+'.'+v.lessonIndex,title:v.lessonTitle,reason:String(v.error||'Error')})
  };
  const {downloadCourse}=await import('./node_modules/skool-downloader/src/index.ts');
  let fails=0;
  if(isRoot(url)) {
    const {Scraper}=await import('./node_modules/skool-downloader/src/scraper.ts');
  const scraper=new Scraper(logger);
    let library;
    try{library=await scraper.parseCourseLibrary(url);}finally{await scraper.close();}
    // Match the exact same catalog displayed in Choose sections. Attempt downloads
    // through the authenticated Skool session; inaccessible courses report errors.
    let courses=selectionApi.catalogCourses(library.courses);
    const groupDir=path.join(root,cleanName(library.groupName));
    uiApi.saveClassroomOrder(groupDir,courses);
    if(selection.level==='courses'){
      const ids=new Set(selection.keys);
      courses=courses.filter(c=>ids.has(String(c.key)));
      const found=new Set(courses.map(c=>String(c.key)));
      const notFound=selection.keys.filter(k=>!found.has(k));
      if(notFound.length)evt({type:'info',message:`Some selected courses were not present in the latest classroom scan (${notFound.length}). Nothing will be substituted.`});
    }
    evt({type:'info',message:`${courses.length} cursuri disponibile`});
    for(const course of courses){
      const target=path.join(groupDir, cleanName(course.title));
      try{const result=await downloadCourse({url:course.url,outputDir:target,concurrency:4,mode:'course',logger,callbacks,suppressIndexLogs:true});
        fails+=result.failedLessons;
        const docs=await documentsApi.archiveCourseDocuments(target,evt);
        fails+=docs.failed;
        const presentation=uiApi.enhanceCourse(target,archiveLanguage);
        evt({type:'info',message:'Course pages ready: '+presentation.lessons+' lessons.'});
      }catch(err){fails++;evt({type:'error',message:'Eroare curs '+course.title+': '+String(err)});}
      uiApi.reorderCommunityPage(groupDir);
      await makeRootIndex(root);
    }
  }else{
    // A single course still keeps Community / Course hierarchy; inspect manifest result after download.
    // The downloader determines names while scraping, so first save to a temporary course-specific path,
    // then move to the correct final hierarchy (no overwrite on resuming).
    const {Scraper}=await import('./node_modules/skool-downloader/src/scraper.ts');
  const scraper=new Scraper(logger);
    let structure;
    try{structure=await scraper.parseClassroom(url);}finally{await scraper.close();}
    const target=path.join(root,cleanName(structure.groupName),cleanName(structure.courseName));
    const result=await downloadCourse({url,outputDir:target,concurrency:4,mode:'auto',logger,callbacks,suppressIndexLogs:true,runTasks: selection.level==='modules' ? selectedRunner : undefined});
    fails+=result.failedLessons;
    const docs=await documentsApi.archiveCourseDocuments(target,evt);
    fails+=docs.failed;
    const presentation=uiApi.enhanceCourse(target,archiveLanguage);
    evt({type:'info',message:'Course pages ready: '+presentation.lessons+' lessons.'});
    uiApi.reorderCommunityPage(path.dirname(target));
    await makeRootIndex(root);
  }
  let auditFailures=0;
  try{
    const audit=auditApi.audit(root);
    auditFailures=audit.incomplete+audit.invalid;
    evt({type:'audit',lessons:audit.lessons,complete:audit.complete,incomplete:audit.incomplete,invalid:audit.invalid,issues:audit.issues.slice(0,50)});
  }catch(error){auditFailures=1;evt({type:'error',message:'Audit offline indisponibil: '+String(error?.message||error)});}
  evt({type:'complete',failed: fails+auditFailures});
}
try {
  if(mode==='login'){
    evt({type:'info',message:'Se deschide pagina oficiala Skool pentru autentificare...'});
    await loginSkool({emit:evt});
  }else if(mode==='verify-ytdlp'){
    const {updateYtDlp}=await import('./node_modules/skool-downloader/src/downloader.ts');
    const v=await updateYtDlp();
    evt({type:'info',message:'yt-dlp pregatit: '+(v.to||'OK')});
  }else if(mode==='scan')await scanCatalog(inputUrl);
  else if(mode==='download')await startDownload(inputUrl,outputRoot);
  else if(mode==='index'){await makeRootIndex(outputRoot);const reordered=uiApi.refreshCommunityPages(outputRoot);evt({type:'info',message:'Community order synchronized: '+reordered.groups+' libraries.'});const result=uiApi.enhanceArchive(outputRoot,archiveLanguage);evt({type:'info',message:'Course pages refreshed: '+result.courses+' courses, '+result.lessons+' lessons.'});}
  else throw Error('Comanda necunoscuta: '+mode);
} catch(e){evt({type:'fatal',message:String(e?.message||e)});process.exitCode=1;}

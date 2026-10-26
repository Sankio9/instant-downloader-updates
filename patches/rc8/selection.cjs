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
module.exports={parseSelection,filterModuleTasks,runSelectedTasks,catalogCourses};

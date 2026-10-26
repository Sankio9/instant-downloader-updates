'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const api=require('./selection.cjs').uiApi;
const root=fs.mkdtempSync(path.join(os.tmpdir(),'instant-order-'));
function put(file,value){fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,value,'utf8')}
function get(file){return fs.readFileSync(file,'utf8')}
try{
 const group=path.join(root,'expert-dropshipping-shopify');
 const names=['EVIDENȚĂ CONTABILĂ','INTRODUCERE','FACEBOOK ADS'];
 for(const name of names){put(path.join(group,name,'.course.json'),JSON.stringify({courseName:name,groupName:'Expert Dropshipping Shopify',modules:[{moduleDirName:'1-Lessons',title:'Lessons'}]}))}
 const card=name=>'<a class="course-card" href="'+name+'/index.html"><div class="course-image"><img src="'+name+'/assets/cover.png"></div><div class="course-body"><h2>'+name+'</h2></div></a>';
 const source='<html><head><title>Courses</title></head><body><section class="courses">'+
  [names[0],names[2],names[1]].map(card).join('\n')+'</section></body></html>';
 put(path.join(group,'index.html'),source);
 assert.equal(api.reorderCommunityPage(group).ordered,false,'Missing catalog order must not invent Skool order');
 assert.equal(api.saveClassroomOrder(group,[
  {key:'intro',title:'INTRODUCERE'},
  {key:'choose-niche',title:'ALEGEREA NIȘEI ȘI ÎNȚELEGEREA CLIENTULUI'},
  {key:'shopify',title:'CONFIGURAREA ȘI LANSAREA MAGAZINULUI SHOPIFY'},
  {key:'facebook',title:'FACEBOOK ADS'},
  {key:'accounting',title:'EVIDENȚĂ CONTABILĂ'}
 ]),true);
 const changed=api.reorderCommunityPage(group);
 assert.deepEqual(changed,{cards:3,changed:true,ordered:true});
 const html=get(path.join(group,'index.html'));
 const intro=html.indexOf('href="INTRODUCERE/index.html"');
 const fb=html.indexOf('href="FACEBOOK ADS/index.html"');
 const accounting=html.indexOf('href="EVIDENȚĂ CONTABILĂ/index.html"');
 assert.ok(intro>=0&&fb>intro&&accounting>fb,'Order must follow Skool list; missing/unarchived courses must not get fake cards');
 assert.equal((html.match(/class="course-card"/g)||[]).length,3,'All offline course cards preserved');
 assert.equal((html.match(/assets\/cover.png/g)||[]).length,3,'Course thumbnails preserved');
 assert.equal(api.reorderCommunityPage(group).changed,false,'Reordering must be idempotent');
 assert.equal(api.saveClassroomOrder(group,api.loadClassroomOrder(group)),false,'Unchanged Skool order is not rewritten');
 assert.deepEqual(api.refreshCommunityPages(root),{groups:1,reordered:0});
 const course=path.join(group,'INTRODUCERE');
 put(path.join(course,'index.html'),'<html><head><title>Intro course</title></head><body><section class="hero"><h1>INTRODUCERE</h1><div class="hero-meta"></div></section><section class="content"><div class="module"><p>Original content</p></div></section></body></html>');
 const lessons=[
  {mod:'1-Lessons',dir:'1-Prima lecție',title:'Prima lecție',mi:1,li:1},
  {mod:'1-Lessons',dir:'2-Second',title:'A doua lecție',mi:1,li:2},
  {mod:'2-Advanced',dir:'1-Third',title:'Lecție avansată',mi:2,li:1}
 ];
 const manifest={courseName:'INTRODUCERE',modules:[{moduleDirName:'1-Lessons',title:'Introducere'},{moduleDirName:'2-Advanced',title:'Avansat'}]};
 put(path.join(course,'.course.json'),JSON.stringify(manifest));
 for(const l of lessons){
  const dir=path.join(course,l.mod,l.dir);
  put(path.join(dir,'lesson.json'),JSON.stringify({title:l.title,moduleIndex:l.mi,lessonIndex:l.li,moduleTitle:l.mod==='1-Lessons'?'Introducere':'Avansat'}));
  put(path.join(dir,'index.html'),'<html><head><title>'+l.title+'</title></head><body><div class="page"><div class="container"><h1>'+l.title+'</h1><p>Text</p><video src="video.mp4"></video><div class="nav"><a href="../../index.html">Back to Course Index</a></div></div></div></body></html>');
 }
 assert.deepEqual(api.enhanceCourse(course,'en'),{lessons:3,changed:4});
 const one=get(path.join(course,'1-Lessons','1-Prima lecție','index.html'));
 const two=get(path.join(course,'1-Lessons','2-Second','index.html'));
 const third=get(path.join(course,'2-Advanced','1-Third','index.html'));
 for(const page of [one,two,third]){
  assert.equal((page.match(/<aside class="instant-sidebar"/g)||[]).length,1,'Exactly one sidebar');
  assert.equal((page.match(/<a\b[^>]*aria-current="page"/g)||[]).length,1,'Current lesson highlighted exactly once');
  assert.equal((page.match(/data-instant-place=/g)||[]).length,2,'Top/bottom navigation retained');
  assert.ok(page.includes('class="container instant-reading"'));
  assert.ok(page.includes('video.mp4'));
  assert.ok(page.includes('@media(max-width:790px)'),'Responsive sidebar fallback');
 }
 assert.equal((one.match(/class="instant-sidebar-name"/g)||[]).length,2,'Only current module lessons are shown');
 assert.equal((third.match(/class="instant-sidebar-name"/g)||[]).length,1,'Next module has its own navigation list');
 assert.match(one,/aria-current="page"[^>]*>[\s\S]*?01[\s\S]*?Prima lecție/);
 assert.match(two,/href="\.\.\/1-Prima%20lec%C8%9Bie\/index.html"/,'Sidebar URLs encode Romanian filenames');
 assert.ok(!one.includes('Lecție avansată'),'Sidebar should not show other modules');
 assert.match(two,/href="\.\.\/\.\.\/2-Advanced\/1-Third\/index.html"/,'Next lesson still crosses modules');
 assert.deepEqual(api.enhanceCourse(course,'en'),{lessons:3,changed:0},'Second refresh should not rewrite pages');
 const ro=api.enhanceCourse(course,'ro');
 assert.equal(ro.lessons,3);
 const localized=get(path.join(course,'1-Lessons','2-Second','index.html'));
 assert.match(localized,/Toate lecțiile/);
 assert.equal((localized.match(/<aside class="instant-sidebar"/g)||[]).length,1);
 assert.equal((localized.match(/data-instant-place=/g)||[]).length,2);
 console.log('PASS Skool order from Choose sections, offline cards preserved, module sidebar current marker, bilingual nav, responsive, idempotent refresh');
} finally{fs.rmSync(root,{recursive:true,force:true})}

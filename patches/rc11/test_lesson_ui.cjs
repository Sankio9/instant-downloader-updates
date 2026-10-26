'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {enhanceCourse,enhanceArchive,lessonList}=require('./selection.cjs').uiApi;
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'instant-usability-'));
try{
 const root=path.join(temp,'Library'),group=path.join(root,'Expert Shopify'),course=path.join(group,'Evidenta-contabila');
 fs.mkdirSync(course,{recursive:true});
 fs.writeFileSync(path.join(course,'.course.json'),JSON.stringify({modules:[{moduleDirName:'1-Start'},{moduleDirName:'2-Learn'}]}));
 const overview='<!doctype html><html><head><style>body{font-family:"Space Grotesk"}</style></head><body><section class="hero"><h1>Course</h1><p>Course Archive</p><div class="hero-meta"><b>4 lessons</b></div></section><section class="content"><div class="module"><ul class="lesson-list"><li class="lesson"><a href="1-Start/1-Primă lecție/index.html">Primă lecție</a></li><li class="lesson"><a href="1-Start/2-Second/index.html">Second</a></li></ul></div><div class="module"><ul class="lesson-list"><li class="lesson"><a href="2-Learn/1-Third/index.html">Third</a></li><li class="lesson"><a href="2-Learn/2-Fourth/index.html">Fourth</a></li></ul></div></section></body></html>';
 fs.writeFileSync(path.join(course,'index.html'),overview);
 const items=[['1-Start','1-Primă lecție','Primă lecție',1,1],['1-Start','2-Second','Second',1,2],['2-Learn','1-Third','Third',2,1],['2-Learn','2-Fourth','Fourth',2,2]];
 const lessonTemplate=title=>'<!doctype html><html><head><title>'+title+'</title><style>body{font-family:"Space Grotesk"}</style></head><body><div class="page"><div class="breadcrumb">Cours</div><div class="container"><h1>'+title+'</h1><video controls src="video.mp4"></video><div class="content"><a href="https://example.org/file.pdf">Original file</a><a href="resources/attachment.pdf">Deschide local</a></div><div class="nav"><a href="../../index.html">Back to Course Index</a></div></div></div></body></html>';
 for(const [module,dir,title,mi,li] of items){
  const p=path.join(course,module,dir);fs.mkdirSync(path.join(p,'resources'),{recursive:true});
  fs.writeFileSync(path.join(p,'lesson.json'),JSON.stringify({title,moduleIndex:mi,lessonIndex:li}));
  fs.writeFileSync(path.join(p,'resources','attachment.pdf'),'example bytes');
  fs.writeFileSync(path.join(p,'index.html'),lessonTemplate(title));
 }
 const summary=enhanceCourse(course,'en');
 assert.deepEqual(summary,{lessons:4,changed:5});
 const first=fs.readFileSync(path.join(course,items[0][0],items[0][1],'index.html'),'utf8');
 const second=fs.readFileSync(path.join(course,items[1][0],items[1][1],'index.html'),'utf8');
 const third=fs.readFileSync(path.join(course,items[2][0],items[2][1],'index.html'),'utf8');
 const last=fs.readFileSync(path.join(course,items[3][0],items[3][1],'index.html'),'utf8');
 const courseHtml=fs.readFileSync(path.join(course,'index.html'),'utf8');
 for(const s of [first,second,third,last]){
  assert.equal((s.match(/data-instant-place=/g)||[]).length,2,'top/bottom navigation');
  assert.match(s,/font-family: Inter/i);
  assert.match(s,/Back to course/);
  assert.doesNotMatch(s,/>Back to Course Index</i);
  assert.match(s,/<video controls src="video.mp4"/);
  assert.match(s,/resources\/attachment.pdf/);
  assert.match(s,/https:\/\/example.org\/file.pdf/);
 }
 assert.equal((first.match(/<span>Next lesson →<\/span>/g)||[]).length,2);
 assert.ok(!first.includes('Previous lesson'));
 assert.ok((second.match(/href="\.\.\/\.\.\/2-Learn\/1-Third\/index.html"/g)||[]).length>=2,'cross-module next link');
 assert.ok((third.match(/href="\.\.\/\.\.\/1-Start\/2-Second\/index.html"/g)||[]).length>=2,'cross-module previous link');
 assert.equal((last.match(/<span>← Previous lesson<\/span>/g)||[]).length,2);
 assert.ok(!last.includes('Next lesson'));
 assert.ok(courseHtml.includes('counter(lesson-number, decimal-leading-zero)'));
 assert.ok(courseHtml.includes('Start with lesson 01'));
 assert.deepEqual(enhanceCourse(course,'en'),{lessons:4,changed:0},'reruns must not duplicate any navigation');
 const updated=enhanceArchive(root,'ro');
 assert.equal(updated.courses,1);assert.equal(updated.lessons,4);
 const ro=fs.readFileSync(path.join(course,items[1][0],items[1][1],'index.html'),'utf8');
 assert.equal((ro.match(/<span>Lecția următoare →<\/span>/g)||[]).length,2);
 assert.equal((ro.match(/>Înapoi la curs<\/a>/g)||[]).length,2);
 assert.equal((ro.match(/data-instant-place=/g)||[]).length,2);
 assert.equal(lessonList(course).length,4);
 console.log('PASS offline usability: numbered courses, readable fonts, top/bottom Prev/Next across modules, Romanian labels, safe rerun, original video/resources');
}finally{fs.rmSync(temp,{recursive:true,force:true})}

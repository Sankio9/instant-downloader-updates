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
  assert.match(s,/font-family:\s*Inter/i);
  assert.match(s,/All lessons/);
  assert.doesNotMatch(s,/>Back to Course Index</i);
  assert.match(s,/<video controls src="video.mp4"/);
  assert.match(s,/resources\/attachment.pdf/);
  assert.match(s,/https:\/\/example.org\/file.pdf/);
 }
 assert.equal((first.match(/<a class="instant-next"/g)||[]).length,2);
 assert.ok(!first.includes('Previous lesson'));
 assert.ok((second.match(/href="\.\.\/\.\.\/2-Learn\/1-Third\/index.html"/g)||[]).length>=2,'cross-module next link');
 assert.ok((third.match(/href="\.\.\/\.\.\/1-Start\/2-Second\/index.html"/g)||[]).length>=2,'cross-module previous link');
 assert.equal((last.match(/<a class="instant-prev"/g)||[]).length,2);
 assert.ok(!last.includes('Next lesson'));
 assert.ok(courseHtml.includes('class="instant-lesson-num"'));
 assert.equal((courseHtml.match(/class="instant-lesson-name"/g)||[]).length,4);
 assert.ok(courseHtml.includes('grid-template-columns:none'));
 assert.ok(courseHtml.indexOf('class="instant-start"')>courseHtml.indexOf('class="content instant-lessons"'));
 assert.ok(courseHtml.includes('Start course →'));
 assert.deepEqual(enhanceCourse(course,'en'),{lessons:4,changed:0},'reruns must not duplicate any navigation');
 const rerendered=fs.readFileSync(path.join(course,'index.html'),'utf8');
 assert.equal((rerendered.match(/class="instant-module"/g)||[]).length,0,'Module class has additional original class');
 assert.equal((rerendered.match(/class="module instant-module"/g)||[]).length,2,'Refresh must preserve exactly two modules');
 assert.equal((rerendered.match(/class="instant-start"/g)||[]).length,1,'Only one start button');
 const updated=enhanceArchive(root,'ro');
 assert.equal(updated.courses,1);assert.equal(updated.lessons,4);
 const ro=fs.readFileSync(path.join(course,items[1][0],items[1][1],'index.html'),'utf8');
 assert.equal((ro.match(/<a class="instant-next"/g)||[]).length,2);
 assert.equal((ro.match(/>Toate lecțiile<\/a>/g)||[]).length,2);
 assert.equal((ro.match(/data-instant-place=/g)||[]).length,2);
 assert.equal(lessonList(course).length,4);
 // Simulate a Skool reordering that does not match existing file/folder order.
 // .course.json and lesson.json, not the saved HTML grid, are the source of truth.
 const firstMeta=path.join(course,'1-Start','1-Primă lecție','lesson.json');
 const secondMeta=path.join(course,'1-Start','2-Second','lesson.json');
 const one=JSON.parse(fs.readFileSync(firstMeta,'utf8'));
 const two=JSON.parse(fs.readFileSync(secondMeta,'utf8'));
 one.lessonIndex=2;two.lessonIndex=1;
 fs.writeFileSync(firstMeta,JSON.stringify(one));fs.writeFileSync(secondMeta,JSON.stringify(two));
 enhanceCourse(course,'en');
 const reordered=fs.readFileSync(path.join(course,'index.html'),'utf8');
 const lpos=reordered.indexOf('class="instant-lesson-name">Second');
 const rpos=reordered.indexOf('class="instant-lesson-name">Primă lecție');
 assert.ok(lpos>=0&&rpos>lpos,'Visible course order must follow Skool lessonIndex metadata');
 assert.ok(reordered.includes('href="1-Start/2-Second/index.html">Start course'), 'Start leads to the first Skool-order lesson');
 assert.equal((reordered.match(/class="instant-start"/g)||[]).length,1,'Only one compact CTA after refresh');
 assert.equal((reordered.match(/class="module instant-module"/g)||[]).length,2,'Exactly two modules after repeat refresh');
 assert.match(reordered,/flex:0 0 auto!important/,'Next/Previous must stay compact');
 console.log('PASS offline usability: numbered courses, readable fonts, top/bottom Prev/Next across modules, Romanian labels, safe rerun, original video/resources');
}finally{fs.rmSync(temp,{recursive:true,force:true})}

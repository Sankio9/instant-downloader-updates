'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const docs=require('./selection.cjs').documentsApi,{audit}=require('./audit_archive.cjs');
const root=fs.mkdtempSync(path.join(os.tmpdir(),'instant-doc-'));
(async()=>{
 try{
  const lesson=path.join(root,'Community','Course','Module','Lesson');
  fs.mkdirSync(lesson,{recursive:true});
  fs.writeFileSync(path.join(lesson,'lesson.json'),JSON.stringify({title:'EVIDENTA CONTABILA',hasVideo:false,resourcesCount:0}));
  const a='https://files.example.org/Model_Evidenta_Etsy_Persoana_Fizica.xlsx?download=1';
  const google='https://docs.google.com/spreadsheets/d/AbCdEfGhIjKlMnOpQrStUv/edit';
  fs.writeFileSync(path.join(lesson,'index.html'),
  '<h1>EVIDENTA CONTABILA</h1><a href="'+a+'">Model_Evidenta_Etsy_Persoana_Fizica_</a> | <a href="'+google+'">Spreadsheet</a> | <a href="https://example.org/">Website</a>');
  let count=0;
  const downloader=async(url,out,suffix)=>{
   count++;fs.writeFileSync(out,'Mock spreadsheet contents');return {name: count===1?'Model_Evidenta.xlsx':'Sheet.xlsx',suffix:'xlsx'};
  };
  const result=await docs.archiveCourseDocuments(root,()=>{},downloader);
  assert.deepEqual(result,{saved:2,failed:0});
  const page=fs.readFileSync(path.join(lesson,'index.html'),'utf8');
  assert.ok(page.includes(a),'Original link preserved');
  assert.equal((page.match(/Deschide local/g)||[]).length,2);
  assert.match(page,/resources\/Model_Evidenta-[a-f0-9]{12}\.xlsx/);
  assert.equal(audit(root).complete,1,'Local resource audit');
  const again=await docs.archiveCourseDocuments(root,()=>{},downloader);
  assert.deepEqual(again,{saved:0,failed:0});
  assert.equal(count,2,'No repeated downloads');
  assert.equal((fs.readFileSync(path.join(lesson,'index.html'),'utf8').match(/Deschide local/g)||[]).length,2);
  assert.equal(docs.classify('http://example.org/file.pdf','File'),null);
  assert.equal(docs.classify('https://example.org/setup.exe','File'),null);
  assert.equal(docs.classify('https://example.org/page','Page'),null);
  assert.ok(docs.classify('https://drive.google.com/file/d/AbCdEfGhIjKlMnOpQrStUv/view','File'));
  assert.throws(()=>docs.safeUrl('https://127.0.0.1/file.pdf'));
  assert.throws(()=>docs.safeUrl('https://example.org:8443/file.pdf'));
  for(const ip of ['10.0.0.1','192.168.1.2','127.0.0.1','169.254.1.1'])assert.equal(docs.publicIp(ip),false);
  const bad=path.join(root,'Community','Course','Module','Bad');fs.mkdirSync(bad);
  fs.writeFileSync(path.join(bad,'lesson.json'),JSON.stringify({title:'Private'}));
  fs.writeFileSync(path.join(bad,'index.html'),'<a href="https://docs.google.com/document/d/AbCdEfGhIjKlMnOpQrStUv/edit">Online link</a>');
  const fail=await docs.archiveCourseDocuments(bad,()=>{},async()=>{throw Error('HTTP 403')});
  assert.equal(fail.failed,1);
  assert.ok(!fs.readFileSync(path.join(bad,'index.html'),'utf8').includes('Deschide local'));
  console.log('PASS: preserved original + offline links; Google Docs; idempotency; forbidden links; audit; failure handling');
 }finally{fs.rmSync(root,{recursive:true,force:true})}
})().catch(e=>{console.error(e);process.exitCode=1});

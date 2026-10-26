/* Local static checks; not a Windows / Skool end-to-end test. */
'use strict';
const fs=require('fs'), os=require('os'), path=require('path'), vm=require('vm'), cp=require('child_process');
const assert=require('node:assert/strict');
const main=__dirname;
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'skool-v14-test-'));
try{
  const src=path.join(tmp,'node_modules','skool-downloader','src');fs.mkdirSync(src,{recursive:true});
  fs.writeFileSync(path.join(src,'downloader.ts'),`export class Downloader {\n async downloadVideo(url: string, outputDir: string, filename: string) {\n await this.ytDlp!.execPromise(args);\n }\n}`);
  fs.writeFileSync(path.join(src,'index.ts'),`export async function demo(){\n await downloader.downloadVideo(lessonData.videoLink, lessonDir, 'video');\n logger.warn(\`    ⚠️ Failed to download video for \${lesson.title}\`);\n}`);
  fs.copyFileSync(path.join(main,'patch_progress.cjs'),path.join(tmp,'patch_progress.cjs'));
  for (let i=0;i<2;i++) {
    const r=cp.spawnSync(process.execPath,[path.join(tmp,'patch_progress.cjs')],{encoding:'utf8'});
    assert.equal(r.status,0,r.stderr+r.stdout);
  }
  const typescript=require('typescript');
  for(const f of ['downloader.ts','index.ts']){
    const patched=fs.readFileSync(path.join(src,f),'utf8');
    assert.ok(patched.includes('SKOOL_MANAGER_1_3'));
    if(f==='index.ts')assert.ok(patched.includes('failed-video'));
    if(f==='index.ts')assert.ok(patched.includes("JSON.stringify({type:'failed-video'"));
    const parsed=typescript.transpileModule(patched,{reportDiagnostics:true,compilerOptions:{target:typescript.ScriptTarget.ES2022,module:typescript.ModuleKind.ESNext}});
    const failures=(parsed.diagnostics||[]).filter(d=>d.category===typescript.DiagnosticCategory.Error);
    assert.equal(failures.length,0,failures.map(d=>typescript.flattenDiagnosticMessageText(d.messageText,'\n')).join('\n'));
  }
  console.log('PASS: progress patch is idempotent; TypeScript parses');
  const root=path.join(tmp,'Archive');
  for(const p of ['_cache','_temp','My Community','My Community/My Course','My Community/EmptyFolder']){fs.mkdirSync(path.join(root,p),{recursive:true});}
  fs.writeFileSync(path.join(root,'My Community/My Course/.course.json'),'{}');
  fs.writeFileSync(path.join(root,'_cache/.course.json'),'{}');
  const content=fs.readFileSync(path.join(main,'bridge.mjs'),'utf8');
  const source=content.slice(content.indexOf('async function makeRootIndex('),content.indexOf('async function startDownload('));
  const ctx={fs,path,evt:()=>{},console,uiApi:require('./selection.cjs').uiApi};
  vm.createContext(ctx);vm.runInContext(source+'\nglobalThis.runIndex=makeRootIndex',ctx);
  ctx.runIndex(root).then(()=>{
    const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
    assert.ok(html.includes('My Course'));
    assert.ok(!html.includes('_cache'));
    assert.ok(!html.includes('_temp'));
    assert.ok(!html.includes('EmptyFolder'));
    console.log('PASS: root index includes courses, excludes technical folders');
    console.log('PASS: local application source files generated');
  }).catch(e=>{console.error(e);process.exitCode=1;});
}catch(e){console.error(e);process.exitCode=1;}finally{process.on('exit',()=>fs.rmSync(tmp,{force:true,recursive:true}));}

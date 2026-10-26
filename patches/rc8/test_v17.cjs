'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const {spawnSync}=require('node:child_process');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'skool-v17-'));
const src=__dirname;
try {
  // Windows UI should classify a text-only lesson as successful archival.
  const gui=fs.readFileSync(path.join(src,'Instant_Downloader.ps1'),'utf8');
  assert.match(gui,/'ARHIVAT'\s*\{Color '#147d43'\}/);
  assert.match(gui,/else\{SetSlot[\s\S]*?'ARHIVAT' 100/);
  assert.doesNotMatch(gui,/RecordStatus[^\n]*'FARA VIDEO'/);
  // Real-world regression: 13 visible Classroom cards, including private
  // courses, must not collapse to 10 simply because privacy > 0.
  const {catalogCourses}=require('./selection.cjs');
  const sample=Array.from({length:13},(_,i)=>({
    key:'course_'+String(i+1),
    title:['INTRODUCERE','ALEGEREA NISEI SI INTELEGEREA CLIENTULUI','CONFIGURAREA SI LANSAREA MAGAZINULUI SHOPIFY','FACEBOOK ADS'][i]||'Module '+String(i+1),
    url:'https://www.skool.com/expert-dropshipping/classroom/course_'+String(i+1),
    numModules:i+1,privacy:[1,2,3].includes(i)?1:0,
    hasAccess:i===2?false:true
  }));
  const catalog=catalogCourses([...sample,sample[0],{key:'hack',url:'https://outside.example/classroom/hack',title:'Invalid'}]);
  assert.equal(catalog.length,13,'All 13 visible course cards should remain');
  assert.equal(catalog[1].title,'ALEGEREA NISEI SI INTELEGEREA CLIENTULUI');
  assert.equal(catalog[2].title,'CONFIGURAREA SI LANSAREA MAGAZINULUI SHOPIFY');
  assert.equal(catalog[3].title,'FACEBOOK ADS');
  assert.equal(catalog[2].accessStatus,'unconfirmed');
  assert.deepEqual(catalog.map(c=>c.key),sample.map(c=>c.key));
  assert.deepEqual(catalog.map(c=>c.numModules),sample.map(c=>c.numModules));
  const scanBridge=fs.readFileSync(path.join(src,'bridge.mjs'),'utf8');
  assert.ok(scanBridge.includes('selectionApi.catalogCourses(lib.courses)'));
  assert.ok(scanBridge.includes('selectionApi.catalogCourses(lib.courses)'));
  assert.ok(!scanBridge.includes('lib.courses.filter(') && !scanBridge.includes('library.courses.filter('));
  const bridge=fs.readFileSync(path.join(src,'bridge.mjs'),'utf8');
  assert.match(bridge,/resourcesCount:v.resourcesCount\|\|0/);
  // Mock GitHub manifest is inaccessible. A synced Dropbox local file is a working fallback.
  const manifestPath=path.join(temp,'dropbox-latest.json');
  const configPath=path.join(temp,'config.json');
  const noticePath=path.join(temp,'notice.json');
  const makeManifest=(version,channel='rc')=>fs.writeFileSync(manifestPath,JSON.stringify({version,channel,sha256:'a'.repeat(64),package_path:'release.zip'}));
  const check=(config)=>{
    fs.writeFileSync(configPath,JSON.stringify(config));
    const r=spawnSync(process.execPath,[path.join(src,'check_update_notice.cjs'),configPath,noticePath],{encoding:'utf8'});
    assert.equal(r.status,0,r.stderr+r.stdout);
    return JSON.parse(fs.readFileSync(noticePath,'utf8'));
  };
  makeManifest('1.8.0-rc.2');
  let n=check({version:'1.8.0-rc.1',updateChannel:'rc',updateManifestSource:path.join(temp,'missing.json'),updateManifestFallback:manifestPath});
  assert.equal(n.status,'available');assert.equal(n.version,'1.8.0-rc.2');assert.equal(n.source,manifestPath);
  n=check({version:'1.8.0-rc.1',updateChannel:'stable',updateManifestSource:path.join(temp,'missing.json'),updateManifestFallback:manifestPath});
  assert.equal(n.status,'up-to-date');
  makeManifest('1.8.0','stable');
  n=check({version:'1.8.0-rc.1',updateChannel:'stable',updateManifestSource:path.join(temp,'missing.json'),updateManifestFallback:manifestPath});
  assert.equal(n.status,'available');assert.equal(n.version,'1.8.0');
  n=check({version:'1.8.0',updateChannel:'stable',updateManifestSource:path.join(temp,'missing.json'),updateManifestFallback:manifestPath});
  assert.equal(n.status,'up-to-date');
  // When both manifests unavailable show a controlled error, not false success.
  n=check({version:'1.8.0-rc.1',updateChannel:'rc',updateManifestSource:path.join(temp,'missing-a.json'),updateManifestFallback:path.join(temp,'missing-b.json')});
  assert.equal(n.status,'error');
  const install=fs.readFileSync(path.join(src,'Install_Instant_Downloader.ps1'),'utf8');
  for(let i=0;i<=8;i++)assert.ok(install.includes('Step '+i+' '),`step ${i}`);
  assert.match(install,/updateManifestFallback/);
  const updater=fs.readFileSync(path.join(src,'Update_Instant_Downloader.ps1'),'utf8');
  assert.match(updater,/foreach\(\$candidate in \$sources\)/);
  assert.match(updater,/\$script:cfg.updateManifestFallback/);
  assert.match(updater,/\[switch\]\$Headless/);
  assert.match(gui,/\$script:updatePanel\.BringToFront\(\)/);
  assert.match(gui,/\$script:backBtn\.Add_Click/);
  // Never include a user's local account secrets in distributed packages.
  const files=fs.readdirSync(src);
  for (const name of files)assert.ok(!['.auth','cookies.txt','config.json','storage_state.json','node_modules'].includes(name));
  console.log('PASS: text-only lessons green; fallback update source; channels stable/RC; unavailable manifests; installer progress; no secrets');
} finally {fs.rmSync(temp,{recursive:true,force:true});}

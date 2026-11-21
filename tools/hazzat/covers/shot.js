const { chromium } = require('playwright'); const fs = require('fs');
(async () => { const b = await chromium.launch(); const p = await b.newPage({viewport:{width:600,height:600}});
await p.goto('file://' + process.cwd() + '/covers.html');
fs.mkdirSync('png', {recursive: true});
for (const k of fs.readFileSync('keys.txt','utf8').split('\n')) { await (await p.$('#' + k)).screenshot({path: `png/${k}.png`}); }
await b.close(); })();

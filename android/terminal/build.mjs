import {readFile,writeFile,copyFile} from 'node:fs/promises';
import {transform} from 'esbuild';
const output=new URL('../app/src/main/assets/terminal/',import.meta.url);
for(const [input,name] of [['@xterm/xterm/lib/xterm.js','xterm.js'],['@xterm/addon-fit/lib/addon-fit.js','fit.js']]) {
 const source=await readFile(new URL(`node_modules/${input}`,import.meta.url),'utf8');
 const result=await transform(source,{target:'chrome70',minify:true,legalComments:'inline'});
 await writeFile(new URL(name,output),result.code);
}
for(const [input,name] of [['@xterm/xterm/css/xterm.css','xterm.css'],['@xterm/xterm/LICENSE','XTERM-LICENSE'],['@xterm/addon-fit/LICENSE','FIT-LICENSE']])await copyFile(new URL(`node_modules/${input}`,import.meta.url),new URL(name,output));

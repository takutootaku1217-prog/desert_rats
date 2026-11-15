// Offline, deterministic code-generated animation. npm install @napi-rs/canvas
const fs=require('fs'),vm=require('vm'),path=require('path');
const {createCanvas,ImageData}=require('@napi-rs/canvas');
const canvas=createCanvas(1280,720), el={addEventListener(){},classList:{toggle(){}},value:7};
canvas.addEventListener=()=>{};
const document={createElement(){return createCanvas(1,1)},getElementById(id){return id==='view'?canvas:{...el}},addEventListener(){}};
const ctx=vm.createContext({document,window:{},ImageData,requestAnimationFrame(){},performance});
const html=fs.readFileSync(path.join(__dirname,'mechanical-explosion.html'),'utf8');
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1],ctx);
const out=process.argv[2]||path.join(__dirname,'../../assets/effects/mechanical');fs.mkdirSync(out,{recursive:true});
for(let i=0;i<54;i++)fs.writeFileSync(path.join(out,`${String(i).padStart(2,'0')}.png`),Buffer.from(ctx.window.__vfx.exportFrame(i*2).split(',')[1],'base64'));
ctx.window.__vfx.setTime(83);fs.writeFileSync(path.join(out,'preview.png'),canvas.toBuffer('image/png'));

(async()=>{const {loadImage}=require('@napi-rs/canvas');const sheet=createCanvas(2880,1080),g=sheet.getContext('2d');for(let i=0;i<54;i++){const im=await loadImage(path.join(out,`${String(i).padStart(2,'0')}.png`));g.drawImage(im,(i%9)*320,Math.floor(i/9)*180);}fs.writeFileSync((process.argv[2]?path.join(out,'mechanical_explosion.png'):path.join(__dirname,'../../assets/effects/mechanical_explosion.png')),sheet.toBuffer('image/png'));})();

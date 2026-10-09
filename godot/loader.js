'use strict';
// Godot 4.7.2 mesh_surface_update_index_region uploads index data through
// ARRAY_BUFFER (drivers/gles3/storage/mesh_storage.cpp). Native GL allows this,
// WebGL does not. Use WebGL2's copy target for that upload, preserving the VAO
// element binding, original array binding, and previous copy target binding.
function installIndexUploadCompatibility() {
  const proto = window.WebGL2RenderingContext?.prototype;
  if (!proto) return;
  const contexts = new WeakMap();
  const bind = proto.bindBuffer;
  const state = gl => {
    if (!contexts.has(gl)) contexts.set(gl, {indices:new WeakSet(), redirect:false, previous:null});
    return contexts.get(gl);
  };
  proto.bindBuffer = function(target, buffer) {
    const s = state(this);
    if (target === this.ARRAY_BUFFER) {
      if (s.redirect) bind.call(this, this.COPY_WRITE_BUFFER, s.previous);
      s.redirect = Boolean(buffer && s.indices.has(buffer));
      if (s.redirect) {
        s.previous = this.getParameter(this.COPY_WRITE_BUFFER_BINDING);
        return bind.call(this, this.COPY_WRITE_BUFFER, buffer);
      }
    }
    if (target === this.ELEMENT_ARRAY_BUFFER && buffer) s.indices.add(buffer);
    return bind.call(this, target, buffer);
  };
  for (const method of ['bufferData', 'bufferSubData', 'getBufferSubData', 'getBufferParameter']) {
    const original = proto[method];
    proto[method] = function(target, ...args) {
      if (target === this.ARRAY_BUFFER && state(this).redirect) target = this.COPY_WRITE_BUFFER;
      return original.call(this, target, ...args);
    };
  }
}
installIndexUploadCompatibility();
const statusText = document.querySelector('#status');
const startButton = document.querySelector('#start');
const progress = document.querySelector('#progress');
let manifest, engine, loadedBytes = 0, ready = false, running = false, busy = false;
const download = window.fetch.bind(window);
function showProgress() {
  const total = manifest.wasm.downloadBytes + manifest.pack.downloadBytes;
  progress.value = loadedBytes / total;
  statusText.textContent = `正在加载 ${(loadedBytes/1048576).toFixed(1)} / ${(total/1048576).toFixed(1)} MB`;
}
// Decode one compressed stream from bounded static chunks. The original PCK bytes are preserved.
window.dearthAssetResponse = async function(key) {
  const asset = manifest[key]; let index = 0;
  const stream = new ReadableStream({
    async pull(controller) {
      if (index >= asset.parts.length) { controller.close(); return; }
      const part = asset.parts[index++];
      try {
        const response = await download(part.file);
        if (!response.ok) throw new Error(`资源下载失败 (${response.status})`);
        const buffer = await response.arrayBuffer();
        const digest = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',buffer)), n=>n.toString(16).padStart(2,'0')).join('');
        if (digest !== part.sha256) throw new Error('资源校验失败，请重新加载');
        loadedBytes += buffer.byteLength; showProgress();
        controller.enqueue(new Uint8Array(buffer));
      } catch(error) { controller.error(error); }
    }
  }).pipeThrough(new DecompressionStream('gzip'));
  return new Response(stream, {headers:{'Content-Type':key==='wasm'?'application/wasm':'application/octet-stream'}});
};
function fail(error) {
  console.error(error); busy=false;startButton.disabled=false;startButton.textContent='重新加载';
  startButton.onclick=()=>location.reload();
  statusText.textContent = '加载未完成：'+(error.message||error)+'。请用较新的 Safari，并保持网络连接。';
}
async function prepare() {
  if(busy)return;busy=true;startButton.disabled=true;progress.hidden=false;
  try {
    if(typeof DecompressionStream==='undefined')throw new Error('浏览器版本较旧，缺少解压支持');
    const missing=Engine.getMissingFeatures({threads:false});
    if(missing.length)throw new Error('浏览器缺少 '+missing.join('、'));
    const response=await download('assets.json');if(!response.ok)throw new Error('资源清单无法下载');
    manifest=await response.json();
    engine=new Engine({executable:'godot',canvas:document.querySelector('#canvas'),canvasResizePolicy:2,focusCanvas:true,persistentPaths:['/userfs'],onPrint:console.log,onPrintError:console.error,onExit:code=>{if(code!==0)fail(new Error('游戏退出：'+code));}});
    await engine.init('godot');
    const pack=await (await window.dearthAssetResponse('pack')).arrayBuffer();
    if(pack.byteLength!==manifest.pack.bytes)throw new Error('游戏内容不完整');
    await engine.preloadFile(pack,'dearth.pck');
    await engine.preloadFile(new TextEncoder().encode('[display]\nwindow/size/mode=0\n[input_devices]\npointing/emulate_mouse_from_touch=true\n'), 'override.cfg');
    ready=true;busy=false;startButton.disabled=false;startButton.textContent='进入荒年';progress.value=1;
    statusText.textContent='准备好了。点击进入，启用游戏与声音。';
  } catch(error){fail(error);}
}
function fullscreen(){const target=document.documentElement;if(target.requestFullscreen)target.requestFullscreen().catch(()=>{});else{document.querySelector('#help').hidden=false;document.querySelector('#help').firstChild.textContent='iPhone 上可使用 Safari 分享菜单的「添加到主屏幕」，再从图标打开，减少浏览器栏遮挡。';}}
async function launch(){
  if(running)return;running=true;startButton.disabled=true;
  try{
    await engine.start({args:['--main-pack','dearth.pck']});
    document.querySelector('#cover').hidden=true;document.querySelector('#cover').style.display='none';
    document.querySelector('#canvas').focus();
    if(matchMedia('(pointer:coarse)').matches)document.querySelector('#mobile-tools').style.display='flex';
    window.dearthRunning=true;
  }catch(error){running=false;fail(error);}
}
startButton.onclick=()=>ready?launch():prepare();
document.querySelector('#fullscreen').onclick=fullscreen;
document.querySelector('#help-button').onclick=()=>document.querySelector('#help').hidden=false;
document.querySelector('#close-help').onclick=()=>{document.querySelector('#help').hidden=true;document.querySelector('#canvas').focus();};
document.querySelector('#canvas').addEventListener('contextmenu',e=>e.preventDefault());

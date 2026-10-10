'use strict';
if (typeof Engine !== 'function') throw new Error('引擎脚本没有下载完成，请重试启动');
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
const mobileLayout = matchMedia('(pointer:coarse)').matches || location.search.includes('phone=1');
// CSS safe-area bounds can change independently of window.resize on Safari.
// Keep the backing buffer and the Godot logical size derived from the same box.
const gameFrame = document.querySelector('#game-frame');
const gameCanvas = document.querySelector('#canvas');
function resizeGameCanvas() {
  const rect = gameFrame.getBoundingClientRect();
  const logicalWidth = Math.max(1, Math.round(rect.width));
  const logicalHeight = Math.max(1, Math.round(rect.height));
  // Reduce render-target memory on phones without changing logical layout/aspect.
  const ratio = Math.min(window.devicePixelRatio || 1, mobileLayout ? 1.5 : 2);
  const width = Math.max(1, Math.round(rect.width * ratio));
  const height = Math.max(1, Math.round(rect.height * ratio));
  if (gameCanvas.width !== width) gameCanvas.width = width;
  if (gameCanvas.height !== height) gameCanvas.height = height;
  return [logicalWidth, logicalHeight];
}
// Also called by the game before applying its logical viewport size: a missed
// browser event must never update the UI size while leaving stale canvas pixels.
window.dearthViewportSize = () => JSON.stringify(resizeGameCanvas());
const canvasSizeObserver = new ResizeObserver(resizeGameCanvas);
canvasSizeObserver.observe(gameFrame);
window.addEventListener('resize', resizeGameCanvas);
window.addEventListener('orientationchange', resizeGameCanvas);
window.addEventListener('pageshow', resizeGameCanvas);
window.visualViewport?.addEventListener('resize', resizeGameCanvas);
document.addEventListener('visibilitychange', () => {
  if (!document.hidden) resizeGameCanvas();
});
resizeGameCanvas();
const statusText = document.querySelector('#status');
const startButton = document.querySelector('#start');
const progress = document.querySelector('#progress');
const BUILD = 'startup-v6';
const compatibilityMode = new URLSearchParams(location.search).has('safe');
const RESOURCE_CACHE = 'dearth-verified-assets-v1';
const SESSION_KEY = 'dearth-web-session-v1';
let manifest, engine, loadedBytes = 0, ready = false, running = false, busy = false, interrupted = false;
let cachedBytes = 0, networkBytes = 0, cacheWritable = true;
const download = window.fetch.bind(window);
// Cache is an optimization: Safari storage operations must never gate startup.
function bounded(task, ms, label) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(label + '超时')), ms);
    Promise.resolve().then(task).then(value => { clearTimeout(timer); resolve(value); }, error => { clearTimeout(timer); reject(error); });
  });
}
const resourceCache = compatibilityMode ? Promise.resolve(null) : bounded(() => caches.open(RESOURCE_CACHE), 1800, '缓存打开').catch(() => null);
const diagnostics = window.dearthRecovery = {build:BUILD, cachedBytes:0, networkBytes:0, cacheAvailable:false, stage:'idle', compatibilityMode};
function stage(name, message) { diagnostics.stage = name; statusText.textContent = message; }
async function fetchAsset(url) {
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), 90000);
  try {
    const response = await download(url, {signal:abort.signal});
    if (!response.ok) throw new Error(`资源下载失败 (${response.status})`);
    return await response.arrayBuffer();
  } finally { clearTimeout(timer); }
}
function recordSession(state, detail = '') {
  try { localStorage.setItem(SESSION_KEY, JSON.stringify({state, detail:String(detail).slice(0,180), at:Date.now()})); } catch (_) {}
}
try {
  const prior = JSON.parse(localStorage.getItem(SESSION_KEY) || 'null');
  if (prior && ['running','background','interrupted'].includes(prior.state)) {
    statusText.textContent = '上次游玩中断了。点击恢复加载；已缓存资源会复用，进入后可选择「继续旅程」。';
    startButton.textContent = '恢复加载';
  }
} catch (_) {}
function showProgress() {
  const total = manifest.wasm.downloadBytes + manifest.pack.downloadBytes;
  progress.value = loadedBytes / total;
  diagnostics.cachedBytes = cachedBytes; diagnostics.networkBytes = networkBytes;
  statusText.textContent = `准备资源 ${(loadedBytes/1048576).toFixed(1)} / ${(total/1048576).toFixed(1)} MB · 本地 ${(cachedBytes/1048576).toFixed(1)} MB`;
}
async function digest(buffer) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', buffer)), n => n.toString(16).padStart(2,'0')).join('');
}
// Hash-addressed entries survive loader updates. A corrupt/interrupted part alone
// is retried; no clearing of IndexedDB, game saves, or unrelated site caches.
async function readPart(part) {
  const cache = cacheWritable ? await resourceCache : null;
  diagnostics.cacheAvailable = Boolean(cache && cacheWritable);
  const key = new URL(`__assets/${part.sha256}`, location.href).href;
  let cached;
  try { if (cache) cached = await bounded(() => cache.match(key), 1800, '缓存读取'); } catch (_) { cacheWritable = false; }
  if (cached) {
    try {
      const buffer = await bounded(() => cached.arrayBuffer(), 1800, '缓存内容读取');
      if (buffer.byteLength === part.bytes && await digest(buffer) === part.sha256) {
        cachedBytes += buffer.byteLength;
        return buffer;
      }
      // A bad entry is replaced only after a verified network download.
    } catch (_) { cacheWritable = false; }
  }
  let lastError;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const buffer = await fetchAsset(part.file + (attempt ? '?retry=1' : ''));
      if (buffer.byteLength !== part.bytes || await digest(buffer) !== part.sha256) throw new Error('资源校验失败');
      networkBytes += buffer.byteLength;
      if (cache && cacheWritable) {
        try { await bounded(() => cache.put(key, new Response(buffer)), 1800, '缓存写入'); }
        catch (_) { cacheWritable = false; diagnostics.cacheAvailable = false; }
      }
      return buffer;
    } catch (error) { lastError = error; }
  }
  throw lastError;
}
window.dearthAssetResponse = async function(key) {
  const asset = manifest[key]; let index = 0;
  const stream = new ReadableStream({
    async pull(controller) {
      if (index >= asset.parts.length) { controller.close(); return; }
      try {
        const buffer = await readPart(asset.parts[index++]);
        loadedBytes += buffer.byteLength; showProgress();
        controller.enqueue(new Uint8Array(buffer));
      } catch (error) { controller.error(error); }
    }
  }).pipeThrough(new DecompressionStream('gzip'));
  return new Response(stream, {headers:{'Content-Type':key==='wasm'?'application/wasm':'application/octet-stream'}});
};
function fail(error) {
  console.error(error);
  const wasRunning = running;
  interrupted = true;
  diagnostics.stage = 'error';
  busy = false; ready = false; running = false; window.dearthRunning = false;
  recordSession('interrupted', error.message || error);
  document.querySelector('#cover').hidden = false;
  document.querySelector('#cover').style.display = 'flex';
  startButton.disabled = false; startButton.textContent = '重试加载';
  startButton.onclick = () => location.reload();
  document.querySelector('#safe-start').hidden = compatibilityMode;
  statusText.textContent = (wasRunning ? '游戏运行中断：' : '加载未完成：') + (error.message || error) + '。重新进入会复用已缓存资源，并保留已有存档。';
}
gameCanvas.addEventListener('webglcontextlost', event => {
  event.preventDefault();
  fail(new Error('浏览器中断了图形画面'));
});
window.addEventListener('error', event => {
  if (running && /memory|out of bounds|unreachable|abort/i.test(event.message || '')) fail(new Error(event.message));
});
document.addEventListener('visibilitychange', () => {
  if (running) recordSession(document.hidden ? 'background' : 'running');
});
window.addEventListener('pagehide', () => { if (running) recordSession('background'); });
// Replace the v5 offline interceptor with network-only requests.
// Keep verified asset caches and all saves.
// Registering the retirement worker also updates an already controlling v5 worker.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js', {updateViaCache:'none'}).then(reg => reg.update()).catch(() => {});
}
document.querySelector('#safe-start').onclick = () => {
  const url = new URL(location.href); url.searchParams.set('safe', '1'); url.searchParams.set('v', 'startup6');
  location.assign(url.href);
};
async function prepare() {
  if(busy)return;busy=true;startButton.disabled=true;progress.hidden=false;
  stage('manifest', '正在读取资源清单…');
  try {
    if(typeof DecompressionStream==='undefined')throw new Error('浏览器版本较旧，缺少解压支持');
    const missing=Engine.getMissingFeatures({threads:false});
    if(missing.length)throw new Error('浏览器缺少 '+missing.join('、'));
    manifest = JSON.parse(new TextDecoder().decode(await fetchAsset('assets.json')));
    stage('engine', '正在加载引擎…');
    engine=new Engine({executable:'godot',canvas:document.querySelector('#canvas'),canvasResizePolicy:0,focusCanvas:true,persistentPaths:['/userfs'],onPrint:console.log,onPrintError:console.error,onExit:code=>fail(new Error('游戏已退出（'+code+'）'))});
    await engine.init('godot');
    stage('pack', '正在加载游戏内容…');
    let pack=await (await window.dearthAssetResponse('pack')).arrayBuffer();
    if(pack.byteLength!==manifest.pack.bytes)throw new Error('游戏内容不完整');
    // Copy before scene startup; release the download buffer before loading textures.
    engine.copyToFS('dearth.pck', pack);
    pack = null;
    stage('interface', '正在准备手机界面…');
    const config = '[application]\nrun/main_scene="res://mobile_boot.tscn"\n[display]\nwindow/size/mode=0\n' + (mobileLayout ? `window/size/viewport_width=${JSON.parse(window.dearthViewportSize())[0]}\nwindow/size/viewport_height=${JSON.parse(window.dearthViewportSize())[1]}\n` : '') + '[input_devices]\npointing/emulate_mouse_from_touch=true\n';
    await engine.preloadFile(new TextEncoder().encode(config), 'override.cfg');
    for (const [url, path] of [['mobile.pck?v=4','mobile.pck'], ['mobile-src/boot.gd?v=4','mobile_boot.gd'], ['mobile-src/boot.tscn?v=4','mobile_boot.tscn']]) {
      await engine.preloadFile(await fetchAsset(url), path);
    }
    diagnostics.stage = 'ready';
    ready=true;busy=false;startButton.disabled=false;startButton.textContent='进入荒年';progress.value=1;
    statusText.textContent = cachedBytes > 0 ? '本地资源已就绪。点击进入，启用游戏与声音。' : '准备好了。点击进入，启用游戏与声音。';
    if (!diagnostics.cacheAvailable) statusText.textContent += ' 浏览器未允许持久缓存，下次可能需重新下载。';
  } catch(error){fail(error);}
}
function fullscreen(){const target=document.documentElement;if(target.requestFullscreen)target.requestFullscreen().catch(()=>{});else{document.querySelector('#help').hidden=false;document.querySelector('#help').firstChild.textContent='iPhone 上可使用 Safari 分享菜单的「添加到主屏幕」，再从图标打开，减少浏览器栏遮挡。';}}
async function launch(){
  if(running)return;running=true;startButton.disabled=true;
  stage('starting', '正在启动场景，首次进入可能稍慢…');
  try{
    resizeGameCanvas();
    await engine.start({args:['--main-pack','dearth.pck']});
    if (interrupted) return;
    resizeGameCanvas();
    document.querySelector('#cover').hidden=true;document.querySelector('#cover').style.display='none';
    document.querySelector('#canvas').focus();
    document.querySelector('#mobile-tools').style.display='none';
    window.dearthRunning=true;
    diagnostics.stage = 'running';
    recordSession('running');
  }catch(error){running=false;fail(error);}
}
startButton.onclick=()=>ready?launch():prepare();
document.querySelector('#fullscreen').onclick=fullscreen;
document.querySelector('#help-button').onclick=()=>document.querySelector('#help').hidden=false;
document.querySelector('#close-help').onclick=()=>{document.querySelector('#help').hidden=true;document.querySelector('#canvas').focus();};
document.querySelector('#canvas').addEventListener('contextmenu',e=>e.preventDefault());

window.dearthBootReady = true;
startButton.disabled = false;
if (startButton.textContent === '重试启动') startButton.textContent = '加载游戏';
if (statusText.textContent === '正在准备加载器…' || statusText.textContent.includes('启动脚本未就绪') || statusText.textContent.includes('加载器等待超过')) {
  statusText.textContent = compatibilityMode ? '兼容模式：跳过资源缓存，保留已有存档。点击加载游戏。' : '首次加载建议使用 Wi-Fi。iPhone 请横屏，在 Safari 中打开。';
}

(function(root) {
  'use strict';
  function angleTenths(text) {
    const value = String(text).trim();
    if (!/^[+-]?\d+(?:\.\d)?$/.test(value)) throw new Error('请填写角度数字，最多一位小数，例如 +60、-40、12.5');
    const n = Number(value);
    if (!Number.isFinite(n) || Math.abs(n) > 3600) throw new Error('转动角度须在 −3600.0°～+3600.0° 之间');
    return Math.round(n * 10);
  }
  const signed32 = text => parseInt(text, 16) | 0;
  const codes = { 0: '状态已更新', 1: '已接受，正在转动', 2: '已到位，保持目标位置', 3: '移动已取消',
    16: '转臂尚未到位，拒绝新指令', 17: '当前未处于正常直立平衡状态', 18: '目标超出相对平衡原点 ±10 圈行程',
    19: '命令格式错误或接收超时', 20: '重复编号，未再次执行' };
  function create(options) {
    const $ = options.getElement, now = options.now || (() => Date.now());
    let capability = null, state = null, remoteBusy = false, pending = false, uncertain = false;
    let buffer = '', lastAt = 0, lastQuery = 0, sentAt = 0, nextId = 0, expectedId = 0, portSession = 0, queryWriting = false;
    const connected = () => options.isConnected();
    const fresh = () => lastAt !== 0 && now() - lastAt < 1500;
    function show(text, error = false) { $('arm-message').textContent = text; $('arm-message').classList.toggle('error', error); }
    function update() {
      const locked = pending || uncertain || remoteBusy;
      $('arm-angle').disabled = !connected() || locked || !!options.motionLocked();
      $('arm-send').disabled = !connected() || !capability || !fresh() || state !== 4 || locked || !!options.motionLocked();
      $('arm-emergency').disabled = !connected();
      $('arm-query').disabled = !connected() || queryWriting;
      $('arm-capability').textContent = capability ? `ARM1 · ${capability.cpr} counts/圈 · ${capability.speed}°/秒 · 行程 ±${(capability.limit * 360 / capability.cpr).toFixed(0)}°` : '等待支持角度转动的 ARM1 固件';
      $('arm-state').textContent = !connected() ? '未连接' : !fresh() ? '等待板端状态' :
        `${state === 4 ? '直立平衡' : `控制状态 ${state}`} · ${locked ? '执行中 / 等待确认' : '空闲'}`;
      options.onStateChange?.();
    }
    async function query() {
      if (!connected() || queryWriting) return;
      const session = portSession;
      queryWriting = true; update();
      try { await options.send(capability ? '@Q\n' : '@I\n'); }
      catch (error) { if (session === portSession) show(`状态查询失败：${error.message}`, true); }
      finally { if (session === portSession) { queryWriting = false; update(); } }
    }
    function onLine(line) {
      let match = /^@I,ARM1,([0-9A-F]{4}),([0-9A-F]{4}),([0-9A-F]{4})$/.exec(line);
      if (match) {
        const [cpr, speed, limit] = match.slice(1).map(s => parseInt(s, 16));
        if (!cpr || !speed || !limit) return;
        capability = { cpr, speed, limit };
        show('已识别 ARM1；使用实体 K3 进入直立平衡后可执行转动。');
        void query(); update(); return;
      }
      match = /^@R,([0-9A-F]{4}),([0-9A-F]{2}),([0-6]),([01]),([0-9A-F]{8}),([0-9A-F]{8})$/.exec(line);
      if (!match || !capability) return;
      const id = parseInt(match[1], 16), code = parseInt(match[2], 16);
      state = Number(match[3]); remoteBusy = match[4] === '1'; lastAt = now();
      // Continue IDs across a webpage reload; never reuse the board's last ID.
      if (!expectedId) nextId = id;
      const actual = signed32(match[5]), goal = signed32(match[6]) / 65536;
      $('arm-actual').textContent = `${(actual * 360 / capability.cpr).toFixed(2)}° (${actual} counts)`;
      $('arm-goal').textContent = `${(goal * 360 / capability.cpr).toFixed(2)}°`;
      if (id === expectedId) {
        pending = false; uncertain = false;
        show(codes[code] || `板端结果 ${code}`, code >= 16);
      } else if (uncertain && !remoteBusy) {
        pending = false; uncertain = false;
        show('已查询板端：当前没有移动在执行。请核对位置后重新填写角度。', true);
      } else if (!pending) show(codes[code] || '状态已更新', code >= 16);
      update();
    }
    function feed(text) {
      buffer += text;
      let index;
      while ((index = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, index).replace(/\r$/, ''); buffer = buffer.slice(index + 1); onLine(line);
      }
      if (buffer.length > 512) buffer = '';
    }
    async function move() {
      if (!connected() || !capability || !fresh() || state !== 4 || pending || uncertain || remoteBusy || options.motionLocked()) return;
      let angle;
      try { angle = angleTenths($('arm-angle').value); } catch (error) { show(error.message, true); return; }
      if (angle === 0) { show('0° 不产生移动。'); return; }
      nextId = nextId % 65535 + 1; expectedId = nextId;
      const session = portSession;
      pending = true; sentAt = now(); show('正在发送，等待板端确认。'); update();
      try { await options.send(`@M,${expectedId},${angle < 0 ? '-' : '+'}${Math.abs(angle)}\n`); }
      catch (error) { if (session === portSession) { uncertain = true; show(`发送未确认：${error.message}。将查询板端状态，不自动重发。`, true); } }
      finally { if (session === portSession) update(); }
    }
    async function emergency() {
      if (!connected()) return;
      // Keep the UI locked until the board confirms stop/cancellation.
      uncertain = true; update();
      try { await options.send('X'); show('已发送立即停机 X，等待板端确认。'); }
      catch (error) { show(`停机指令发送失败：${error.message}，请使用实体 K4。`, true); }
      await query();
    }
    async function poll() {
      if (!connected()) return;
      if (pending && now() - sentAt > 1000 && !uncertain) {
        uncertain = true; show('未收到匹配回复，正在查询板端；不会自动重发移动指令。', true);
      }
      if (capability && now() - lastQuery >= 500 && !queryWriting) { lastQuery = now(); await query(); }
      update();
    }
    $('arm-send').addEventListener('click', move);
    $('arm-emergency').addEventListener('click', emergency);
    $('arm-query').addEventListener('click', query);
    $('arm-form').addEventListener('submit', event => { event.preventDefault(); void move(); });
    update();
    return {
      feed, poll, update, query, move, emergency,
      get locked() { return pending || uncertain || remoteBusy; },
      get requestPending() { return pending || uncertain; },
      async connected() { portSession++;capability=null;state=null;remoteBusy=false;pending=false;uncertain=false;expectedId=0;buffer='';lastAt=0;queryWriting=false;await query(); },
      disconnected() { portSession++;capability=null;state=null;remoteBusy=false;pending=false;uncertain=false;buffer='';lastAt=0;queryWriting=false;show('串口已断开。');update(); },
      async beforeDisconnect() { if (pending || uncertain || remoteBusy) await options.send('X'); }
    };
  }
  const api = { create, angleTenths };
  root.ArmApp = api;
  if (typeof module === 'object') module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);

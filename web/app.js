'use strict';
const $ = id => document.getElementById(id);
const recording = new Telemetry.Recording();
let decoder = new Telemetry.LineDecoder(frame => {
  if (recording.add(frame)) { lastReceived = performance.now(); streaming = true; dirty = true; updateControls(); }
});
let port = null, reader = null, readTask = null, keepReading = false;
let connecting = false, disconnecting = false, sending = false, streaming = false;
let dirty = true, frozen = false, lastReceived = 0, lastPaint = 0, chartView = null;
let writeQueue = Promise.resolve(), calibration = null;
const canvas = $('chart'), ctx = canvas.getContext('2d');

function message(text, error = false) { $('message').textContent = text; $('message').classList.toggle('error', error); }
function updateControls() {
  const connected = !!port;
  $('connect').disabled = connected || connecting || disconnecting || !('serial' in navigator);
  $('disconnect').disabled = !connected || disconnecting || sending;
  $('start').disabled = !connected || disconnecting || sending || !!calibration?.locked;
  $('stop').disabled = !connected || disconnecting || sending || !!calibration?.locked;
  $('baud').disabled = connected || connecting;
  $('import').disabled = connected;
  $('export').disabled = !recording.length;
  $('status').textContent = disconnecting ? '正在断开' : connecting ? '正在连接' :
    connected ? streaming ? '正在接收角度' : '串口已连接' : '串口未连接';
  $('statusDot').className = `dot${connected ? streaming ? ' streaming' : ' connected' : ''}`;
}
function writeCommand(command) {
  const currentPort = port;
  const operation = writeQueue.catch(() => {}).then(async () => {
    if (!currentPort?.writable || currentPort !== port) throw new Error('串口尚未连接');
    const writer = currentPort.writable.getWriter();
    try { await writer.write(new TextEncoder().encode(command)); }
    finally { writer.releaseLock(); }
  });
  writeQueue = operation.catch(() => {});
  return operation;
}
async function command(value) {
  if (sending || disconnecting || calibration?.locked) return;
  sending = true; updateControls();
  try {
    await writeCommand(value);
    if (value === 'P') message('已发送 P，等待角度、PWM、转臂位置和目标偏移。');
    else { streaming = false; message('已发送 Q，板卡完成当前帧后停止回传。电机控制继续保持原状态。'); }
  } catch (error) { message(`指令发送失败：${error.message}`, true); }
  finally { sending = false; updateControls(); }
}
async function readLoop(currentPort) {
  const textDecoder = new TextDecoder();
  try {
    while (keepReading && currentPort.readable) {
      reader = currentPort.readable.getReader();
      try {
        while (keepReading) {
          const { value, done } = await reader.read();
          if (done) break;
          const text = textDecoder.decode(value, { stream: true });
          decoder.feed(text); calibration?.feed(text);
        }
      } finally { reader.releaseLock(); reader = null; }
    }
  } catch (error) {
    if (!disconnecting) message(`串口读取中断：${error.message}。已收集的数据仍可导出。`, true);
  } finally {
    if (!disconnecting && port === currentPort) {
      keepReading = false;
      try { await currentPort.close(); } catch (_) { /* Disconnected devices may already be closed. */ }
      port = null; streaming = false; calibration?.disconnected(); updateControls();
    }
  }
}
$('connect').addEventListener('click', async () => {
  connecting = true; updateControls();
  let selected = null;
  try {
    const baudRate = Number($('baud').value);
    if (!Number.isInteger(baudRate) || baudRate < 1200 || baudRate > 2000000)
      throw new Error('请输入 1200～2000000 的整数波特率');
    selected = await navigator.serial.requestPort();
    await selected.open({ baudRate, dataBits: 8, stopBits: 1, parity: 'none', flowControl: 'none' });
    port = selected; keepReading = true; streaming = false;
    decoder = new Telemetry.LineDecoder(frame => {
      if (recording.add(frame)) { lastReceived = performance.now(); streaming = true; dirty = true; }
    });
    // A new connection is a separate acquisition session, even when firmware was not reset.
    if (recording.length) { recording.session++; recording.lastSequence = null; recording.time += 5; }
    readTask = readLoop(selected);
    await calibration?.connected();
    message('串口已连接。点击「开始回传 P」接收角度、PWM、位置和目标偏移。');
  } catch (error) {
    if (selected && selected !== port) { try { await selected.close(); } catch (_) {} }
    message(error.name === 'NotFoundError' ? '已取消串口选择。' : `连接失败：${error.message}。请关闭占用该串口的串口助手。`, error.name !== 'NotFoundError');
  } finally { connecting = false; updateControls(); }
});
$('start').addEventListener('click', () => command('P'));
$('stop').addEventListener('click', () => command('Q'));
$('disconnect').addEventListener('click', async () => {
  if (!port || disconnecting) return;
  disconnecting = true; updateControls();
  const currentPort = port;
  let stopped = false;
  try {
    try { await calibration?.beforeDisconnect(); } catch (_) { /* The hardware watchdog still expires after heartbeats stop. */ }
    try { await writeCommand('Q'); stopped = true; } catch (_) {}
    keepReading = false;
    if (reader) await reader.cancel();
    if (readTask) await readTask;
    await currentPort.close();
    message(stopped ? '已停止回传并断开串口；数据可继续查看或导出。' : '串口已断开，Q 未成功发送；数据可继续导出。', !stopped);
  } catch (error) { message(`断开串口：${error.message}。数据已保留。`, true); }
  finally { port = null; streaming = false; disconnecting = false; calibration?.disconnected(); updateControls(); }
});
$('clear').addEventListener('click', () => {
  recording.clear(); decoder.pending = ''; decoder.invalid = 0; dirty = true;
  if (frozen) draw();
  $('tooltip').hidden = true; message('已清空本页数据；回传状态保持不变。'); refreshMetrics();
});
$('freeze').addEventListener('click', () => {
  frozen = !frozen; $('freeze').textContent = frozen ? '继续绘图' : '暂停绘图';
  if (!frozen) dirty = true;
  message(frozen ? '绘图已暂停，串口数据仍在收集，可继续导出。' : '绘图已恢复。');
});
$('window').addEventListener('change', () => { dirty = true; if (frozen) draw(); });
$('signal').addEventListener('change', () => { dirty = true; $('tooltip').hidden = true; if (frozen) draw(); });
$('export').addEventListener('click', () => {
  const url = URL.createObjectURL(new Blob([recording.csv()], { type: 'text/csv;charset=utf-8' }));
  const link = document.createElement('a'); link.href = url;
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  link.download = `furuta-angle-${stamp}.csv`; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  message(`已导出 ${recording.length.toLocaleString()} 个保留样本。`);
});
$('import').addEventListener('click', () => $('file').click());
$('file').addEventListener('change', async () => {
  const file = $('file').files[0]; if (!file) return;
  try {
    if (file.size > 30 * 1024 * 1024) throw new Error('请导入 30 MB 以内的文件');
    const points = Telemetry.importText(await file.text());
    recording.clear(); points.forEach(point => recording.push(point));
    const latest = recording.latest();
    recording.time = latest.time; recording.session = latest.session; recording.lastSequence = null;
    recording.missing = points.reduce((sum, point, index) => index && point.session === points[index - 1].session ?
      sum + Math.max(0, Math.round((point.time - points[index - 1].time) / 5) - 1) : sum, 0);
    frozen = false; $('freeze').textContent = '暂停绘图'; dirty = true;
    message(`已导入 ${file.name}，保留 ${recording.length.toLocaleString()} 个样本。`); refreshMetrics();
  } catch (error) { message(`导入失败：${error.message}`, true); }
  finally { $('file').value = ''; }
});

function refreshMetrics() {
  const latest = recording.latest();
  $('current').innerHTML = latest ? `${latest.angle.toFixed(1)}<small>°</small>` : '—<small>°</small>';
  const pwmText = value => value == null ? '—' : `${Telemetry.pwmPercent(value).toFixed(2)}%`;
  $('requestedPwm').textContent = pwmText(latest?.requestedPwm);
  $('actualPwm').textContent = pwmText(latest?.actualPwm);
  const countsText = value => value == null ? '—' : `${value} counts`;
  $('armPosition').textContent = countsText(latest?.armPosition);
  $('positionTarget').textContent = countsText(latest?.positionTarget);
  $('positionError').textContent = countsText(latest?.positionError);
  $('targetAngleOffset').textContent = latest?.targetAngleOffsetAdc == null ? '—' : `${Telemetry.offsetDegrees(latest.targetAngleOffsetAdc).toFixed(3)}°`;
  $('rms').innerHTML = latest ? `${Math.sqrt(Math.max(0, recording.sumSquares / recording.length)).toFixed(2)}<small>°</small>` : '—<small>°</small>';
  $('count').textContent = recording.total.toLocaleString();
  $('duration').textContent = `采集时长 ${latest ? (latest.time / 1000).toFixed(3) : '0.000'} s`;
  $('missing').textContent = recording.missing.toLocaleString();
  $('retention').textContent = recording.total > recording.capacity ?
    `已覆盖 ${recording.total - recording.capacity} 个早期样本；当前保留最近 ${recording.length.toLocaleString()} 个，导出为保留部分。` :
    '保留最近 120,000 个样本，约 10 分钟；可随时导出。';
  if (streaming && !calibration?.locked && performance.now() - lastReceived > 1500) {
    streaming = false;
    message('暂未收到新角度值；请检查回传是否停止，或数码管是否正在显示无效角度。');
  }
  updateControls();
}
function draw() {
  const width = canvas.clientWidth, height = canvas.clientHeight, ratio = window.devicePixelRatio || 1;
  if (canvas.width !== Math.round(width * ratio) || canvas.height !== Math.round(height * ratio)) {
    canvas.width = Math.round(width * ratio); canvas.height = Math.round(height * ratio);
  }
  ctx.setTransform(ratio, 0, 0, ratio, 0, 0); ctx.clearRect(0, 0, width, height);
  const box = { left: 66, right: width - 22, top: 20, bottom: height - 42 };
  const latest = recording.latest();
  const seconds = $('window').value;
  const maxTime = latest ? latest.time / 1000 : 10;
  const minTime = latest && seconds === 'all' ? recording.get(0).time / 1000 : Math.max(0, maxTime - Number(seconds));
  const endTime = Math.max(maxTime, minTime + 0.005);
  let first = 0;
  // Binary search the retained ring, avoiding full scans of off-screen samples.
  let lo = 0, hi = recording.length;
  while (lo < hi) { const mid = (lo + hi) >>> 1; if (recording.get(mid).time / 1000 < minTime) lo = mid + 1; else hi = mid; }
  first = lo;
  const views = {
    angle: { title: '角度偏差曲线', unit: '°', names: ['数码管角度偏差'], colors: ['#62dfc5'], reads: [p => p.angle] },
    pwm: { title: '要求与实际 PWM', unit: '%', names: ['要求 PWM', '实际 PWM'], colors: ['#fbbf24', '#60a5fa'], reads: [p => Telemetry.pwmPercent(p.requestedPwm), p => Telemetry.pwmPercent(p.actualPwm)] },
    position: { title: '转臂位置、目标与最短误差', unit: 'counts', names: ['转臂位置', '位置目标', '位置误差'], colors: ['#62dfc5', '#fbbf24', '#c4b5fd'], reads: [p => p.armPosition ?? null, p => p.positionTarget ?? null, p => p.positionError ?? null] },
    offset: { title: '角度与位置环目标倾角偏移', unit: '°', names: ['角度偏差', '目标倾角偏移'], colors: ['#62dfc5', '#fbbf24'], reads: [p => p.angle, p => Telemetry.offsetDegrees(p.targetAngleOffsetAdc)] }
  };
  const view = views[$('signal').value] || views.angle;
  const series = view.reads.map((read, index) => ({ read, color: view.colors[index] }));
  $('chartTitle').textContent = view.title;
  $('chartLegend').innerHTML = view.names.map((name, index) => `<span class="legend" style="background:${view.colors[index]}"></span>${name}`).join(' ') + `<span class="muted">/ 单位 ${view.unit}</span>`;
  let hasVisibleData = false;
  let minimum = 0, maximum = 0;
  for (let index = first; index < recording.length; index++) {
    for (const trace of series) {
      const value = trace.read(recording.get(index));
      if (value === null) continue;
      hasVisibleData = true; minimum = Math.min(minimum, value); maximum = Math.max(maximum, value);
    }
  }
  const padding = Math.max(0.5, (maximum - minimum) * 0.15);
  const yMin = minimum - padding, yMax = maximum + padding;
  const x = time => box.left + (time - minTime) / (endTime - minTime) * (box.right - box.left);
  const y = value => box.bottom - (value - yMin) / (yMax - yMin) * (box.bottom - box.top);
  ctx.font = '11px Consolas, monospace'; ctx.lineWidth = 1;
  for (let i = 0; i <= 4; i++) {
    const value = yMin + (yMax - yMin) * i / 4;
    ctx.strokeStyle = '#2a3547'; ctx.beginPath(); ctx.moveTo(box.left, y(value)); ctx.lineTo(box.right, y(value)); ctx.stroke();
    ctx.fillStyle = '#8597b1'; ctx.textAlign = 'right'; ctx.fillText(value.toFixed(1), box.left - 12, y(value) + 4);
  }
  for (let i = 0; i <= 5; i++) {
    const time = minTime + (endTime - minTime) * i / 5;
    ctx.strokeStyle = '#232e3e'; ctx.beginPath(); ctx.moveTo(x(time), box.top); ctx.lineTo(x(time), box.bottom); ctx.stroke();
    ctx.fillStyle = '#8597b1'; ctx.textAlign = i === 0 ? 'left' : i === 5 ? 'right' : 'center'; ctx.fillText(time.toFixed(endTime - minTime < 1 ? 3 : 2), x(time), box.bottom + 24);
  }
  ctx.setLineDash([4, 4]); ctx.strokeStyle = '#52637b'; ctx.beginPath(); ctx.moveTo(box.left, y(0)); ctx.lineTo(box.right, y(0)); ctx.stroke(); ctx.setLineDash([]);
  ctx.fillStyle = '#8597b1'; ctx.textAlign = 'left'; ctx.fillText(view.unit, 8, box.top);
  if (latest) {
    ctx.save(); ctx.beginPath(); ctx.rect(box.left, box.top, box.right - box.left, box.bottom - box.top); ctx.clip();
    for (const trace of series) {
    ctx.strokeStyle = trace.color; ctx.lineWidth = 1.6; ctx.beginPath();
    let previous = null, bucket = null;
    // Per-pixel extrema preserve short peaks when many samples share one pixel.
    function flush() {
      if (!bucket) return;
      const points = [bucket.first, bucket.min, bucket.max, bucket.last].sort((a, b) => a.time - b.time);
      for (const point of points) {
        const circularJump = $('signal').value === 'position' && trace !== series[1] && previous && Math.abs(trace.read(point) - trace.read(previous)) > Telemetry.COUNTS_PER_REV / 2;
        if (!previous || circularJump || point.gap && point !== previous || point.session !== previous.session) ctx.moveTo(x(point.time / 1000), y(trace.read(point)));
        else ctx.lineTo(x(point.time / 1000), y(trace.read(point)));
        previous = point;
      }
      bucket = null;
    }
    for (let index = first; index < recording.length; index++) {
      const point = recording.get(index), pixel = Math.floor(x(point.time / 1000));
      if (trace.read(point) === null) { flush(); previous = null; continue; }
      if (bucket && (bucket.pixel !== pixel || point.gap || bucket.last.session !== point.session)) flush();
      if (!bucket) bucket = { pixel, first: point, last: point, min: point, max: point };
      else { bucket.last = point; if (trace.read(point) < trace.read(bucket.min)) bucket.min = point; if (trace.read(point) > trace.read(bucket.max)) bucket.max = point; }
    }
    flush(); ctx.stroke();
    if (trace.read(latest) !== null) { ctx.fillStyle = trace.color; ctx.beginPath(); ctx.arc(x(latest.time / 1000), y(trace.read(latest)), 3, 0, 2 * Math.PI); ctx.fill(); }
    }
    ctx.restore();
  }
  $('empty').hidden = !!latest && hasVisibleData;
  $('range').textContent = latest ? hasVisibleData ? `范围 ${minimum.toFixed(1)} ${view.unit} ～ ${maximum.toFixed(1)} ${view.unit}` : `该文件没有${$('signal').value === 'pwm' ? ' PWM' : '位置'}数据` : '—';
  chartView = { box, minTime, endTime, first, last: recording.length - 1, x, y };
}
canvas.addEventListener('pointermove', event => {
  if (!recording.length || !chartView || frozen) return;
  const rect = canvas.getBoundingClientRect(), pixel = event.clientX - rect.left;
  const time = chartView.minTime + (pixel - chartView.box.left) / (chartView.box.right - chartView.box.left) * (chartView.endTime - chartView.minTime);
  let lo = chartView.first, hi = chartView.last;
  while (lo < hi) { const mid = (lo + hi) >>> 1; if (recording.get(mid).time / 1000 < time) lo = mid + 1; else hi = mid; }
  const point = recording.get(lo); if (!point) return;
  const tooltip = $('tooltip'); tooltip.hidden = false;
  const pwmText = v => v == null ? '无数据' : `${Telemetry.pwmPercent(v).toFixed(2)}%`;
  const countsText = v => v == null ? '无数据' : `${v} counts`;
  const offsetText = point.targetAngleOffsetAdc == null ? '无数据' : `${Telemetry.offsetDegrees(point.targetAngleOffsetAdc).toFixed(3)}°`;
  tooltip.textContent = `${(point.time / 1000).toFixed(3)} s\n${point.angle.toFixed(1)}°\n要求 ${pwmText(point.requestedPwm)}\n实际 ${pwmText(point.actualPwm)}\n位置 ${countsText(point.armPosition)}\n目标 ${countsText(point.positionTarget)}\n误差 ${countsText(point.positionError)}\n目标偏移 ${offsetText}`;
  tooltip.style.left = `${Math.max(4, Math.min(canvas.clientWidth - 230, pixel + 12))}px`;
  tooltip.style.top = `${Math.max(0, Math.min(canvas.clientHeight - 180, event.clientY - rect.top - 50))}px`;
});
canvas.addEventListener('pointerleave', () => { $('tooltip').hidden = true; });
new ResizeObserver(() => { dirty = true; if (frozen) draw(); }).observe(canvas);
function animate(now) {
  if (dirty && !frozen && now - lastPaint > 33) { draw(); dirty = false; lastPaint = now; }
  requestAnimationFrame(animate);
}
if (typeof CalibrationApp !== 'undefined') calibration = CalibrationApp.create({ getElement: $, send: writeCommand, isConnected: () => !!port && !disconnecting, onStateChange: () => { if (calibration?.locked) streaming = false; updateControls(); } });
if (!('serial' in navigator)) message('当前浏览器无法访问串口。请在桌面 Chrome / Edge 中打开本地网页；此处仍可导入数据查看曲线。', true);
else if (!window.isSecureContext) message('串口需要安全上下文，请通过启动脚本提供的 http://localhost:8765 打开网页。', true);
updateControls(); refreshMetrics(); draw(); requestAnimationFrame(animate); setInterval(refreshMetrics, 250);

(function (root) {
  'use strict';
  const RESULT = ['等待结果', '起动成功', '维持成功', '未起动', '未持续运动', '触及行程', '传感器故障', '手动停止', '心跳超时', '拒绝执行', 'PWM 未到位', '无效', '未静止', '预检结束', '摆杆达到角度阈值', '摆杆未达到角度阈值'];
  const PHASE = ['待机', '等待 PWM', '电流预检', '起动观察', '起动阶段', '过渡阶段', '维持观察', '完成', '平衡叠加脉冲'];
  const INVALID_RESULTS = new Set([5, 6, 7, 8, 9, 10, 11, 12]);
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  function crc8(text) {
    let value = 0;
    for (const char of text) {
      const byte = char.charCodeAt(0);
      if (byte > 127) throw new Error('协议字段必须为 ASCII');
      value ^= byte;
      for (let bit = 0; bit < 8; bit++) value = ((value << 1) ^ (value & 0x80 ? 7 : 0)) & 255;
    }
    return value;
  }
  function command(name, ...fields) {
    if (name === 'i' && fields.length === 0) return '!i\n';
    const body = [name, ...fields].join(',');
    const counts = { c: 4, b: 4, r: 4, p: 5, h: 1, g: 2, e: 1 };
    if (counts[name] !== fields.length || fields.some(v => !Number.isInteger(v))) throw new Error('校准命令字段不正确');
    const sid = fields[0];
    if (sid < 1 || sid > 0xffffffff) throw new Error('会话编号超出范围');
    if (['b', 'r', 'p', 'g'].includes(name) && (fields[1] < 1 || fields[1] > 65535)) throw new Error('试次编号超出范围');
    if (name === 'c' && (fields[1] < 64 || fields[1] > 65535 || fields[2] < 5 || fields[2] > 150 || ![-1, 1].includes(fields[3]))) throw new Error('CPR 须为 64～65535；行程须为 0.5～15°；编码器方向须为 ±1');
    if (name === 'b' && (fields[2] === 0 || Math.abs(fields[2]) > 500 || ![0, 1].includes(fields[3]))) throw new Error('试验 PWM 或类型不正确');
    if (name === 'r' && (fields[2] === 0 || Math.abs(fields[2]) > 500 || Math.abs(fields[3]) > Math.abs(fields[2]) || fields[3] !== 0 && Math.sign(fields[2]) !== Math.sign(fields[3]))) throw new Error('起动 PWM 必须非零且在 20% 以内；维持 PWM 允许零，非零时须同向且不超过起动档');
    if (name === 'p' && (Math.abs(fields[2]) > 2500 || fields[3] < 1 || fields[3] > 5000 || fields[4] < 1 || fields[4] > 4095)) throw new Error('叠加 PWM 须在 ±100% 以内，时间须为 1～5000 ms，角度阈值须为 1～4095 ADC 码');
    return `!${body},${crc8(body).toString(16).toUpperCase().padStart(2, '0')}\n`;
  }
  const hex = (value, digits) => new RegExp(`^[0-9A-Fa-f]{${digits}}$`).test(value);
  const signed32 = value => parseInt(value, 16) | 0;
  const stamp = value => value.toUpperCase() === 'FFFFFFFF' ? null : parseInt(value, 16);
  function parseLine(line) {
    const start = line.search(/[IMRN],/);
    if (start < 0) return null;
    line = line.slice(start).replace(/\r$/, '');
    const fields = line.split(','), checksum = fields.pop();
    if (!hex(checksum, 2) || crc8(fields.join(',')) !== parseInt(checksum, 16)) throw new Error('校准帧 CRC 错误');
    if (fields[0] === 'I') {
      if (fields.length !== 11 || !['DZCAL1', 'DZCAL2'].includes(fields[1]) || !hex(fields[2], 8) || !fields.slice(3).every(v => hex(v, 4))) throw new Error('能力帧格式不正确');
      const [pwmMax, cpr, periodMs, maxPercent, startDeadlineMs, runDeadlineMs, heartbeatMs, travelTenths] = fields.slice(3).map(v => parseInt(v, 16));
      const maxCounts = Math.floor(pwmMax * maxPercent / 100);
      const uprightPulse = fields[1] === 'DZCAL2';
      if (pwmMax !== 2500 || cpr < 1 || cpr > 1000000 || periodMs !== 10 || maxCounts < 1 || maxCounts > (uprightPulse ? 2500 : 500) || startDeadlineMs < 1 || startDeadlineMs > 120 || runDeadlineMs < 1 || runDeadlineMs > (uprightPulse ? 5000 : 600) || heartbeatMs < 100 || heartbeatMs > 200 || travelTenths < 1 || travelTenths > 150) throw new Error('固件测试能力与当前网页不兼容');
      return { type: 'I', protocol: fields[1], buildId: fields[2].toUpperCase(), pwmMax, cpr, periodMs, maxCounts, startDeadlineMs, runDeadlineMs, maxDurationMs: uprightPulse ? runDeadlineMs : null, uprightPulse, heartbeatMs, travelTenths };
    }
    if (fields[0] === 'M') {
      if (![12, 13].includes(fields.length) || !hex(fields[1], 8) || !hex(fields[2], 8) || !hex(fields[3], 4) || !fields.slice(4, 7).every(v => hex(v, 1)) || !hex(fields[7], 8) || !fields.slice(8, 10).every(v => /^[+-]\d{4}$/.test(v) && Math.abs(Number(v)) <= 2500) || !hex(fields[10], 4) || !hex(fields[11], 1) || fields.length === 13 && !hex(fields[12], 1)) throw new Error('测量帧格式不正确');
      const phase = parseInt(fields[4], 16), result = parseInt(fields[5], 16), flags = parseInt(fields[11], 16);
      if (phase > (fields.length === 13 ? 8 : 7) || result > (fields.length === 13 ? 15 : 13) || flags > 7 || parseInt(fields[10], 16) > 4095) throw new Error('测量帧状态不正确');
      return { type: 'M', ms: parseInt(fields[1], 16), session: parseInt(fields[2], 16), trial: parseInt(fields[3], 16), phase, result, fault: parseInt(fields[6], 16), position: signed32(fields[7]), requested: Number(fields[8]), actual: Number(fields[9]), sample: parseInt(fields[10], 16), flags, coreState: fields.length === 13 ? parseInt(fields[12], 16) : null, sampleValid: !!(flags & 1), sessionActive: !!(flags & 2), active: !!(flags & 4) };
    }
    if (fields[0] === 'R') {
      if (fields.length !== 13 || !hex(fields[1], 8) || !hex(fields[2], 4) || !hex(fields[3], 1) || !fields.slice(4, 10).every(v => hex(v, 8)) || !fields.slice(10).every(v => hex(v, 4))) throw new Error('结果帧格式不正确');
      const result = parseInt(fields[3], 16);
      if (result > 13) throw new Error('结果码不正确');
      return { type: 'R', session: parseInt(fields[1], 16), trial: parseInt(fields[2], 16), result, tCommand: stamp(fields[4]), tPwm: stamp(fields[5]), tEdge: stamp(fields[6]), tEnd: stamp(fields[7]), startPosition: signed32(fields[8]), endPosition: signed32(fields[9]), windows: fields.slice(10).map(v => parseInt(v, 16)) };
    }
    if (fields[0] === 'N') {
      if (fields.length !== 18 || !hex(fields[1], 8) || !hex(fields[2], 4) || !hex(fields[3], 1) || !fields.slice(4, 11).every(v => hex(v, 8)) || !fields.slice(11, 14).every(v => hex(v, 4)) || !/^[+-]\d{4}$/.test(fields[14]) || !fields.slice(15, 17).every(v => hex(v, 4)) || !/^[+-]\d{4}$/.test(fields[17])) throw new Error('平衡脉冲结果帧格式不正确');
      const result = parseInt(fields[3], 16), startAdc = parseInt(fields[11], 16), endAdc = parseInt(fields[12], 16), maxDeltaAdc = parseInt(fields[13], 16), added = Number(fields[14]), durationMs = parseInt(fields[15], 16), thresholdAdc = parseInt(fields[16], 16), baseline = Number(fields[17]);
      if (result > 15 || [startAdc, endAdc, maxDeltaAdc].some(v => v > 4095) || Math.abs(added) > 2500 || Math.abs(baseline) > 2500 || durationMs < 1 || durationMs > 5000 || thresholdAdc < 1 || thresholdAdc > 4095) throw new Error('平衡脉冲结果值不正确');
      return { type: 'N', session: parseInt(fields[1], 16), trial: parseInt(fields[2], 16), result, tCommand: stamp(fields[4]), tPwm: stamp(fields[5]), tEdge: stamp(fields[6]), tAdc: stamp(fields[7]), tEnd: stamp(fields[8]), startPosition: signed32(fields[9]), endPosition: signed32(fields[10]), startAdc, endAdc, maxDeltaAdc, added, durationMs, thresholdAdc, baseline };
    }
    return null;
  }
  class LineDecoder {
    constructor(onFrame, onError = () => {}) { this.onFrame = onFrame; this.onError = onError; this.pending = ''; this.invalid = 0; }
    feed(text) {
      this.pending += text;
      let end;
      while ((end = this.pending.indexOf('\n')) >= 0) {
        const line = this.pending.slice(0, end); this.pending = this.pending.slice(end + 1);
        try { const frame = parseLine(line); if (frame) this.onFrame(frame); }
        catch (error) { this.invalid++; this.onError(error.message); }
      }
      if (this.pending.length > 2048) { this.pending = ''; this.invalid++; this.onError('校准接收行过长'); }
    }
  }
  const elapsed = (end, begin) => end == null || begin == null ? null : (end - begin) >>> 0;
  // A trial lasts at most 600 ms. Motion can precede settled PWM during ramp-up;
  // keep that offset signed while also handling the 32-bit board-clock wrap.
  const responseDelay = (edge, pwm) => edge == null || pwm == null ? null : (edge - pwm) | 0;
  const adcDegrees = codes => codes * 333 / 4095;
  function angleCodes(degrees) { if (!Number.isFinite(degrees) || degrees <= 0 || degrees > 333) throw new Error('移动角度阈值须大于 0° 且不超过 333°'); return Math.ceil(degrees * 4095 / 333); }
  const csvValue = value => `"${String(value ?? '').replace(/"/g, '""')}"`;
  const csv = rows => '\ufeff' + rows.map(row => row.map(csvValue).join(',')).join('\r\n') + '\r\n';
  function electricalCheck(reading, metadata) {
    if (!reading || !metadata) return false;
    const limit = Math.min(0.8, Number(metadata.motorAllowedA));
    return Number.isFinite(reading.currentPeakA) && reading.currentPeakA >= 0 && reading.currentPeakA <= limit && Number.isFinite(reading.vmMinV) && reading.vmMinV >= 0.95 * Number(metadata.vmV) && Number(metadata.vmV) > 0 && limit > 0;
  }
  class Measurement {
    constructor(capacity = 120000) { this.capacity = capacity; this.clear(); }
    clear() { this.samples = []; this.trials = []; this.rawFrames = []; this.sessions = []; this.metadata = null; this.capability = null; this.manifest = null; this.dropped = 0; this.gaps = 0; this.invalidFrames = 0; this.lastSample = null; }
    setMetadata(metadata, capability, manifest) { this.metadata = Object.freeze({ ...metadata }); this.capability = { ...capability }; this.manifest = manifest ? JSON.parse(JSON.stringify(manifest)) : null; this.sessions.push({ metadata: this.metadata, capability: this.capability, manifest: this.manifest }); }
    addTrial(trial) {
      if (this.trials.some(t => t.session === trial.session && t.id === trial.id)) throw new Error('重复试次编号');
      this.trials.push({ ...trial, direction: trial.direction || Math.sign(trial.counts) || Math.sign(trial.kick) || 1, metadata: this.metadata, capability: this.capability, manifest: this.manifest, result: null, confirmed: null, electrical: null, dataGap: false, invalidReason: '' });
      return this.trials[this.trials.length - 1];
    }
    findTrial(session, id) { return this.trials.find(t => t.session === session && t.id === id); }
    addFrame(frame) {
      if (frame.type === 'M') {
        const previous = this.lastSample;
        const delta = previous && previous.session === frame.session ? elapsed(frame.ms, previous.ms) : 0;
        if (previous && previous.session === frame.session && delta === 0) return false;
        const gap = delta > 15;
        if (gap) { this.gaps += Math.max(1, Math.round(delta / 10) - 1); const trial = this.findTrial(frame.session, frame.trial); if (trial && !trial.result) trial.dataGap = true; }
        frame = { ...frame, gap }; this.samples.push(frame); this.lastSample = frame;
        if (this.samples.length > this.capacity) { this.samples.shift(); this.dropped++; }
      } else if (frame.type === 'R' || frame.type === 'N') {
        if (!frame.trial || frame.result === 0 || frame.tEnd == null) return false;
        const trial = this.findTrial(frame.session, frame.trial);
        if (!trial || trial.result) return false;
        trial.result = { ...frame }; trial.delayMs = frame.type === 'N' ? elapsed(frame.tAdc, frame.tCommand) : responseDelay(frame.tEdge, frame.tPwm); trial.completedAt = Date.now();
        if (frame.type === 'N') {
          trial.maxMovementDegrees = adcDegrees(frame.maxDeltaAdc); trial.netMovementDegrees = adcDegrees(frame.endAdc - frame.startAdc) * (trial.metadata?.angleInvert ? -1 : 1); trial.armDelayMs = elapsed(frame.tEdge, frame.tCommand);
          if (trial.profile !== 3 || frame.added !== trial.counts || frame.durationMs !== trial.durationMs || frame.thresholdAdc !== trial.thresholdAdc) trial.invalidReason ||= '板端脉冲参数与请求不一致';
        }
      } else return false;
      this.rawFrames.push({ ...frame });
      if (this.rawFrames.length > this.capacity) this.rawFrames.shift();
      return true;
    }
    classify(trial) {
      if (!trial.result) return trial.invalidReason ? 'invalid' : 'pending';
      if (trial.invalidReason || trial.dataGap || INVALID_RESULTS.has(trial.result.result)) return 'invalid';
      if (trial.profile === 3) return trial.result.type === 'N' && trial.result.result === 14 ? 'success' : trial.result.type === 'N' && trial.result.result === 15 ? 'failure' : 'invalid';
      if (trial.profile === 0) return trial.result.result === 13 && electricalCheck(trial.electrical, trial.metadata) ? 'prechecked' : 'invalid';
      if ([1, 2].includes(trial.result.result)) return trial.confirmed === true ? 'success' : trial.confirmed === false ? 'invalid' : 'unconfirmed';
      if ([3, 4].includes(trial.result.result)) return trial.confirmed === false ? 'failure' : trial.confirmed === true ? 'invalid' : 'unconfirmed';
      return 'invalid';
    }
    prechecked(session, counts) { return this.trials.some(t => t.session === session && t.profile === 0 && t.counts === counts && this.classify(t) === 'prechecked'); }
    groups() {
      const groups = new Map();
      for (const trial of this.trials.filter(t => t.profile !== 0)) {
        const key = `${trial.location}|${trial.profile}|${trial.direction}|${trial.counts}|${trial.durationMs ?? ''}|${trial.thresholdAdc ?? ''}`;
        if (!groups.has(key)) groups.set(key, { location: trial.location, profile: trial.profile, direction: trial.direction, counts: trial.counts, durationMs: trial.durationMs, thresholdAdc: trial.thresholdAdc, thresholdDegrees: trial.thresholdDegrees, success: 0, failure: 0, invalid: 0, unconfirmed: 0, pending: 0, delays: [] });
        const group = groups.get(key), status = this.classify(trial); group[status]++;
        if (status === 'success' && trial.delayMs != null) group.delays.push(trial.delayMs);
      }
      return [...groups.values()].sort((a, b) => a.location.localeCompare(b.location) || a.profile - b.profile || a.counts - b.counts);
    }
    threshold(location, profile, direction) {
      if (profile === 3) return null;
      const reliable = this.groups().filter(g => g.location === location && g.profile === profile && g.direction === direction && g.success >= 5 && g.failure === 0 && g.unconfirmed === 0 && g.pending === 0);
      if (!reliable.length) return null;
      const winner = reliable.sort((a, b) => Math.abs(a.counts) - Math.abs(b.counts))[0];
      const lower = this.groups().filter(g => g.location === location && g.profile === profile && g.direction === direction && Math.abs(g.counts) < Math.abs(winner.counts) && g.failure > 0).sort((a, b) => Math.abs(b.counts) - Math.abs(a.counts))[0];
      return { counts: winner.counts, lowerCounts: lower?.counts ?? null, successes: winner.success, delays: winner.delays };
    }
    rawCsv() {
      if (this.rawFrames.some(f => f.type === 'N') || this.capability?.uprightPulse) {
        const keys = ['type','ms','session','trial','phase','result','fault','coreState','position','requested','actual','sample','sampleValid','flags','gap','tCommand','tPwm','tEdge','tAdc','tEnd','startPosition','endPosition','startAdc','endAdc','maxDeltaAdc','added','durationMs','thresholdAdc','baseline'];
        return csv([keys, ...this.rawFrames.map(f => keys.map(k => typeof f[k] === 'boolean' ? Number(f[k]) : f[k] ?? ''))]);
      }
      const rows = [['record_type','board_ms','session','trial','phase','result','fault','position_counts','requested_counts','actual_counts','adc','adc_valid','flags','gap','t_command_ms','t_pwm_ms','t_edge_ms','t_end_ms','start_position','end_position','window1_counts','window2_counts','window3_counts']];
      for (const f of this.rawFrames) rows.push(f.type === 'M' ? [f.type,f.ms,f.session,f.trial,f.phase,f.result,f.fault,f.position,f.requested,f.actual,f.sample,f.sampleValid ? 1 : 0,f.flags,f.gap ? 1 : 0,...Array(9).fill('')] : [f.type,'',f.session,f.trial,'',f.result,'','','','','','','','',f.tCommand,f.tPwm,f.tEdge,f.tEnd,f.startPosition,f.endPosition,...f.windows]);
      return csv(rows);
    }
    summaryCsv() {
      const rows = [['session','trial','location','profile','direction','counts','pwm_percent','kick_counts','board_result','classification','physical_motion_confirmed','delay_ms','net_counts','w1','w2','w3','current_peak_a','vm_min_v','data_gap','invalid_reason','firmware_build_id','metadata_json','manifest_json','specified_duration_ms','angle_threshold_degrees','angle_threshold_adc','pendulum_max_degrees','pendulum_net_degrees','pendulum_hit_from_command_ms','arm_hit_from_command_ms','start_adc','end_adc','baseline_counts','reported_added_counts','reported_duration_ms','reported_threshold_adc']];
      for (const t of this.trials) rows.push([t.session,t.id,t.location,t.profile,t.direction,t.counts,t.counts * 100 / (t.capability?.pwmMax || 2500),t.kick ?? '',t.result?.result ?? '',this.classify(t),t.confirmed == null ? '' : Number(t.confirmed),t.delayMs ?? '',t.result ? (t.result.endPosition - t.result.startPosition) | 0 : '',...(t.result?.windows || ['','','']),t.electrical?.currentPeakA ?? '',t.electrical?.vmMinV ?? '',Number(t.dataGap),t.invalidReason,t.capability?.buildId,JSON.stringify(t.metadata),JSON.stringify(t.manifest),t.durationMs ?? '',t.thresholdDegrees ?? '',t.thresholdAdc ?? '',t.maxMovementDegrees ?? '',t.netMovementDegrees ?? '',t.profile === 3 ? t.delayMs ?? '' : '',t.armDelayMs ?? '',t.result?.startAdc ?? '',t.result?.endAdc ?? '',t.result?.baseline ?? '',t.result?.added ?? '',t.result?.durationMs ?? '',t.result?.thresholdAdc ?? '']);
      return csv(rows);
    }
    uprightReport() {
      const groups = this.groups().filter(g => g.profile === 3);
      const groupRows = groups.map(g => `<tr><td>${esc(g.location)}</td><td>${(g.counts / 25).toFixed(2)}%</td><td>${g.durationMs}</td><td>${adcDegrees(g.thresholdAdc).toFixed(3)}</td><td>${g.success}/${g.success + g.failure}</td><td>${g.invalid}</td><td>${g.delays.length ? `${Math.min(...g.delays)}～${Math.max(...g.delays)}` : '—'}</td></tr>`).join('');
      const trialRows = this.trials.filter(t => t.profile === 3).map(t => `<tr><td>${t.session}/${t.id}</td><td>${(t.counts / 25).toFixed(2)}%</td><td>${t.durationMs}</td><td>${t.thresholdDegrees}</td><td>${esc(t.result ? RESULT[t.result.result] : '等待结果')}</td><td>${t.maxMovementDegrees == null ? '—' : t.maxMovementDegrees.toFixed(3)}</td><td>${t.delayMs ?? '—'}</td><td>${t.result ? (t.result.endPosition - t.result.startPosition) | 0 : '—'}</td><td>${t.result ? (t.result.baseline / 25).toFixed(2) + '%' : '—'}</td></tr>`).join('');
      const references = new Map();
      const traces = this.samples.map(p => {
        const key = `${p.session}:${p.trial}`, trial = this.findTrial(p.session, p.trial);
        if (p.sampleValid && !references.has(key)) references.set(key, p.sample);
        const reference = trial?.result?.startAdc ?? references.get(key);
        return { ...p, angleRelative: p.sampleValid && reference != null ? adcDegrees(p.sample - reference) * (trial?.metadata?.angleInvert ? -1 : 1) : null };
      });
      const reportData = JSON.stringify({ metadata: this.metadata, sessions: this.sessions, capability: this.capability, manifest: this.manifest, traces, trials: this.trials, groups, dropped: this.dropped, gaps: this.gaps, invalidFrames: this.invalidFrames }).replace(/</g, '\\u003c');
      return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Furuta 平衡位置 PWM 脉冲实测报告</title>
<style>body{font:15px system-ui,sans-serif;max-width:1200px;margin:32px auto;padding:0 20px;color:#172033}h1{font-size:26px}h2{font-size:19px}table{border-collapse:collapse;width:100%;font-size:13px}th,td{border:1px solid #ccd5df;padding:8px;text-align:left}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f0f3f7;padding:15px}canvas{width:100%;height:280px;border:1px solid #ccd5df}p,li{line-height:1.7}select{padding:8px}small{color:#58657b}.table{overflow-x:auto}</style>
<h1>Furuta 平衡位置 PWM 脉冲实测报告</h1><p>生成时间：${esc(new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' }))}。固件构建：${esc(this.capability?.buildId || '未识别')}。</p>
<p>平衡 PID 持续运行，设定的 PWM 是附加到 PID 上的脉冲，实际总输出会在 ±100% 限幅。记录两个可修改参数：叠加 PWM 大小和输出时间；运动判据是摆杆相对试次初始 ADC 移动所选角度。达到判据后，脉冲仍持续到设定时间。此结果反映闭环平衡响应，不能直接当作电机静摩擦常数。相同时间的 0% 试次可用于比较自然平衡波动。</p>
<h2>PWM × 时间 × 角度判据</h2><div class="table"><table><thead><tr><th>位置</th><th>叠加 PWM</th><th>输出时间 ms</th><th>实际量化角度阈值 °</th><th>命中/有效</th><th>无效</th><th>指令到摆杆达阈值 ms</th></tr></thead><tbody>${groupRows || '<tr><td colspan="7">尚无实测，不生成推测值。</td></tr>'}</tbody></table></div>
<h2>每次测量</h2><div class="table"><table><thead><tr><th>会话/试次</th><th>叠加 PWM</th><th>指定时间 ms</th><th>指定角度 °</th><th>板端结果</th><th>摆杆最大移动 °</th><th>首次达阈值 ms</th><th>转臂净计数</th><th>起始实际总 PWM</th></tr></thead><tbody>${trialRows || '<tr><td colspan="9">尚无试次。</td></tr>'}</tbody></table></div><p>首次达阈值时间 = 摆杆 ADC 达到角度阈值时刻 − 接受脉冲指令时刻；空值表示未达阈值或相应事件缺失。摆杆相对角度 = ADC 差值 × 333° / 4095；最大变化为绝对值。原始 ADC、转臂事件和实际 PWM 均保留在 CSV 与下方完整记录中。</p>
<h2>原始曲线</h2><label>曲线 <select id="signal"><option value="angle">摆杆相对初始角度 (°)</option><option value="pwm">要求总 / 实际总 PWM (%)</option><option value="adc">原始摆杆 ADC</option><option value="position">转臂计数</option></select></label><canvas id="plot"></canvas><small>会话、试次边界及数据缺口断线。M 帧每 10 ms，短脉冲的运动时刻以板端 N 事件时间为准。</small>
<h2>实验元信息</h2><pre>${esc(JSON.stringify({ metadata: this.metadata, capability: this.capability, manifest: this.manifest, gaps: this.gaps, dropped: this.dropped, invalidFrames: this.invalidFrames }, null, 2))}</pre><h2>全部试次与板端原始结果</h2><pre>${esc(JSON.stringify(this.trials, null, 2))}</pre><script type="application/json" id="data">${reportData}</script><script>
const d=JSON.parse(document.getElementById('data').textContent),c=document.getElementById('plot'),s=document.getElementById('signal');
function draw(){c.width=Math.max(400,c.clientWidth);c.height=280;const x=c.getContext('2d');x.clearRect(0,0,c.width,c.height);if(!d.traces.length)return;let time=0,prev=null;const q=d.traces.map(v=>{time+=prev&&v.session===prev.session?(v.ms-prev.ms)>>>0:10;prev=v;return{...v,time}});const readers=s.value==='pwm'?[v=>v.requested/25,v=>v.actual/25]:s.value==='adc'?[v=>v.sampleValid?v.sample:null]:s.value==='position'?[v=>v.position]:[v=>v.angleRelative];let min=0,max=0;for(const v of q)for(const read of readers){const n=read(v);if(n!==null){min=Math.min(min,n);max=Math.max(max,n)}}const pad=Math.max(s.value==='angle'?.05:1,(max-min)*.1);min-=pad;max+=pad;const left=60,right=c.width-15,px=t=>left+(t-q[0].time)/Math.max(1,time-q[0].time)*(right-left),py=n=>245-(n-min)/(max-min)*225;x.font='11px monospace';for(let i=0;i<5;i++){const n=min+(max-min)*i/4;x.strokeStyle='#dae1e9';x.beginPath();x.moveTo(left,py(n));x.lineTo(right,py(n));x.stroke();x.fillStyle='#596478';x.fillText(n.toFixed(2),2,py(n))}readers.forEach((read,i)=>{x.strokeStyle=['#bd7000','#2563eb'][i];x.beginPath();let last=null;for(const v of q){const n=read(v);if(n===null){last=null;continue}if(!last||v.gap||last.session!==v.session||last.trial!==v.trial)x.moveTo(px(v.time),py(n));else x.lineTo(px(v.time),py(n));last=v}x.stroke()});x.fillStyle='#596478';x.fillText('0 s',left,270);x.fillText(((time-q[0].time)/1000).toFixed(3)+' s',Math.max(left,right-90),270)}s.onchange=draw;window.onresize=draw;draw();
</script></html>`;
    }
    report() {
      if (this.capability?.uprightPulse || this.trials.some(t => t.profile === 3)) return this.uprightReport();
      const traces = this.samples.map(p => ({ ms: p.ms, position: p.position, requested: p.requested, actual: p.actual, session: p.session, gap: p.gap }));
      const groups = this.groups();
      const groupRows = groups.map(g => `<tr><td>${esc(g.location)}</td><td>${g.profile === 1 ? '起动' : '维持'}</td><td>${(g.counts / 25).toFixed(2)}%</td><td>${g.success}/${g.success + g.failure}</td><td>${g.invalid}</td><td>${g.unconfirmed}</td><td>${g.delays.length ? `${Math.min(...g.delays)}～${Math.max(...g.delays)}` : '—'}</td></tr>`).join('');
      const locations = [...new Set(this.trials.map(t => t.location))];
      const conclusions = locations.flatMap(location => [1, 2].flatMap(profile => [1, -1].map(direction => {
        const value = this.threshold(location, profile, direction);
        return `<li>${esc(location)} / ${profile === 1 ? 'D_start' : 'D_run'}${direction > 0 ? '+' : '−'}：${value ? `${(Math.abs(value.counts) / 25).toFixed(2)}%（5 次以上全成功${value.lowerCounts == null ? '；尚无相邻低档失败记录，门槛边界未闭合' : `；低档 ${(Math.abs(value.lowerCounts) / 25).toFixed(2)}% 存在失败`}）` : '尚无可靠实测值'}</li>`;
      })));
      const reportData = JSON.stringify({ metadata: this.metadata, sessions: this.sessions, capability: this.capability, manifest: this.manifest, traces, trials: this.trials, groups, dropped: this.dropped, gaps: this.gaps, invalidFrames: this.invalidFrames }).replace(/</g, '\\u003c');
      return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Furuta 电机死区实测报告</title><style>body{font:15px system-ui,sans-serif;max-width:1100px;margin:32px auto;padding:0 20px;color:#172033}h1{font-size:26px}h2{font-size:19px}table{border-collapse:collapse;width:100%;font-size:13px}th,td{border:1px solid #ccd5df;padding:8px;text-align:left}pre{white-space:pre-wrap;background:#f0f3f7;padding:15px}canvas{width:100%;height:260px;border:1px solid #ccd5df}p,li{line-height:1.7}button,select{padding:8px}small{color:#58657b}</style><h1>Furuta 电机死区实测报告</h1><p>生成时间：${esc(new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' }))}（Asia/Shanghai）。固件构建：${esc(this.capability?.buildId || '未识别')}。</p><h2>实测门槛</h2><ul>${conclusions.join('')}</ul><p>D_start 是短时起动补偿的参考；D_run 是运行补偿量级的参考。未自动修改 PID 或写入补偿。维持结果只适用于三个 100 ms 观察窗口，不能视为无限时间稳态。只有电机轴运动、供电明显下陷或门槛随位置变化时，应优先检查背隙、供电及机械。被动摆轴摩擦需要单独处理。</p><h2>候选档位统计</h2><table><thead><tr><th>位置</th><th>试验</th><th>指令 PWM</th><th>成功/有效</th><th>无效</th><th>待确认</th><th>起动延迟 ms</th></tr></thead><tbody>${groupRows || '<tr><td colspan="7">未完成实物试验；没有推测门槛。</td></tr>'}</tbody></table><p>起动延迟 = 首次运动时刻 − PWM 到位时刻；负值表示 PWM 爬升期间已经运动，空值表示缺少相应事件。</p><h2>原始曲线</h2><label>曲线 <select id="signal"><option value="pwm">要求/实际 PWM (%)</option><option value="position">未回绕位置 (counts)</option><option value="velocity">速度估算 (counts/s)</option></select></label><canvas id="plot"></canvas><small>数据缺口及会话边界断线。速度为相邻 10 ms 位置差分，仅作趋势参考。</small><h2>实验元信息</h2><pre>${esc(JSON.stringify({ ...this.metadata, capability: this.capability, manifest: this.manifest, gaps: this.gaps, dropped: this.dropped, invalidFrames: this.invalidFrames }, null, 2))}</pre><h2>全部试次</h2><pre>${esc(JSON.stringify(this.trials, null, 2))}</pre><script type="application/json" id="data">${reportData}</script><script>const d=JSON.parse(document.getElementById('data').textContent),c=document.getElementById('plot'),s=document.getElementById('signal');function draw(){const p=d.traces;c.width=Math.max(400,c.clientWidth);c.height=260;const x=c.getContext('2d');x.clearRect(0,0,c.width,c.height);if(!p.length)return;let time=0,prev=null;const q=p.map(v=>{const dt=prev&&v.session===prev.session?(v.ms-prev.ms)>>>0:10;time+=dt;const speed=prev&&!v.gap&&v.session===prev.session&&dt>0?(v.position-prev.position)*1000/dt:null;prev=v;return{...v,time,speed}});const kind=s.value,series=kind==='pwm'?[v=>v.requested/25,v=>v.actual/25]:kind==='velocity'?[v=>v.speed]:[v=>v.position];let min=0,max=0;for(const v of q)for(const read of series){const n=read(v);if(n!==null){min=Math.min(min,n);max=Math.max(max,n)}}const pad=Math.max(1,(max-min)*.1);min-=pad;max+=pad;const left=55,top=15,bottom=225,right=c.width-15;function px(t){return left+(t-q[0].time)/Math.max(1,time-q[0].time)*(right-left)}function py(v){return bottom-(v-min)/(max-min)*(bottom-top)}x.font='11px monospace';for(let i=0;i<5;i++){const v=min+(max-min)*i/4;x.strokeStyle='#dae1e9';x.beginPath();x.moveTo(left,py(v));x.lineTo(right,py(v));x.stroke();x.fillStyle='#596478';x.fillText(v.toFixed(1),2,py(v))}series.forEach((read,i)=>{x.strokeStyle=['#bd7000','#2563eb'][i];x.beginPath();let last=null;for(const v of q){const n=read(v);if(n===null){last=null;continue}if(!last||v.gap||last.session!==v.session)x.moveTo(px(v.time),py(n));else x.lineTo(px(v.time),py(n));last=v}x.stroke()});x.fillStyle='#596478';x.fillText('0 s',left,250);x.fillText(((time-q[0].time)/1000).toFixed(3)+' s',Math.max(left,right-90),250)}s.onchange=draw;window.onresize=draw;draw();</script></html>`;
    }
  }
  const api = { RESULT, PHASE, INVALID_RESULTS, crc8, command, parseLine, LineDecoder, Measurement, electricalCheck, elapsed, adcDegrees, angleCodes, esc };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.Calibration = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);

(function (root) {
  'use strict';
  function create(options) {
    const $ = options.getElement, model = new Calibration.Measurement();
    const now = options.now || (() => Date.now());
    let capability = null, manifest = null, session = null, pendingTrial = null, lastFrameAt = 0;
    let lastTrial = 0, sessionCounter = typeof crypto !== 'undefined' && crypto.getRandomValues ? crypto.getRandomValues(new Uint32Array(1))[0] : Math.floor(now() / 1000) >>> 0, busy = false, lastQueryAt = 0, lastStopAt = 0;
    let selectedTrial = null, dirty = true, diagnostic = '连接串口后读取固件能力。旧固件不能执行校准。';
    const configIds = ['cal-cpr', 'cal-travel', 'cal-encoderSign', 'cal-vm', 'cal-ratedVm', 'cal-motorAllowed', 'cal-encoderAxis', 'cal-directionNote', 'cal-location', 'cal-instrument', 'cal-environment', 'cal-ready'];
    const show = (text, error = false) => { diagnostic = text; $('cal-message').textContent = text; $('cal-message').classList.toggle('error', error); };
    const pct = counts => (counts * 100 / (capability?.pwmMax || 2500)).toFixed(2);
    const currentCounts = () => {
      const percentage = Number($('cal-duty').value), direction = Number($('cal-direction').value);
      if (!Number.isFinite(percentage) || percentage < 0 || percentage > (capability ? capability.maxCounts * 100 / capability.pwmMax : 20) || ![-1, 1].includes(direction)) throw new Error('请输入 0～20% 的 PWM（零只用于维持基准）');
      const counts = Math.round(percentage * (capability?.pwmMax || 2500) / 100);
      if (Math.abs(counts * 100 / (capability?.pwmMax || 2500) - percentage) > 0.000001) throw new Error('PWM 必须能精确转换为整数计数（当前分辨率 0.04%）');
      return direction * counts;
    };
    function trialKick(counts) {
      const direction = Math.sign(counts) || Number($('cal-direction').value);
      const threshold = model.threshold(session?.location || '', 1, direction);
      if (!threshold) return null;
      const kick = threshold.counts + direction * Math.round(capability.pwmMax / 100);
      return Math.abs(kick) <= capability.maxCounts ? kick : null;
    }
    function metadata() {
      const values = {
        cpr: Number($('cal-cpr').value), travelTenths: Math.round(Number($('cal-travel').value) * 10), encoderSign: Number($('cal-encoderSign').value),
        vmV: Number($('cal-vm').value), ratedVmV: Number($('cal-ratedVm').value), motorAllowedA: Number($('cal-motorAllowed').value), encoderAxis: $('cal-encoderAxis').value,
        directionNote: $('cal-directionNote').value.trim(), location: $('cal-location').value.trim(), instrument: $('cal-instrument').value.trim(), environment: $('cal-environment').value.trim(),
        createdAt: new Date(now()).toISOString(), timezone: 'Asia/Shanghai', currentMeasurement: '单根电机引线电流；外部测量，仅预检记录，非板端实时过流保护'
      };
      if (!Number.isInteger(values.cpr) || values.cpr < 64 || values.cpr > 65535 || !Number.isInteger(values.travelTenths) || values.travelTenths < 5 || values.travelTenths > capability.travelTenths || ![-1, 1].includes(values.encoderSign)) throw new Error('请填写 64～65535 的实测 CPR、0.5～15° 行程及编码器方向');
      if (Math.abs(Number($('cal-travel').value) * 10 - values.travelTenths) > 1e-8) throw new Error('行程以 0.1° 为步长');
      if (Math.floor(values.cpr * values.travelTenths / 3600) < 2) throw new Error('该 CPR 与行程不足 2 个计数，无法完成起动判据');
      if (![values.vmV, values.ratedVmV, values.motorAllowedA].every(v => Number.isFinite(v) && v > 0) || values.vmV > values.ratedVmV || values.vmV > 13.5) throw new Error('请填写额定电压、实际 VM 与允许电流；VM 不得超过电机额定电压或 TB6612 13.5 V 工作范围');
      if (!['motor', 'arm'].includes(values.encoderAxis) || !values.directionNote || !values.location || !values.instrument) throw new Error('请填写编码器轴位置、实际转向、试验位置及仪器');
      if (!$('cal-ready').checked) throw new Error('请完成机械行程、摆杆下垂及停止按键检查后勾选准备完成');
      return values;
    }
    function canPulse(profile, ignoreBusy = false) {
      if (!options.isConnected() || !capability || busy && !ignoreBusy || !session?.acknowledged || pendingTrial || now() - lastStopAt < 1000 || now() - lastFrameAt > 200) return false;
      const frame = model.lastSample;
      if (!frame || frame.session !== session.id || !frame.sessionActive || frame.active || frame.actual !== 0 || frame.fault) return false;
      let counts;
      try { counts = currentCounts(); } catch (_) { return false; }
      if (profile === 0) return counts !== 0;
      if (profile === 1 && counts === 0) return false;
      if (counts !== 0 && !model.prechecked(session.id, counts)) return false;
      if (profile === 2) {
        const kick = trialKick(counts);
        return kick !== null && model.prechecked(session.id, kick);
      }
      return true;
    }
    function update() {
      const connected = options.isConnected(), locked = !!session;
      $('cal-capability').textContent = capability ? `DZCAL1 / 构建 ${capability.buildId} / M ${capability.periodMs} ms / 最大 ${pct(capability.maxCounts)}%` : '未识别兼容校准固件';
      const manifestId = String(manifest?.build_id ?? manifest?.buildId ?? '').replace(/^0x/i, '').toUpperCase().padStart(8, '0');
      $('cal-manifestStatus').textContent = !manifest ? '构建清单未加载；可手动载入。' : !capability ? '清单已载入，等待板端能力确认。' : manifestId === capability.buildId ? '构建 ID 与板端匹配。清单随报告保留。' : '清单与板端构建 ID 不匹配；报告标记来源不一致。';
      configIds.forEach(id => $(id).disabled = locked || busy);
      $('cal-queryCap').disabled = !connected || locked || busy;
      $('cal-open').disabled = !connected || !capability || locked || busy;
      $('cal-end').disabled = !locked || busy;
      $('cal-emergency').disabled = !connected;
      $('cal-precheck').disabled = !canPulse(0);
      $('cal-pulse').disabled = !canPulse(Number($('cal-profile').value));
      $('cal-queryResult').disabled = !connected || !model.trials.length || busy || !!pendingTrial;
      $('cal-duty').disabled = !!pendingTrial || busy;
      $('cal-direction').disabled = !!pendingTrial || busy;
      $('cal-profile').disabled = !!pendingTrial || busy;
      $('cal-next').disabled = !!pendingTrial || busy;
      $('cal-step').disabled = !!pendingTrial || busy;
      $('cal-clear').disabled = locked || busy;
      $('cal-raw').disabled = !model.rawFrames.length;
      $('cal-summary').disabled = !model.trials.length;
      $('cal-report').disabled = !model.sessions.length;
      $('cal-manifest').disabled = locked;
      const last = model.lastSample;
      $('cal-state').textContent = session ? session.acknowledged ? `会话 ${session.id} · ${last ? Calibration.PHASE[last.phase] : '等待测量'}` : `会话 ${session.id} · 等待板端确认` : '校准会话已关闭';
      $('cal-live').textContent = last ? `板端 ${last.ms} ms · 转臂 ${last.position} counts · 要求 ${pct(last.requested)}% · 实际 ${pct(last.actual)}% · ADC ${last.sampleValid ? last.sample : '无效'} · 故障 ${last.fault}` : '等待 100 Hz 校准数据';
      $('cal-dataStatus').textContent = `M 样本 ${model.samples.length.toLocaleString()} · 缺口 ${model.gaps} · 无效帧 ${model.invalidFrames} · 已覆盖 ${model.dropped}`;
      let counts = 0;
      try { counts = currentCounts(); } catch (_) {}
      const kick = session ? trialKick(counts) : null;
      $('cal-gate').textContent = session ? `当前 ${pct(counts)}%：${counts === 0 ? '零维持基准无需电流预检，不能用于起动' : model.prechecked(session.id, counts) ? '电气预检通过' : '需先短预检并登记波形'}。维持试验起动 PWM：${kick == null ? '需该方向起动门槛 5/5 成功且留有 1% 余量' : `${pct(kick)}%${model.prechecked(session.id, kick) ? '（预检通过）' : '（也需先预检）'}`}。每次自动停机，试次之间至少停 1 秒。` : '校准会话确认后可进行单次测试。';
      $('cal-reviewSave').disabled = !selectedTrial?.result || busy;
      renderTables();
      if (dirty) { draw(); dirty = false; }
      options.onStateChange?.();
    }
    function renderTables() {
      const escape = Calibration.esc;
      $('cal-trials').innerHTML = model.trials.slice(-30).map(t => `<tr><td>${t.session}/${t.id}</td><td>${escape(t.location)}</td><td>${t.profile === 0 ? '预检' : t.profile === 1 ? '起动' : '维持'}</td><td>${pct(t.counts)}%</td><td>${t.result ? escape(Calibration.RESULT[t.result.result]) : '等待板端结果'}</td><td>${escape(model.classify(t))}</td><td>${t.delayMs ?? '—'}</td></tr>`).join('') || '<tr><td colspan="7">尚无试次</td></tr>';
      $('cal-groups').innerHTML = model.groups().map(g => `<tr><td>${escape(g.location)}</td><td>${g.profile === 1 ? '起动' : '维持'}</td><td>${pct(g.counts)}%</td><td>${g.success}/${g.success + g.failure}</td><td>${g.invalid}</td><td>${g.unconfirmed}</td></tr>`).join('') || '<tr><td colspan="6">边界档位需要每方向 5 次有效重复</td></tr>';
      const locations = [...new Set(model.trials.map(t => t.location))];
      $('cal-thresholds').textContent = locations.length ? locations.flatMap(location => [1, 2].flatMap(profile => [1, -1].map(direction => {
        const threshold = model.threshold(location, profile, direction);
        return `${location} ${profile === 1 ? 'D_start' : 'D_run'}${direction > 0 ? '+' : '−'} ${threshold ? `${pct(Math.abs(threshold.counts))}%${threshold.lowerCounts == null ? '（需低档失败记录闭合边界）' : `（低档 ${pct(Math.abs(threshold.lowerCounts))}% 有失败）`}` : '待实测'}`;
      }))).join('；') : '未完成实物试验，不生成推测门槛。';
    }
    function updateReviewOptions() {
      const select = $('cal-reviewTrial');
      select.innerHTML = model.trials.map(t => `<option value="${t.session}:${t.id}">${t.session}/${t.id} · ${t.profile === 0 ? '预检' : t.profile === 1 ? '起动' : '维持'} ${pct(t.counts)}%</option>`).join('');
      if (selectedTrial) select.value = `${selectedTrial.session}:${selectedTrial.id}`;
      fillReview();
    }
    function fillReview() {
      $('cal-current').value = selectedTrial?.electrical?.currentPeakA ?? '';
      $('cal-vmMin').value = selectedTrial?.electrical?.vmMinV ?? '';
      $('cal-motion').value = selectedTrial?.confirmed == null ? 'unknown' : selectedTrial.confirmed ? 'yes' : 'no';
      $('cal-comment').value = selectedTrial?.invalidReason || '';
      $('cal-motionTitle').textContent = selectedTrial?.profile === 2 ? '维持观察阶段持续运动？' : '转臂出现实际动作？';
    }
    function invalidatePending(reason) {
      if (pendingTrial) { pendingTrial.invalidReason = reason; if (!pendingTrial.result) pendingTrial.dataGap = true; }
      pendingTrial = null; dirty = true;
    }
    async function stopSession(reason) {
      const sid = session?.id;
      session = null; lastStopAt = now(); invalidatePending(reason); update();
      try { await options.send('X'); if (sid) await options.send(Calibration.command('e', sid)); await options.send('Q'); }
      catch (error) { show(`停机发送失败：${error.message}。板端仍有试次截止及 200 ms 心跳超时。`, true); throw error; }
      show(reason || '已发送 X、退出会话及 Q；需要重新建立会话才能测试。');
    }
    function onFrame(frame) {
      lastFrameAt = now();
      if (frame.type === 'I') {
        if (session && capability && frame.buildId !== capability.buildId) { void stopSession('板端构建变化，当前会话无效').catch(() => {}); }
        capability = frame;
        if (!session) $('cal-cpr').value = frame.cpr;
        show(`板端已确认校准能力。正反定义为控制指令方向；请先记录物理转向。`);
      } else {
        const retained = model.addFrame(frame);
        if (retained) dirty = true;
        if (frame.type === 'M' && session && frame.session === session.id) {
          if (frame.sessionActive) session.acknowledged = true;
          else if (session.acknowledged || frame.result >= 5 && frame.result <= 9) {
            const reason = `板端已关闭会话：${Calibration.RESULT[frame.result] || '停止'}。行程原点需重新建立。`;
            if (pendingTrial) pendingTrial.invalidReason ||= reason;
            session = null; lastStopAt = now(); show(reason, true);
          }
        }
        if (frame.type === 'R' && retained) {
          selectedTrial = model.findTrial(frame.session, frame.trial);
          if (pendingTrial === selectedTrial) pendingTrial = null;
          lastStopAt = now(); updateReviewOptions();
          show(`试次 ${frame.trial}：${Calibration.RESULT[frame.result]}。${selectedTrial.profile === 0 ? '请登记电流峰值及 VM 最低值后开放长测试。' : '请确认转臂是否实际运动；没有确认的试次不进入门槛统计。'}`, Calibration.INVALID_RESULTS.has(frame.result));
        }
      }
      if (frame.type !== 'M') update();
    }
    const decoder = new Calibration.LineDecoder(onFrame, error => {
      model.invalidFrames++; if (pendingTrial) pendingTrial.dataGap = true; show(`${error}；已保留原数据。`, true);
    });
    async function action(callback) {
      if (busy) return;
      busy = true; update();
      try { await callback(); } catch (error) { show(error.message, true); }
      finally { busy = false; update(); }
    }
    async function pulse(profile) {
      if (!canPulse(profile, true)) throw new Error('请等待会话确认、输出归零、停机 1 秒，并完成目标 PWM 电气预检');
      const counts = currentCounts(), kick = profile === 2 ? trialKick(counts) : null;
      if (lastTrial >= 65535) throw new Error('试次编号已耗尽，请退出并建立新会话');
      const id = ++lastTrial;
      const trial = model.addTrial({ session: session.id, id, location: session.location, profile, direction: Number($('cal-direction').value), counts, kick, sentAt: now() });
      pendingTrial = trial; selectedTrial = trial; updateReviewOptions();
      try { await options.send(profile === 2 ? Calibration.command('r', session.id, id, kick, counts) : Calibration.command('b', session.id, id, counts, profile)); }
      catch (error) { trial.invalidReason = `发送失败：${error.message}`; pendingTrial = null; throw error; }
      show(`已请求试次 ${id}；等待板端 M/R 确认。不会自动开始下一档。`); dirty = true;
    }
    function download(text, name, type) {
      const url = URL.createObjectURL(new Blob([text], { type })), link = document.createElement('a');
      link.href = url; link.download = name; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
    }
    $('cal-queryCap').addEventListener('click', () => action(() => options.send(Calibration.command('i'))));
    $('cal-open').addEventListener('click', () => action(async () => {
      if (!capability || !options.isConnected() || session) throw new Error('需先连接兼容固件，且不能重复打开会话');
      const meta = metadata();
      sessionCounter = (sessionCounter + 1) >>> 0 || 1;
      session = { id: sessionCounter, location: meta.location, acknowledged: false, openedAt: now() }; lastTrial = 0; lastFrameAt = now();
      model.setMetadata({ ...meta, session: session.id }, capability, manifest);
      try { await options.send('X'); await options.send('Q'); await options.send(Calibration.command('i')); await options.send(Calibration.command('c', session.id, meta.cpr, meta.travelTenths, meta.encoderSign)); }
      catch (error) { session = null; throw error; }
      show('已提交校准会话；板端确认前不能启动测试。元信息与行程原点已冻结。');
    }));
    $('cal-end').addEventListener('click', () => action(() => stopSession('已退出校准并停机；原平衡控制入口恢复。')));
    $('cal-emergency').addEventListener('click', () => stopSession('已请求立即停机，当前试次作废。').catch(() => {}));
    $('cal-precheck').addEventListener('click', () => { if (canPulse(0)) return action(() => pulse(0)); });
    $('cal-pulse').addEventListener('click', () => { const profile = Number($('cal-profile').value); if (canPulse(profile)) return action(() => pulse(profile)); });
    $('cal-queryResult').addEventListener('click', () => action(async () => {
      const trial = selectedTrial || model.trials[model.trials.length - 1];
      if (!trial) throw new Error('没有可查询的试次');
      if (pendingTrial) throw new Error('试次尚在等待结束；不能把进行中的状态当成缓存结果');
      await options.send(Calibration.command('i')); await options.send(Calibration.command('g', trial.session, trial.id)); show('已查询板端缓存结果；查询不会重启电机。');
    }));
    $('cal-next').addEventListener('click', () => {
      const step = Number($('cal-step').value);
      const next = Number($('cal-duty').value) + step;
      if (![1, 0.2, -0.2, -1].includes(step) || next < 0 || next > 20) { show('已到扫描范围边界。至多 20%；不要继续增加。', true); return; }
      $('cal-duty').value = (Math.round(next * 5) / 5).toFixed(1); update(); show('候选档已更新；须自行点击预检/测试，电机不会自动启动。');
    });
    ['cal-duty','cal-direction','cal-profile','cal-step','cal-signal'].forEach(id => $(id).addEventListener('change', () => { dirty = true; update(); }));
    $('cal-reviewTrial').addEventListener('change', () => { const [sid,id] = $('cal-reviewTrial').value.split(':').map(Number); selectedTrial = model.findTrial(sid,id); fillReview(); update(); });
    $('cal-reviewSave').addEventListener('click', () => {
      const t = selectedTrial;
      if (!t?.result) return;
      try {
        const comment = $('cal-comment').value.trim();
        t.comment = comment;
        if (comment) t.invalidReason ||= comment;
        if (t.profile === 0) {
          if ($('cal-current').value.trim() === '' || $('cal-vmMin').value.trim() === '') throw new Error('预检需填写实测电流峰值及 VM 最低值');
          t.electrical = { currentPeakA: Number($('cal-current').value), vmMinV: Number($('cal-vmMin').value), recordedAt: new Date(now()).toISOString() };
          if (!Calibration.electricalCheck(t.electrical, t.metadata)) { t.invalidReason ||= '电气预检异常'; void stopSession('电气预检未通过，已请求停机并关闭会话。请排查电流或供电压降后重新建立会话。').catch(() => {}); update(); return; }
          show('预检记录已保存；该会话、该指令方向及 PWM 可进入长测试。');
        } else {
          if (!['yes','no'].includes($('cal-motion').value)) throw new Error('请选择转臂是否出现实际动作');
          t.confirmed = $('cal-motion').value === 'yes';
          if ((t.confirmed && [3,4].includes(t.result.result)) || (!t.confirmed && [1,2].includes(t.result.result))) t.invalidReason ||= '板端判据与实际转臂运动不一致，检查编码器轴位置和背隙';
          if ($('cal-current').value.trim() !== '' && $('cal-vmMin').value.trim() !== '') {
            t.electrical = { currentPeakA: Number($('cal-current').value), vmMinV: Number($('cal-vmMin').value) };
            if (!Calibration.electricalCheck(t.electrical, t.metadata)) t.invalidReason ||= '长测试电流或供电压降异常';
          }
          show(`人工记录已保存：${model.classify(t)}。每个边界档位需 5 次有效重复。`);
        }
      } catch (error) { show(error.message, true); }
      update();
    });
    $('cal-raw').addEventListener('click', () => download(model.rawCsv(), 'furuta-calibration-raw.csv', 'text/csv;charset=utf-8'));
    $('cal-summary').addEventListener('click', () => download(model.summaryCsv(), 'furuta-calibration-summary.csv', 'text/csv;charset=utf-8'));
    $('cal-report').addEventListener('click', () => download(model.report(), 'furuta-calibration-report.html', 'text/html;charset=utf-8'));
    $('cal-clear').addEventListener('click', () => { if (session) return; model.clear(); selectedTrial = null; updateReviewOptions(); dirty = true; update(); show('已清空校准数据；普通角度采集数据保留。'); });
    $('cal-manifest').addEventListener('change', async () => {
      const file = $('cal-manifest').files?.[0]; if (!file || session) return;
      try { if (file.size > 1024 * 1024) throw new Error('构建清单过大'); manifest = JSON.parse(await file.text()); if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)) throw new Error('构建清单必须为 JSON 对象'); update(); }
      catch (error) { show(`清单载入失败：${error.message}`, true); }
      finally { $('cal-manifest').value = ''; }
    });
    function draw() {
      const canvas = $('cal-chart'), ctx = canvas.getContext('2d');
      const width = canvas.clientWidth || 800, height = 260, ratio = window.devicePixelRatio || 1;
      canvas.width = Math.round(width * ratio); canvas.height = Math.round(height * ratio); ctx.setTransform(ratio,0,0,ratio,0,0); ctx.clearRect(0,0,width,height);
      const samples = model.samples.slice(-2000);
      if (!samples.length) { ctx.fillStyle = '#96a5bc'; ctx.font = '14px sans-serif'; ctx.fillText('等待校准 M 帧；使用独立 10 ms 板端时间',45,120); return; }
      let time = 0, prev = null;
      const points = samples.map(p => { const delta = prev && prev.session === p.session ? Calibration.elapsed(p.ms,prev.ms) : 10; time += delta; const velocity = prev && !p.gap && prev.session === p.session && delta > 0 ? (p.position-prev.position)*1000/delta : null; prev=p; return { ...p,time,velocity }; });
      const kind = $('cal-signal').value;
      const readers = kind === 'position' ? [p => p.position] : kind === 'velocity' ? [p => p.velocity] : [p => p.requested*100/(capability?.pwmMax||2500),p => p.actual*100/(capability?.pwmMax||2500)];
      let min=0,max=0; for (const p of points) for (const read of readers) { const n=read(p); if(n!==null){min=Math.min(min,n);max=Math.max(max,n);} }
      const pad=Math.max(1,(max-min)*.1);min-=pad;max+=pad;
      const px=t=>55+(t-points[0].time)/Math.max(1,time-points[0].time)*(width-75), py=n=>225-(n-min)/(max-min)*205;
      ctx.font='11px Consolas,monospace';
      for(let i=0;i<5;i++){const n=min+(max-min)*i/4;ctx.strokeStyle='#2b3444';ctx.beginPath();ctx.moveTo(55,py(n));ctx.lineTo(width-20,py(n));ctx.stroke();ctx.fillStyle='#96a5bc';ctx.fillText(n.toFixed(1),2,py(n));}
      readers.forEach((read,index)=>{ctx.strokeStyle=['#fbbf24','#60a5fa'][index];ctx.beginPath();let previous=null;for(const p of points){const n=read(p);if(n===null){previous=null;continue;}if(!previous||p.gap||p.session!==previous.session)ctx.moveTo(px(p.time),py(n));else ctx.lineTo(px(p.time),py(n));previous=p;}ctx.stroke();});
      ctx.fillStyle='#96a5bc';ctx.fillText('0 s',55,250);ctx.fillText(`${((time-points[0].time)/1000).toFixed(3)} s`,width-100,250);
    }
    async function tick() {
      if (session && options.isConnected()) {
        const current = session;
        try { await options.send(Calibration.command('h', current.id)); }
        catch (_) { if (session === current) { session = null; invalidatePending('心跳发送失败'); show('心跳发送失败。当前会话作废；板端将在 200 ms 超时停机。',true); } }
        if (session === current && !current.acknowledged && now()-current.openedAt > 1500) { await stopSession('板端未确认会话，已停机').catch(() => {}); }
        else if (session === current && current.acknowledged && now()-lastFrameAt > 250) { await stopSession('校准数据中断超过 250 ms，当前试次无效').catch(() => {}); }
      }
      if (pendingTrial && options.isConnected() && model.lastSample?.session === pendingTrial.session && model.lastSample?.trial === pendingTrial.id && !model.lastSample.active && now()-pendingTrial.sentAt > (pendingTrial.profile===2?850:350) && now()-lastQueryAt > 500) {
        const t=pendingTrial;lastQueryAt=now();
        try { await options.send(Calibration.command('g',t.session,t.id)); } catch (_) {}
        if(now()-t.sentAt > 2000){invalidatePending('未收到板端缓存结果');show('试次结果缺失，已标记无效；可手动查询结果。',true);}
      }
      update();
    }
    (options.setInterval || setInterval)(() => { void tick(); }, 50);
    if (typeof fetch === 'function') fetch('calibration-manifest.json', { cache: 'no-store' }).then(r => r.ok ? r.json() : null).then(value => { if (value && typeof value === 'object' && !Array.isArray(value)) { manifest=value;update(); } }).catch(() => {});
    update();
    return {
      model, decoder, feed: text => decoder.feed(text),
      get locked() { return !!session; }, get active() { return !!pendingTrial; },
      async connected() { capability=null;session=null;decoder.pending='';await options.send(Calibration.command('i'));show('正在读取板端能力；收到兼容 I 帧前禁止校准。');update(); },
      disconnected() { session=null;capability=null;invalidatePending('串口断开');show('串口已断开；保留实测数据，可导出报告。');update(); },
      async beforeDisconnect() { if(session||pendingTrial) await stopSession('断开前已请求停机；当前试次作废'); },
      update, tick, canPulse, currentCounts, pulse, onFrame, metadata,
      get status() { return { session, pendingTrial, capability, manifest, diagnostic }; }
    };
  }
  root.CalibrationApp = { create };
})(typeof globalThis !== 'undefined' ? globalThis : this);

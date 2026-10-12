(function (root) {
  'use strict';
  const PERIOD_MS = 5;
  const PWM_MAX = 2500; // Current 50 MHz / 20 kHz firmware, signed duty counts.
  const ANGLE_ADC_SPAN = 4095, ANGLE_RANGE_DEG = 333;
  const COUNTS_PER_REV = 408;
  const offsetDegrees = value => value == null ? null : value * ANGLE_RANGE_DEG / ANGLE_ADC_SPAN;
  const positionKeys = ['armPosition', 'positionTarget', 'positionError', 'targetAngleOffsetAdc'];
  const CSV_HEADER = 'time_ms,sequence,angle_deviation_deg,session,pwm_requested_counts,pwm_actual_counts,arm_position_counts,position_target_counts,position_error_counts,angle_target_offset_adc';
  const pwmPercent = value => value == null ? null : value * 100 / PWM_MAX;
  class LineDecoder {
    constructor(onFrame) { this.onFrame = onFrame; this.pending = ''; this.invalid = 0; }
    feed(text) {
      this.pending += text;
      let end;
      while ((end = this.pending.indexOf('\n')) >= 0) {
        const line = this.pending.slice(0, end).replace(/\r$/, '');
        this.pending = this.pending.slice(end + 1);
        // Ignore command echoes before a complete telemetry line.
        const start = line.indexOf('T,');
        if (start < 0) continue;
        const match = /^T,([0-9a-fA-F]{8}),([+-]\d{3}\.\d)(?:,([+-]\d{4}),([+-]\d{4})(?:,([+-]\d{4}),([+-]\d{4}),([+-]\d{4}),([+-]\d{4}))?)?$/.exec(line.slice(start));
        if (!match) { this.invalid++; continue; }
        const requestedPwm = match[3] === undefined ? null : Number(match[3]);
        const actualPwm = match[4] === undefined ? null : Number(match[4]);
        if ([requestedPwm, actualPwm].some(v => v !== null && Math.abs(v) > PWM_MAX)) { this.invalid++; continue; }
        const frame = { sequence: parseInt(match[1], 16), angle: Number(match[2]), requestedPwm, actualPwm };
        positionKeys.forEach((key, index) => frame[key] = match[5 + index] === undefined ? null : Number(match[5 + index]) / (index === 3 ? 10 : 1));
        this.onFrame(frame);
      }
      if (this.pending.length > 8192) { this.pending = ''; this.invalid++; }
    }
  }
  class Recording {
    constructor(capacity = 120000) {
      this.capacity = capacity; this.clear();
    }
    clear() {
      this.buffer = new Array(this.capacity); this.length = 0; this.head = 0;
      this.lastSequence = null; this.time = 0; this.session = 0;
      this.missing = 0; this.total = 0; this.sum = 0; this.sumSquares = 0;
    }
    add(frame) {
      let gap = false;
      if (this.lastSequence !== null) {
        const delta = (frame.sequence - this.lastSequence) >>> 0;
        if (delta === 0) return false;
        if (delta >= 0x80000000) { this.session++; this.time += PERIOD_MS; gap = true; }
        else { this.time += delta * PERIOD_MS; this.missing += delta - 1; gap = delta > 1; }
      }
      this.lastSequence = frame.sequence;
      const point = { time: this.time, sequence: frame.sequence, angle: frame.angle, requestedPwm: frame.requestedPwm ?? null, actualPwm: frame.actualPwm ?? null, session: this.session, gap };
      positionKeys.forEach(key => point[key] = frame[key] ?? null);
      this.push(point);
      return true;
    }
    push(point) {
      if (this.length === this.capacity) {
        const old = this.buffer[this.head]; this.sum -= old.angle; this.sumSquares -= old.angle ** 2;
      } else this.length++;
      this.buffer[this.head] = point; this.head = (this.head + 1) % this.capacity;
      this.total++; this.sum += point.angle; this.sumSquares += point.angle ** 2;
    }
    get(index) {
      return this.buffer[(this.head - this.length + index + this.capacity) % this.capacity];
    }
    latest() { return this.length ? this.get(this.length - 1) : null; }
    values() { return Array.from({ length: this.length }, (_, index) => this.get(index)); }
    csv() {
      return '\ufeff' + CSV_HEADER + '\r\n' + this.values().map(p =>
        [p.time, p.sequence, p.angle.toFixed(1), p.session, p.requestedPwm ?? '', p.actualPwm ?? '',
          ...positionKeys.map(key => p[key] ?? '')].join(',')).join('\r\n') + '\r\n';
    }
  }
  function importText(text) {
    const lines = text.replace(/^\ufeff/, '').trim().split(/\r?\n/);
    const oldHeader = 'time_ms,sequence,angle_deviation_deg,session';
    const headers = [oldHeader, oldHeader + ',pwm_requested_counts,pwm_actual_counts', CSV_HEADER];
    const columnCount = [4, 6, 10][headers.indexOf(lines[0])];
    if (columnCount) {
      const points = lines.slice(1).filter(Boolean).map((line, index) => {
        const fields = line.split(',');
        if (fields.length !== columnCount || fields.slice(0, 4).some(x => x.trim() === '')) throw new Error(`第 ${index + 2} 行 CSV 格式不正确`);
        const [time, sequence, angle, session] = fields.map(Number);
        if (![time, sequence, angle, session].every(Number.isFinite) || time < 0 ||
            !Number.isInteger(sequence) || sequence < 0 || sequence > 0xffffffff ||
            !Number.isInteger(session) || session < 0 || Math.abs(angle) > 999.9)
          throw new Error(`第 ${index + 2} 行数值不正确`);
        const optionalNumber = i => i >= columnCount || fields[i].trim() === '' ? null : Number(fields[i]);
        const requestedPwm = optionalNumber(4), actualPwm = optionalNumber(5);
        if ((requestedPwm === null) !== (actualPwm === null) ||
            [requestedPwm, actualPwm].some(v => v !== null && (!Number.isInteger(v) || Math.abs(v) > PWM_MAX)))
          throw new Error(`第 ${index + 2} 行 PWM 数值不正确`);
        const metadata = [6, 7, 8, 9].map(optionalNumber);
        const present = metadata.filter(v => v !== null).length;
        if (present !== 0 && present !== 4 || metadata.some((v, i) => v !== null &&
            (!Number.isFinite(v) || Math.abs(v) > (i === 3 ? 999.9 : 9999) || i < 3 && !Number.isInteger(v))))
          throw new Error(`第 ${index + 2} 行位置数值不正确`);
        const point = { time, sequence, angle, session, requestedPwm, actualPwm, gap: false };
        positionKeys.forEach((key, i) => point[key] = metadata[i]);
        return point;
      });
      points.forEach((point, index) => {
        if (!index) return;
        const previous = points[index - 1];
        if (point.time <= previous.time) throw new Error('CSV 时间必须递增');
        point.gap = point.session !== previous.session || point.time - previous.time > PERIOD_MS;
      });
      if (!points.length) throw new Error('文件中没有角度数据');
      return points;
    }
    const recording = new Recording();
    const decoder = new LineDecoder(frame => recording.add(frame));
    decoder.feed(text + '\n');
    if (!recording.length) throw new Error('未找到数据，请导入网页导出的 CSV 或 T,序号,角度 串口记录');
    return recording.values();
  }
  const api = { PERIOD_MS, PWM_MAX, COUNTS_PER_REV, ANGLE_ADC_SPAN, ANGLE_RANGE_DEG, pwmPercent, offsetDegrees, CSV_HEADER, LineDecoder, Recording, importText };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.Telemetry = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);

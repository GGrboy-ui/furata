from pathlib import Path
import csv, json, sys
import numpy as np

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'plot_deps'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager

source = Path(r'D:\Backup\Downloads\furuta-angle-2026-10-12T11-25-22-944Z.csv')
with source.open(encoding='utf-8-sig', newline='') as handle:
    rows = list(csv.DictReader(handle))
keys = list(rows[0])
data = np.array([[float(row[key]) for key in keys] for row in rows])
t, seq, angle, session, req, actual = data.T
t /= 1000
assert np.isfinite(data).all()
assert np.all(np.diff(t) > 0)
assert np.unique(session).tolist() == [0]
assert np.allclose(np.diff(seq), np.diff(t) * 200)
window = (t >= 18.8) & (t <= 26.5)
kp, kd, ts = 23661/65536, 23214/65536, 0.005
codes_per_degree = 4095/333
slope, intercept = np.polyfit(angle[window], req[window]/25, 1)
sat = np.abs(req) == 2500
summary = {
    'source': str(source), 'samples': len(rows), 'duration_s': float(t[-1]),
    'missing_sequence_slots': int(np.sum(np.diff(seq)-1)),
    'first_motor_request_s': float(t[np.flatnonzero(req)[0]]),
    'last_motor_request_s': float(t[np.flatnonzero(req)[-1]]),
    'analysis_interval_s': [18.8, 26.5],
    'exact_pwm_tracking_fraction': float(np.mean(req[window] == actual[window])),
    'pwm_tracking_rms_counts': float(np.sqrt(np.mean((req[window]-actual[window])**2))),
    'pwm_sign_mismatches': int(np.sum(np.sign(req[window]) != np.sign(actual[window]))),
    'fitted_request_percent_per_degree': float(slope), 'fit_intercept_percent': float(intercept),
    'coded_kp_percent_per_degree': kp*codes_per_degree,
    'coded_kd_percent_per_deg_s': kd*codes_per_degree*ts,
    'coded_d_over_p_time_s': kd/kp*ts,
    'first_requested_saturation_s': float(t[np.flatnonzero(sat)[0]]),
    'requested_saturation_samples': int(sat.sum()),
    'milestones': []
}
for target in [10.735,18.8,19,24,26.3,26.5,26.8,27.0,27.08,27.1,27.18,27.185,27.2,27.25,27.275]:
    i = int(np.argmin(abs(t-target)))
    summary['milestones'].append({'time_s':float(t[i]),'angle_deg':float(angle[i]),
                                 'requested_percent':float(req[i]/25),'actual_percent':float(actual[i]/25)})
(ROOT/'analysis_summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(summary, ensure_ascii=False, indent=2))

font_manager.fontManager.addfont(r'C:\Windows\Fonts\msyh.ttc')
plt.rcParams.update({'font.family':'Microsoft YaHei','axes.unicode_minus':False,
                     'font.size':10,'axes.spines.top':False,'axes.spines.right':False})
fig, axes = plt.subplots(2,2,figsize=(13.2,7.2),gridspec_kw={'width_ratios':[1.5,1]},layout='constrained')
for col, limits in enumerate([(10.5,27.3),(26.6,27.22)]):
    m = (t>=limits[0]) & (t<=limits[1])
    axes[0,col].plot(t[m],angle[m],color='#2457a7',lw=1.65)
    axes[1,col].plot(t[m],req[m]/25,color='#dc7824',lw=1.4,label='要求 PWM')
    axes[1,col].plot(t[m],actual[m]/25,color='#19816c',lw=1.1,label='实际 PWM')
    for row in range(2):
        axes[row,col].set_xlim(limits)
        axes[row,col].axhline(0,color='#82909b',lw=.6)
        axes[row,col].grid(alpha=.19)
    axes[1,col].set_xlabel('采集时间 / s')
    axes[1,col].legend(loc='upper left',frameon=False)
axes[0,0].set_ylim(-18,5)
axes[0,1].set_ylim(-42,32)
axes[1,0].set_ylim(-110,110)
axes[1,1].set_ylim(-110,110)
axes[0,0].set_title('先单向漂移，末期快速失稳',loc='left',fontsize=12)
axes[0,1].set_title('失稳末期：饱和、反向与关断',loc='left',fontsize=12)
axes[0,0].set_ylabel('平均角度偏差 / °')
axes[0,1].set_ylabel('平均角度偏差 / °')
axes[1,0].set_ylabel('有符号占空比 / %')
axes[1,1].set_ylabel('有符号占空比 / %')
axes[0,0].annotate('19 s：−2.4°',xy=(19,-2.4),xytext=(17.3,1.8),arrowprops={'arrowstyle':'-','color':'#555'})
axes[0,0].annotate('26.5 s：−6.5°',xy=(26.5,-6.5),xytext=(21.4,-12),arrowprops={'arrowstyle':'-','color':'#555'})
axes[1,0].text(18.95,66,'18.8–26.5 s：99.0% 采样点\n实际 PWM 与要求值完全相同',fontsize=10)
for row in range(2):
    axes[row,1].axvline(27.185,color='#a02e40',lw=1,ls='--')
axes[0,1].text(27.181,-38,'PWM 归零',ha='right',va='bottom',color='#a02e40')
fig.suptitle('K3 平衡测试：角度与 PWM 数据诊断',fontsize=15,x=.03,ha='left')
fig.savefig(ROOT/'angle_pwm_diagnosis.png',dpi=180)
fig.savefig(ROOT/'angle_pwm_diagnosis.svg')

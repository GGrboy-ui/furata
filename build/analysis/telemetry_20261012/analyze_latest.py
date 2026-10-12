from pathlib import Path
import csv, json, re, sys, hashlib
from datetime import datetime
import numpy as np

BASE=Path(__file__).resolve().parent
OUT=BASE/'run_113621'
OUT.mkdir(exist_ok=True)
sys.path.insert(0,str(BASE/'plot_deps'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager

PROJECT=Path(r'G:\furata-git\furata')
INPUT=Path(r'D:\Backup\Downloads\furuta-angle-2026-10-12T11-36-21-614Z.csv')
def read_csv(path):
    with path.open(encoding='utf-8-sig',newline='') as h:
        rows=list(csv.DictReader(h))
    return np.array([[float(row[k]) for k in rows[0]] for row in rows])
data=read_csv(INPUT)
t,seq,angle,session,req,actual=data.T
t=t/1000
assert np.isfinite(data).all() and np.all(np.diff(t)>0)
assert np.all(np.diff(seq)==1) and np.allclose(np.diff(t),.005)
params={}
for filename in ['src/rtl/control_core.v','src/board/acg720_top.v','src/rtl/pid_fixed.v','src/rtl/pwm_motor.v']:
    content=(PROJECT/filename).read_bytes()
    (OUT/Path(filename).name).write_bytes(content)
    params[filename]={'sha256':hashlib.sha256(content).hexdigest(),
                      'mtime':datetime.fromtimestamp((PROJECT/filename).stat().st_mtime).isoformat()}
core=(OUT/'control_core.v').read_text()
top=(OUT/'acg720_top.v').read_text()
values={name:int(re.search(r'\b'+name+r'\s*=\s*(\d+)',core).group(1))
        for name in ['ANGLE_KP','ANGLE_KI','ANGLE_KD','POSITION_KP','POSITION_KI','POSITION_KD','ANGLE_MS','START_PERCENT']}
values.update({name:int(re.search(r'\b'+name+r'\s*=\s*(\d+)',top).group(1))
               for name in ['CENTER','PULSE_MS','MOTOR_INVERT','PWM_HZ']})
params['effective_parameters']=values
params['sample_period_s']=.005
params['kp_percent_per_deg']=values['ANGLE_KP']/65536*4095/333
params['kd_continuous_percent_per_deg_s']=values['ANGLE_KD']/65536*4095/333*.005
params['d_over_p_s']=values['ANGLE_KD']/values['ANGLE_KP']*.005
(OUT/'parameter_snapshot.json').write_text(json.dumps(params,ensure_ascii=False,indent=2),encoding='utf-8')
nz=np.flatnonzero(req)
summary={'source':str(INPUT),'samples':len(data),'duration_s':float(t[-1]),'missing_samples':0,
         'request_start_s':float(t[nz[0]]),'last_request_s':float(t[nz[-1]]),
         'drive_zero_s':float(t[nz[-1]+1]),'release_s_user_approx':4.5,'intervals':[],'milestones':[]}
for s,e in [(2.2,4.5),(5,7.4),(7.5,7.635),(7.635,7.93)]:
    m=(t>=s)&(t<=e)
    summary['intervals'].append({'start_s':s,'end_s':e,'samples':int(m.sum()),
        'angle_mean_deg':float(angle[m].mean()),'angle_std_deg':float(angle[m].std()),
        'requested_mean_percent':float(req[m].mean()/25),'requested_std_percent':float(req[m].std()/25),
        'requested_min_percent':float(req[m].min()/25),'requested_max_percent':float(req[m].max()/25),
        'actual_mean_percent':float(actual[m].mean()/25),
        'exact_tracking_fraction':float(np.mean(req[m]==actual[m])),
        'tracking_rms_percent_points':float(np.sqrt(np.mean((req[m]-actual[m])**2))/25)})
for target in [2.08,4.5,5,7.5,7.635,7.64,7.76,7.78,7.84,7.88,7.92,7.93,7.935,7.94]:
    i=int(np.argmin(abs(t-target)))
    summary['milestones'].append({'time_s':float(t[i]),'angle_deg':float(angle[i]),
        'requested_percent':float(req[i]/25),'actual_percent':float(actual[i]/25)})
(OUT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'parameters':values,'summary':summary},ensure_ascii=False,indent=2))

font_manager.fontManager.addfont(r'C:\Windows\Fonts\msyh.ttc')
plt.rcParams.update({'font.family':'Microsoft YaHei','axes.unicode_minus':False,'font.size':10,
                     'axes.spines.top':False,'axes.spines.right':False})
fig,axes=plt.subplots(2,2,figsize=(13.2,7.2),layout='constrained',gridspec_kw={'width_ratios':[1.4,1]})
for col,limits in enumerate([(0,7.96),(7.45,7.96)]):
    m=(t>=limits[0])&(t<=limits[1])
    axes[0,col].plot(t[m],angle[m],color='#2457a7',lw=1.6)
    axes[1,col].plot(t[m],req[m]/25,color='#df7b25',lw=1.1,label='要求 PWM')
    axes[1,col].plot(t[m],actual[m]/25,color='#19816c',lw=1.1,label='实际 PWM')
    for row in range(2):
        axes[row,col].set_xlim(limits)
        axes[row,col].grid(alpha=.18)
        axes[row,col].axhline(0,color='#83919d',lw=.6)
    axes[0,col].set_ylabel('平均角度偏差 / °')
    axes[1,col].set_ylabel('有符号占空比 / %')
    axes[1,col].set_xlabel('采集时间 / s')
    axes[1,col].legend(loc='upper left',frameon=False)
axes[0,0].set_ylim(-5,3)
axes[1,0].set_ylim(-20,20)
axes[0,1].set_ylim(-33,48)
axes[1,1].set_ylim(-110,110)
axes[0,0].set_title('扶杆、松手及短暂的小偏角阶段',loc='left',fontsize=12)
axes[0,1].set_title('末期振幅增长与执行偏差',loc='left',fontsize=12)
for row in range(2):
    axes[row,0].axvline(4.5,color='#666',lw=1,ls='--')
    axes[row,1].axvline(7.935,color='#a02e40',lw=1,ls='--')
axes[0,0].text(4.6,2.2,'约 4.5 s 松手（用户确认）')
axes[0,0].text(5.1,.6,'5–7.4 s：约 −0.5°')
axes[1,0].text(2.35,-17,'扶杆阶段平均 −4.62%')
axes[1,0].text(5.15,15,'松手后平均 +2.01%\n仍持续向同一方向驱动')
for x,y,tx,ty,label in [(7.635,-4.1,7.48,-18,'−4.1°'),(7.76,12.1,7.67,31,'+12.1°'),(7.84,-27.1,7.8,-32,'−27.1°')]:
    axes[0,1].annotate(label,xy=(x,y),xytext=(tx,ty),arrowprops={'arrowstyle':'-','color':'#777'})
fig.suptitle('最新 K3 记录：短暂小偏角之后快速发散',fontsize=15,x=.03,ha='left')
fig.savefig(OUT/'latest_diagnosis.png',dpi=180)
fig.savefig(OUT/'latest_diagnosis.svg')

"""Publish matching TRJ1 sources/bitstream only after regression, web, HTTP and STA pass."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
from urllib.request import urlopen
from urllib.error import HTTPError
import hashlib,json,re,shutil,zipfile

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build/trajectory_20261030'
CANDIDATE=BUILD/'candidate'
VALIDATION=BUILD/'validation'

def require(condition,message):
    if not condition:raise SystemExit('RELEASE BLOCKED: '+message)

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def copy(source,target):
    if target.exists():target.chmod(0o644)
    shutil.copy2(source,target)
    target.chmod(0o644)

def main():
    sources=sorted(p for p in ROOT.joinpath('src').rglob('*') if p.is_file())+[ROOT/'furata.gprj']
    for p in sources:
        rel=p.relative_to(ROOT)
        require((CANDIDATE/rel).exists() and sha(p)==sha(CANDIDATE/rel),f'candidate mismatch: {rel}')
        if rel.parts[0]=='src':
            require((VALIDATION/rel).exists() and sha(p)==sha(VALIDATION/rel),f'validation mismatch: {rel}')
    report_file=VALIDATION/'build/oss/regression_report.txt'
    report=report_file.read_text(encoding='utf-8-sig')
    tests=sorted(ROOT.joinpath('sim').glob('tb_*.v'))
    requested=re.search(r'^requested=(.*)$',report,re.M).group(1).split(',')
    passed=int(re.search(r'^passed=(\d+)$',report,re.M).group(1))
    require(sorted(requested)==[p.stem for p in tests] and passed==len(tests),'incomplete RTL regression')
    require(re.search(r'^failed=\s*$',report,re.M) and re.search(r'^missing=\s*$',report,re.M),'RTL failures')
    for p in tests:
        reduced=re.sub(r'\$dumpvars\(0,(\s*tb_\w+)\)',r'$dumpvars(1,\1)',p.read_text(encoding='utf-8'))
        require(reduced==(VALIDATION/'sim'/p.name).read_text(encoding='utf-8'),f'test stimulus mismatch: {p.name}')
    require(report_file.stat().st_mtime>=max(p.stat().st_mtime for p in sources),'regression predates sources')
    web=json.loads((BUILD/'web-checks.json').read_text(encoding='utf-8'))
    require(web['passed']==len(list(ROOT.joinpath('web').glob('test-*.cjs'))) and web['syntaxPassed'],'incomplete web checks')
    for rel,digest in web['files'].items():require(sha(ROOT/rel)==digest,f'web checks predate change: {rel}')
    browser=json.loads((BUILD/'browser-checks.json').read_text(encoding='utf-8'))
    require(browser['passed'] and not browser['errors'],'browser failure')
    timing_file=CANDIDATE/'impl/pnr/furata_tr_content.html'
    timing=timing_file.read_text(encoding='utf-8',errors='replace')
    setup=int(re.search(r'Setup Violated Endpoints</td>\s*<td>(\d+)',timing).group(1))
    hold=int(re.search(r'Hold Violated Endpoints</td>\s*<td>(\d+)',timing).group(1))
    fmax=float(re.search(r'50\.000\(MHz\)</td>\s*<td[^>]*>([\d.]+)\(MHz\)',timing).group(1))
    slacks=[float(s) for s in re.findall(r'^SETUP\s*\n([+-]?[\d.]+)',(CANDIDATE/'impl/pnr/furata.timing_paths').read_text(),re.M)]
    require(setup==0 and hold==0 and fmax>=50 and slacks and min(slacks)>=0,'50 MHz STA failure')
    bitstream=CANDIDATE/'impl/pnr/furata.fs'
    require(bitstream.exists() and bitstream.stat().st_mtime>=max(p.stat().st_mtime for p in sources),'stale/missing bitstream')
    require(timing_file.stat().st_mtime>=max(p.stat().st_mtime for p in sources),'stale timing report')
    for name in ['index.html','app.js','arm-app.js','trajectory-core.js','trajectory-app.js','telemetry-core.js','style.css']:
        require(hashlib.sha256(urlopen('http://localhost:8766/'+name).read()).hexdigest()==sha(ROOT/'web'/name),f'8766 wrong content: {name}')
    for name in ['friction-app.js','friction-core.js']:
        try:urlopen('http://localhost:8766/'+name)
        except HTTPError as error:require(error.code==404,f'unexpected HTTP status for removed {name}')
        else:require(False,f'removed resource still served: {name}')
    text='\n'.join(p.read_text(encoding='utf-8') for p in ROOT.joinpath('src').rglob('*.v'))
    require('friction_' not in text and 'FRC1' not in text,'measurement RTL remains active')
    release=BUILD/'release';release.mkdir(parents=True,exist_ok=True)
    copy(bitstream,release/'furata.trajectory.fs')
    manifest={
        'protocol':'TRJ1','createdAt':datetime.now(timezone(timedelta(hours=8))).isoformat(),
        'sourceFiles':{p.relative_to(ROOT).as_posix():sha(p) for p in sources},
        'webFiles':web['files'],'rtlPassed':passed,'rtlTotal':len(tests),'webPassed':web['passed'],
        'bitstreamSha256':sha(release/'furata.trajectory.fs'),
        'timing':{'constraintMHz':50,'fmaxMHz':fmax,'setupViolations':setup,'holdViolations':hold,'worstSetupSlackNs':min(slacks)},
        'positionPeriod':{'defaultMs':50,'minMs':1,'maxMs':1000,'persistAcrossStop':True,'powerResetToDefault':True,'rescalePid':False},
        'modes':['quintic','enveloped-sine','waypoints','seven-segment-s-velocity'],
        'httpVerified':'http://localhost:8766/','automaticallyProgrammed':False,'hardwareMeasured':False,
        'notes':['STA passes at the specified corner; setup margin is small (see numerical slack).',
                 'Validation copy changes VCD dump depth only; all stimulus/assertions match.',
                 'Browser WebSerial interaction was tested with a private headless mock, not physical hardware.',
                 'Verilator lint was not run; Icarus regression, JavaScript syntax/tests, HTTP and browser checks passed.']}
    validation=f'''# 发布验证：TRJ1 四种轨迹与位置环周期

日期：{manifest['createdAt']}。实际工程：`G:/furata-git/furata`。

- RTL：{passed}/{len(tests)} 全量测试通过。包含四种曲线与导数金标准、正反向/行程/速度校验、实际到位确认、物理 UART 混合帧、残缺/超时命令隔离、X/K4、位置环周期边界和 PID 历史保留。
- 位置环：1/1000/50 ms 的实际 PID 更新次数专项测试通过；5/20 ms 的板级切换、K4 保留、系统复位恢复也通过。
- 网页：{web['passed']}/{web['passed']} 测试及全部 JavaScript 语法通过；Chrome 桌面/420 px 窄屏、四模式表单、周期应用回读、模拟串口互锁/停机/断开检查通过，无页面脚本错误。
- HTTP：8766 的当前 HTML/JS/CSS 与实际源码哈希一致，已移除的测量脚本返回 404。
- 时序：50 MHz 约束，Fmax **{fmax:.3f} MHz**，最差建立余量 **{min(slacks):.3f} ns**，建立/保持违例 **{setup}/{hold}**。余量较小；后续任何 RTL 或实现选项变动均须重新检查，不沿用本次结论。
- 编译与回归快照的 RTL/约束逐文件 SHA-256 与主工程一致；回归副本仅缩小 VCD 深度，不修改刺激和断言。未运行 Verilator lint。
- 未自动烧录，未验证实物的摆杆最大偏角、位置/速度跟踪、持续平衡与电机负载能力。浏览器模拟串口结果不作为实机验证。

## 文件

- `furata.trajectory.fs`：匹配当前源代码的下载固件。
- `furata.trajectory.source.zip`：完整源码、网页、仿真、文档和编译/发布脚本。
- `manifest.json`：源码、网页及固件哈希，测试数和时序结果。
- `regression_report.txt`、`full-regression.log`、`web-checks.*`、`browser-checks.json`、时序报告与路径文件：验证依据。

固件 SHA-256：`{manifest['bitstreamSha256']}`。

下载后刷新 <http://localhost:8766/>，确认识别 TRJ1。位置环周期默认 50 ms，可手动设置 1～1000 ms；平衡空闲时在原周期更新边界生效，K4 后保留，上电恢复默认。KI/KD 和积分衰减不自动换算。
高云 GUI 若已打开工程，关闭并重新打开 `furata.gprj` 以刷新新增模块。编译时保留数码管 M18 的 SSPI GPIO 选项；发布构建由 `run_gowin.ps1` 设置。
'''
    (release/'VALIDATION.md').write_text(validation,encoding='utf-8')
    record=ROOT/'doc/test-record.md';old=record.read_text(encoding='utf-8');heading='## 2026-10-30：TRJ1四种轨迹与位置环周期'
    if heading in old:old=old[:old.index(heading)].rstrip()+'\n'
    record.write_text(old+'\n'+heading+'\n\n'+f'新增四种 FPGA 参考轨迹与 1～1000 ms 位置环周期调节，移除当前启动补偿测量功能。默认 50 ms，平衡空闲时在旧周期更新完成后切换，PID 历史保留，K4 保留周期，上电恢复默认；离散参数不自动换算。\n\n全量 RTL {passed}/{len(tests)}，网页 {web["passed"]}/{web["passed"]} 与 Chrome/HTTP 检查通过。50 MHz 下 Fmax={fmax:.3f} MHz，最差建立余量={min(slacks):.3f} ns，建立/保持违例={setup}/{hold}，余量较小。主工程、独立编译及回归 RTL 哈希匹配。未烧录或机械验证。发布见 `build/trajectory_20261030/release/`，详细参数/协议见 [轨迹说明](trajectory-control.md)，数值与哈希见发布 `VALIDATION.md`/`manifest.json`。\n',encoding='utf-8')
    for p in [timing_file,CANDIDATE/'impl/pnr/furata.timing_paths',report_file,BUILD/'full-regression.log',BUILD/'web-checks.json',BUILD/'web-checks.log',BUILD/'browser-checks.json',BUILD/'web-desktop.png',BUILD/'web-mobile.png']:
        copy(p,release/p.name)
    archive=release/'furata.trajectory.source.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for directory in ['src','web','sim','doc']:
            for p in sorted(ROOT.joinpath(directory).rglob('*')):
                if p.is_file() and '__pycache__' not in p.parts:z.write(p,p.relative_to(ROOT))
        for name in ['furata.gprj','run_gowin.ps1','README.md']:z.write(ROOT/name,name)
    manifest['sourceArchiveSha256']=sha(archive)
    (release/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'release':str(release),'rtlPassed':passed,'webPassed':web['passed'],'timing':manifest['timing'],'bitstreamSha256':manifest['bitstreamSha256']},ensure_ascii=False))

if __name__=='__main__':main()

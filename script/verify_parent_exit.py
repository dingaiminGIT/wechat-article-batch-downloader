#!/usr/bin/env python3
import json,os,pathlib,subprocess,sys,tempfile,time,urllib.request
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='mp-archive-parent-') as work:
 p=pathlib.Path(work);(p/'config.yaml').write_text(json.dumps({'api':{'hostname':'127.0.0.1','port':2182},'proxy':{'hostname':'127.0.0.1','port':2183,'system':False,'skipInstallRootCert':True},'download':{'dir':str(p/'exports'),'playDoneAudio':False}}))
 code='''import os,subprocess,sys,time,urllib.request
root,work=sys.argv[1:]
log=open(work+'/service.log','w')
env=dict(os.environ,MP_ARCHIVE_PARENT=str(os.getpid()),MP_ARCHIVE_DATA=work)
p=subprocess.Popen([root+'/mp_article_downloader_src/mp_article_batch_downloader','--config',work+'/config.yaml'],env=env,stdout=log,stderr=log)
open(work+'/pid','w').write(str(p.pid))
op=urllib.request.build_opener(urllib.request.ProxyHandler({}))
for _ in range(60):
 try:op.open('http://127.0.0.1:2182/api/desktop/info',timeout=1);break
 except Exception:time.sleep(.1)
else:raise RuntimeError('not ready')
'''
 subprocess.run([sys.executable,'-c',code,str(root),work],check=True)
 pid=int((p/'pid').read_text())
 for _ in range(80):
  try:os.kill(pid,0)
  except ProcessLookupError:print('parent exit → backend shutdown: passed');break
  time.sleep(.1)
 else:
  os.kill(pid,15);raise AssertionError('backend outlived parent')

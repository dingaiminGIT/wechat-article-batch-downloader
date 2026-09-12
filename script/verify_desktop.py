#!/usr/bin/env python3
"""Exercise the real backend and exporter against a local deterministic article fixture."""
import http.server,json,os,pathlib,subprocess,tempfile,threading,time,urllib.request
root=pathlib.Path(__file__).resolve().parents[1]
backend=root/'mp_article_downloader_src/mp_article_batch_downloader'
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
class Fixture(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  content='<html><script>window.cgiDataNew = '+json.dumps({'title':'版本 1.2：归档验证','content_noencode':'<h2>测试正文</h2><p>这是一篇用于验证中文、标点与导出完整性的本地测试文章。</p>','nick_name':'本地验证账号','author':'测试作者'},ensure_ascii=False)+';</script></html>'
  self.send_response(200);self.send_header('Content-Type','text/html;charset=utf-8');self.end_headers();self.wfile.write(content.encode())
 def log_message(self,*args):pass
fixture=http.server.HTTPServer(('127.0.0.1',0),Fixture)
threading.Thread(target=fixture.serve_forever,daemon=True).start()
with tempfile.TemporaryDirectory(prefix='mp-archive-verify-') as work:
 work=pathlib.Path(work)
 config={'api':{'hostname':'127.0.0.1','port':2182},'proxy':{'hostname':'127.0.0.1','port':2183,'system':False,'skipInstallRootCert':True},'download':{'dir':str(work/'exports'),'playDoneAudio':False}}
 (work/'config.yaml').write_text(json.dumps(config))
 env=dict(os.environ,MP_ARCHIVE_PARENT=str(os.getpid()),MP_ARCHIVE_DATA=str(work))
 log=open(work/'service.log','w')
 p=subprocess.Popen([str(backend),'--config',str(work/'config.yaml')],env=env,stdout=log,stderr=log)
 def api(path,body=None):
  req=urllib.request.Request('http://127.0.0.1:2182'+path,data=json.dumps(body).encode() if body is not None else None,headers={'Content-Type':'application/json'})
  return json.load(opener.open(req,timeout=20))
 try:
  for _ in range(60):
   try:api('/api/desktop/info');break
   except Exception:time.sleep(.1)
  else:raise AssertionError('backend startup failed')
  article={'URL':f'officialaccount://http://127.0.0.1:{fixture.server_port}/article','Filename':'版本1.2-固定标识.html','Dir':'集成验证','on_exists':'skip'}
  first=api('/api/desktop/queue',[article]);assert first['data']['created']==1,first
  duplicate=api('/api/desktop/queue',[article]);assert duplicate['data']['skipped']==1,duplicate
  for _ in range(100):
   task=api('/api/task/list?page=1&page_size=10')['data']['list'][0]
   if task['status'] in ('done','error'):break
   time.sleep(.1)
  assert task['status']=='done',task.get('error')
  assert task['files_exist'],task
  paths=[pathlib.Path(x) for x in task['expected_files']]
  assert len(paths)==3 and all(x.exists() for x in paths)
  assert all('版本1.2-固定标识' in x.name for x in paths),paths
  plain=next(x for x in paths if x.suffix=='.txt').read_text();assert '测试正文' in plain and '本地测试文章' in plain
  corpus=work/'exports/集成验证/style_corpus.jsonl';assert len(corpus.read_text().splitlines())==1
  after=api('/api/desktop/queue',[article]);assert after['data']['skipped']==1,after
  next(x for x in paths if x.suffix=='.txt').unlink()
  repaired=api('/api/desktop/queue',[article]);assert repaired['data']['created']==1,repaired
  for _ in range(100):
   repaired_task=api('/api/task/list?page=1&page_size=10')['data']['list'][0]
   if repaired_task['status'] in ('done','error'):break
   time.sleep(.1)
  assert repaired_task['files_exist'] and repaired_task['status']=='done',repaired_task
  bad=api('/api/task/create2',dict(article,Dir='../outside'));assert bad['code']==400,bad
  page=api('/api/task/list?page=-1&page_size=-10');assert page['code']==0 and page['data']['page']==1,page
  print(json.dumps({'startup':'passed','batch_enqueue':'passed','inflight_dedup':'passed','completed_dedup':'passed','HTML_Markdown_TXT_JSONL':'passed','dotted_filename':'passed','partial_output_repair':'passed','path_boundary':'passed','pagination_bounds':'passed'},ensure_ascii=False))
 finally:
  p.terminate();p.wait(timeout=15);log.close();fixture.shutdown()

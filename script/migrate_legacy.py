#!/usr/bin/env python3
"""Copy legacy account records on local installation, retaining newer app records."""
import json,os,pathlib
root=pathlib.Path(__file__).resolve().parents[1]
source=root/'mp.json'
target=pathlib.Path.home()/'Library/Application Support/MPArticleDownloader/mp.json'
if source.is_file():
 try:
  legacy=json.loads(source.read_text());current=json.loads(target.read_text()) if target.exists() else {}
  if isinstance(legacy,dict) and isinstance(current,dict):
   merged=dict(legacy);merged.update(current)
   target.parent.mkdir(parents=True,exist_ok=True)
   temporary=target.with_suffix('.migration.tmp');temporary.write_text(json.dumps(merged,ensure_ascii=False));temporary.chmod(0o600);os.replace(temporary,target)
   print(f'已保留 {len(merged)} 个公众号的本地记录；旧目录保持不变。')
 except (OSError,ValueError) as error:
  print('旧版记录未导入：',type(error).__name__)

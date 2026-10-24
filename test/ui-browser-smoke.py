"""Optional browser regression: python test/ui-browser-smoke.py

Requires playwright Python package and a local Chromium. Uses in-memory mock DSH
responses; never accesses a real DSH or Cloudflare service.
"""
import base64
import json
import os
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
JS = (ROOT / 'lib' / 'client.js').read_text(encoding='utf-8')
state = {
    'instanceId':'test-dsh-instance-id',
    'gateway':{'running':True,'port':39081},
    'lan': {
        'enabled': True, 'running': True, 'port': 39081,
        'addresses': [{'interface': 'WLAN', 'address': '192.168.1.2'},
                      {'interface': 'Ethernet', 'address': '10.0.0.10'}],
        'urls': ['http://192.168.1.2:39081', 'http://10.0.0.10:39081'],
        'selectedAddress': '192.168.1.2', 'passwordMode': 'random',
        'visiblePassword': 'example-password', 'error': '',
    },
    'public': {
        'enabled': True, 'running': True, 'port': 39081, 'mode': 'quick',
        'hostname': '', 'hasToken': False, 'binaryPath': '',
        'url': 'https://one.trycloudflare.com', 'tunnelState': 'online',
        'passwordMode': 'random', 'visiblePassword': 'another-password', 'error': '',
    },
    'frpc': {'enabled': False, 'running': False, 'port': 39081, 'serverAddr': '', 'serverPort': 7000,
             'remotePort': 0, 'proxyName':'dsh-mobile', 'publicUrl':'', 'hasToken': False, 'binaryPath':'',
             'url':'', 'tunnelState':'stopped', 'passwordMode':'random',
             'visiblePassword':'another-password', 'error':''},
    'recentLogs': [{'time': '2026-10-21T05:21:00Z', 'level': 'info',
                    'message': '插件初始化完成'}],
}
# Tiny valid PNG, enough for the QR image mock (not a functional QR code).
QR = ('data:image/png;base64,' + base64.b64encode(base64.b64decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9E'
    'VsEAAAAASUVORK5CYII='  # test image only
)).decode('ascii'))
html = '''<!doctype html><html lang="zh"><meta charset="utf-8">
<style>body{font-family:sans-serif}.settingsArea{position:fixed;left:10px;bottom:10px;width:230px}
.accountRow{position:relative;width:225px;height:52px}.accountRow>button{width:100%;height:100%}</style>
<div class="settingsArea"><div class="accountRow" data-dsh-mobile-account-row>
<button aria-haspopup="menu">账号</button></div></div>
<script>
window.fake=FAKE;window.qrRequests=0;window.lastConfigure=null;
window.fetch=async(u,options={})=>{if(String(u).includes('/configure'))window.lastConfigure=JSON.parse(options.body);
return ({ok:true,json:async()=>String(u).includes('/qr?')
? (window.qrRequests++,{dataUrl:QRCODE}) : structuredClone(window.fake)});};
window.setInterval=(fn)=>{window.poll=fn;return 1};window.clearInterval=()=>{};
window.__ModuleLoader__={load({factory}){const p=factory(()=>({}));p.apply({effect(){}});
setTimeout(()=>document.querySelector('.dsh-mobile-trigger').click(),0)}};
</script><script>CLIENT</script></html>'''
html = (html.replace('FAKE', json.dumps(state, ensure_ascii=False))
        .replace('QRCODE', json.dumps(QR)).replace('CLIENT', JS))

with sync_playwright() as playwright:
    chromium = os.environ.get('CHROMIUM_BIN') or '/usr/bin/chromium'
    browser = playwright.chromium.launch(executable_path=chromium,headless=True,args=['--no-sandbox','--disable-dev-shm-usage'])
    page = browser.new_page(viewport={'width': 1280, 'height': 900})
    errors = []
    page.on('pageerror',lambda error:errors.append(str(error)))
    page.set_content(html)
    page.locator('.dsh-mobile-id-value').wait_for(timeout=5000)
    ids=['base','lan','public','frpc','logs']
    assert page.locator('.dsh-mobile-tab-name').all_text_contents()==['基础配置','局域网','Cloudflare隧道','frpc隧道','运行日志']
    assert page.locator('.dsh-mobile-overview-pill').count()==3
    assert page.locator('[aria-selected=true].dsh-mobile-tab').get_attribute('data-tab')=='base'
    assert page.locator('input[type=number]').count()==1
    assert page.locator('input[type=password]').count()==2
    assert page.locator('.dsh-mobile-qr').count()==0
    # Polling does not recreate an in-progress form.
    page.evaluate("""() => {window.beforeBase=document.querySelector('.dsh-mobile-section');
      document.querySelector('input[type=number]').value='40123';
      window.oldScroll=document.querySelector('.dsh-mobile-content').scrollTop;}""")
    page.evaluate("""async()=>{window.fake.recentLogs.push({time:'2026-10-21T05:22:00Z',level:'info',message:'连接恢复'});await window.poll();}""")
    assert page.evaluate("window.beforeBase===document.querySelector('.dsh-mobile-section')")
    assert page.locator('input[type=number]').input_value()=='40123'
    page.locator('input[type=password]').nth(0).fill('MyLanPass456789')
    page.locator('input[type=password]').nth(1).fill('MyPublicPass12345')
    page.locator('button:has-text("保存基础配置")').click()
    assert page.evaluate('window.lastConfigure.mode')=='base'
    assert page.evaluate('window.lastConfigure.patch')=={'port':40123,'lanPassword':'MyLanPass456789','publicPassword':'MyPublicPass12345'}
    page.screenshot(path='/mnt/data/dsh-mobile-plugin-dev13-preview-base.png',animations='disabled')
    page.locator('[data-tab="lan"]').click()
    assert page.locator('.dsh-mobile-switch-row').count()==1
    assert page.locator('select.dsh-mobile-select').count()==1
    assert page.locator('.dsh-mobile-qr').count()==1
    assert page.locator('input[type=password]').count()==0
    assert page.locator('input[type=number]').count()==0
    old=page.evaluate('window.qrRequests')
    page.evaluate('''async()=>{await window.poll();await window.poll();}''')
    assert page.evaluate('window.qrRequests')==old
    page.locator('select.dsh-mobile-select').select_option('10.0.0.10')
    assert '10.0.0.10' in page.locator('.dsh-mobile-url').inner_text()
    page.screenshot(path='/mnt/data/dsh-mobile-plugin-dev13-preview-lan.png',animations='disabled')

    page.locator('[data-tab="public"]').click()
    assert page.locator('input[type=number]').count()==0
    assert page.locator('input[type=password]').count()==1 # Tunnel token only.
    page.locator('details').first.evaluate('(el)=>{el.open=true}')
    assert page.locator('select.dsh-mobile-select').count()==2
    page.locator('select.dsh-mobile-select').nth(1).select_option('ghfast')
    page.locator('button:has-text("保存并应用")').click()
    assert page.evaluate('window.lastConfigure.mode')=='public'
    assert page.evaluate('window.lastConfigure.patch.downloadSource')=='ghfast'
    assert 'password' not in page.evaluate('window.lastConfigure.patch')
    page.evaluate('''async()=>{window.fake.public.url='https://new.trycloudflare.com';await window.poll();}''')
    assert 'new.trycloudflare.com' in page.locator('.dsh-mobile-url').inner_text()
    page.screenshot(path='/mnt/data/dsh-mobile-plugin-dev13-preview-cloudflare.png',animations='disabled')

    page.locator('[data-tab="frpc"]').click()
    assert page.locator('input[placeholder="frp.example.com"]').count()==1
    assert page.locator('input[type=password]').count()==1 # frps token only
    assert page.locator('input[type=number]').count()==2
    page.locator('input[placeholder="frp.example.com"]').fill('frps.example.com')
    page.locator('input[type=number]').nth(1).fill('40443')
    page.locator('button:has-text("保存并应用")').click()
    assert page.evaluate('window.lastConfigure.mode')=='frpc'
    assert page.evaluate('window.lastConfigure.patch.serverAddr')=='frps.example.com'
    assert page.evaluate('window.lastConfigure.patch.remotePort')==40443
    assert 'password' not in page.evaluate('window.lastConfigure.patch')
    page.screenshot(path='/mnt/data/dsh-mobile-plugin-dev13-preview-frpc.png',animations='disabled')

    page.locator('[data-tab="logs"]').click()
    page.locator('[data-dsh-mobile-log-view]').wait_for()
    assert page.locator('.dsh-mobile-log-line').count()==2
    page.evaluate("""() => {window.logNode=document.querySelector('.dsh-mobile-log');
      window.logNode.style.height='302px';window.logNode.dispatchEvent(new Event('pointerup'));}""")
    page.evaluate("""async()=>{window.fake.recentLogs.push({time:'2026-10-21T05:23:00Z',level:'warn',message:'隧道断开，正在重连'});await window.poll();}""")
    assert page.locator('.dsh-mobile-log-line').count()==3
    assert page.evaluate('window.logNode===document.querySelector(".dsh-mobile-log")')
    page.evaluate("""() => Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async t=>window.copied=t}})""")
    page.locator('button:has-text("复制日志")').click()
    assert '隧道断开' in page.evaluate('window.copied')
    page.locator('[data-tab="base"]').click()
    page.locator('[data-tab="logs"]').click()
    assert page.locator('.dsh-mobile-log').evaluate('(el)=>el.style.height')=='302px'
    page.screenshot(path='/mnt/data/dsh-mobile-plugin-dev13-preview-logs.png',animations='disabled')

    # Layout remains stable and all controls retain the 40px sizing.
    for width,height in [(1280,900),(1280,480),(390,760),(390,480)]:
        page.set_viewport_size({'width':width,'height':height})
        page.wait_for_timeout(50)
        h=[]
        for tab in ids:
            page.locator(f'[data-tab="{tab}"]').click()
            box=page.evaluate("""() => {const r=document.querySelector('.dsh-mobile-panel').getBoundingClientRect();
              return {height:r.height,top:r.top,bottom:r.bottom,content:document.querySelector('.dsh-mobile-content').clientHeight};}""")
            assert box['top']>=-1 and box['bottom']<=height+1,(width,height,tab,box)
            assert box['content']>0,(width,height,tab,box)
            h.append(box['height'])
        assert max(h)-min(h)<1,(width,height,h)
        assert abs(h[0]-min(760,height-(20 if width<=760 else 52)))<1
        page.locator('[data-tab="base"]').click()
        sizes=page.evaluate("""() => [...document.querySelectorAll('input.dsh-mobile-input,select.dsh-mobile-select')]
          .filter(e=>e.getClientRects().length).map(e=>e.getBoundingClientRect().height)""")
        assert set(sizes)=={40},(width,height,sizes)
        tab_sizes=page.locator('.dsh-mobile-tab').evaluate_all('(items)=>items.map(e=>e.getBoundingClientRect().height)')
        assert set(tab_sizes)==({44} if width<=760 else {46}),(width,height,tab_sizes)
    assert not errors,errors
    print('Browser smoke: PASS (5 tabs, base settings, QR, logs, fixed layout, 4 viewports)')
    browser.close()

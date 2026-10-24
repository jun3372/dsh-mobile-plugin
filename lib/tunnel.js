import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { resolveCloudflared } from './cloudflared.js';

const quickUrlRegex = /https:\/\/[a-z0-9-]+\.trycloudflare\.com\b/i;
export class TunnelManager extends EventEmitter {
  constructor({ executable = '', spawnFn = spawn, resolver } = {}) {
    super(); this.executable = executable; this.spawnFn = spawnFn; this.resolver=resolver || (spawnFn===spawn ? resolveCloudflared : async()=>executable||'cloudflared'); this.generation=0; this.child = null; this.url = ''; this.state = 'stopped'; this.error = ''; this.mode = 'quick'; this.stopping = false;
  }
  async start({ mode = 'quick', originPort, hostname = '', token = '', binaryPath = '', downloadSource = 'official', downloadMirror = '' }) {
    this.stop();
    const generation=this.generation;
    if (!Number.isInteger(originPort) || originPort < 1 || originPort > 65535) throw new Error('invalid port');
    if (mode !== 'quick' && mode !== 'named') throw new Error('invalid tunnel mode');
    if (mode === 'named' && (!token || !/^https:\/\/[^/]+$/i.test(hostname))) throw new Error('named tunnel needs token and https hostname');
    this.stopping = false; this.mode = mode; this.error = ''; this.url = mode === 'named' ? hostname : ''; this.state = 'connecting';
    const args = mode === 'quick'
      ? ['tunnel', '--no-autoupdate', '--url', `http://127.0.0.1:${originPort}`]
      : ['tunnel', '--no-autoupdate', 'run'];
    const env = mode === 'named' ? { ...process.env, TUNNEL_TOKEN: token } : { ...process.env };
    let child;
    try {
      const binary=await this.resolver({explicit:binaryPath||this.executable,downloadSource,downloadMirror});
      if(generation!==this.generation)return;
      child=this.spawnFn(binary,args,{env,stdio:['ignore','pipe','pipe'],windowsHide:true});
    } catch(e) {
      if(generation===this.generation){this.state='error';this.error=e.message;this.emit('change');}
      throw e;
    }
    this.child = child; this.emit('change');
    let logs = '';
    const parse = chunk => {
      logs = (logs + chunk.toString()).slice(-8192);
      if (mode === 'quick') {
        const result = logs.match(quickUrlRegex);
        if (result) { this.url = result[0]; this.state = 'online'; this.emit('change'); }
      } else if (/registered tunnel connection|connection registered|initial protocol/i.test(logs)) {
        this.state = 'online'; this.emit('change');
      }
    };
    child.stdout?.on('data', parse); child.stderr?.on('data', parse);
    child.on('error', error => { if (this.child !== child) return; this.child = null; this.state = 'error'; this.error = error.code==='ENOENT' ? 'cloudflared executable missing. Install cloudflared or configure its executable path.' : error.message; this.emit('change'); if(!this.stopping) this.emit('lost'); });
    child.on('exit', (code, signal) => {
      if (this.child !== child) return;
      this.child = null;
      if (!this.stopping) { this.state = 'error'; this.error = `cloudflared exited (${code ?? signal ?? 'unknown'})`; this.emit('lost'); }
      else this.state = 'stopped';
      this.emit('change');
    });
  }
  stop() { this.generation++; this.stopping = true; const child=this.child; this.child=null; if(child) { child.kill('SIGTERM'); } this.url=''; this.state='stopped'; this.emit('change'); }
  snapshot() { return { mode:this.mode, state:this.state, url:this.url, error:this.error }; }
}

import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { mkdir, rename, writeFile, chmod } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';
import { resolveFrpc } from './frpc-downloader.js';
export { resolveFrpc } from './frpc-downloader.js';

const home = () => process.env.DSH_HOME || join(homedir(), '.dsh');
const configFile = () => join(home(), 'dsh-mobile-plugin', 'frpc.toml');

const portValid = n => Number.isInteger(n) && n >= 1 && n <= 65535;
export function validFrpcHost(value) {
  if(typeof value !== 'string' || value.length > 253 || !/^[a-zA-Z0-9.\-]+$/.test(value) || value.startsWith('-') || value.endsWith('-') || value.includes('..')) return false;
  return true;
}
export function renderFrpcConfig({ serverAddr, serverPort, remotePort, authToken = '', proxyName = 'dsh-mobile', originPort }) {
  if(!validFrpcHost(serverAddr)) throw new Error('frps 地址无效（请填写 IP 或域名，不含协议及端口）');
  if(!portValid(serverPort) || !portValid(remotePort) || !portValid(originPort)) throw new Error('frpc 端口无效');
  if(!/^[a-zA-Z0-9_-]{1,64}$/.test(proxyName)) throw new Error('frpc 映射名称仅允许英文字母、数字、横线和下划线');
  if(typeof authToken !== 'string' || authToken.length > 8192) throw new Error('frps Token 无效');
  // Use JSON escaped strings, which are also valid TOML basic strings, never interpolate unescaped user input.
  return `serverAddr = ${JSON.stringify(serverAddr)}\nserverPort = ${serverPort}\nauth.method = "token"\nauth.token = ${JSON.stringify(authToken)}\ntransport.tls.enable = true\n\n[[proxies]]\nname = ${JSON.stringify(proxyName)}\ntype = "tcp"\nlocalIP = "127.0.0.1"\nlocalPort = ${originPort}\nremotePort = ${remotePort}\n`;
}
export function frpcPublicUrl({ publicUrl = '', serverAddr, remotePort }) {
  const raw = publicUrl || `http://${serverAddr}:${remotePort}`;
  let u;
  try { u = new URL(raw); } catch { throw new Error('frpc 手机连接地址无效'); }
  if(!['http:', 'https:'].includes(u.protocol) || !u.hostname || u.username || u.password || u.pathname !== '/' || u.search || u.hash) throw new Error('frpc 手机连接地址只能是 http(s)://域名[:端口]');
  return u.origin;
}
export class FrpcManager extends EventEmitter {
  constructor({ spawnFn = spawn, resolver = resolveFrpc, file = configFile() } = {}) {
    super();this.spawnFn = spawnFn;this.resolver = resolver;this.file = file;
    this.generation = 0;this.child = null;this.state = 'stopped';this.error = '';this.url = '';this.stopping = false;
  }
  async start(opts) {
    this.stop();const generation = this.generation;
    const text = renderFrpcConfig(opts);
    const url = frpcPublicUrl(opts);
    this.stopping = false;this.state = 'connecting';this.error = '';this.url = url;this.emit('change');
    try {
      const binary = await this.resolver({ explicit: opts.binaryPath || '', downloadSource: opts.downloadSource || 'official', downloadMirror: opts.downloadMirror || '', onProgress: message => this.emit('install', message) });
      if(generation !== this.generation) return;
      await mkdir(dirname(this.file), { recursive: true, mode: 0o700 });
      const tmp = `${this.file}.${process.pid}.tmp`;
      await writeFile(tmp, text, { mode: 0o600 });await chmod(tmp, 0o600);
      await rename(tmp, this.file);await chmod(this.file, 0o600);
      if(generation !== this.generation) return;
      const child = this.spawnFn(binary, ['-c', this.file], { stdio: ['ignore','pipe','pipe'], windowsHide: true });
      this.child = child;
      let tail = '';
      const parse = chunk => {
        if(this.child !== child) return;
        tail = (tail + String(chunk)).slice(-4096);
        if(/start proxy success|proxy added|login to server success|\[.*\] start proxy success/i.test(tail)) {
          if(this.state !== 'online') {this.state = 'online';this.emit('change');}
        }
        if(/login to server failed|start error|authentication failed|authorization failed/i.test(tail)) {
          this.error = 'frpc 无法连接 frps 或认证失败，请检查地址、端口、Token 与映射端口';
          this.state = 'error';this.emit('change');
        }
      };
      child.stdout?.on('data', parse);child.stderr?.on('data', parse);
      child.on('error', e => {
        if(this.child !== child)return;
        this.child = null;this.state = 'error';this.error = e.code === 'ENOENT' ? 'frpc 可执行文件不存在或没有执行权限，请检查程序路径' : e.message;
        this.emit('change');if(!this.stopping)this.emit('lost');
      });
      child.on('exit', (code, signal) => {
        if(this.child !== child)return;
        this.child = null;this.state = this.stopping ? 'stopped' : 'error';
        if(!this.stopping) {this.error = `frpc 进程退出（${code ?? signal ?? '未知'}）`;this.emit('lost');}
        this.emit('change');
      });
    }catch(e){if(generation===this.generation){this.state='error';this.error=e.message;this.emit('change');}throw e;}
  }
  stop() {
    this.generation++;this.stopping = true;
    const child = this.child;this.child = null;
    if(child) child.kill('SIGTERM');
    this.state = 'stopped';this.url='';this.emit('change');
  }
  snapshot() {return { state: this.state, error: this.error, url: this.url };}
}

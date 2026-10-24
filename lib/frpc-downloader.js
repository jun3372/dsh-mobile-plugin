/**
 * 官方 frp Release 的按需安装器。仅下载固定版本、官方 GitHub 资产，
 * 校验官方 SHA-256 清单后只提取 frpc / frpc.exe。
 * 不执行下载脚本、不依赖 shell/tar/unzip 或第三方 npm 模块。
 */
import { access, chmod, mkdir, rename, rm, stat, writeFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { homedir, arch as currentArch, platform as currentPlatform } from 'node:os';
import { delimiter, isAbsolute, join } from 'node:path';
import { gunzipSync, inflateRawSync } from 'node:zlib';
import { buildDownloadUrl, allowedDownloadUrl, downloadSourceLabel } from './download-source.js';

export const FRP_VERSION = '0.71.1';
const RELEASE = `https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}`;
const ARCHIVES = Object.freeze({
  'win32-x64': 'windows_amd64.zip',
  'win32-arm64': 'windows_arm64.zip',
  'darwin-x64': 'darwin_amd64.tar.gz',
  'darwin-arm64': 'darwin_arm64.tar.gz',
  'linux-x64': 'linux_amd64.tar.gz',
  'linux-arm64': 'linux_arm64.tar.gz',
  'linux-arm': 'linux_arm.tar.gz',
});
const TRUSTED_REDIRECT_HOSTS = new Set([
  'github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com',
]);
const MAX_ARCHIVE_BYTES = 45_000_000;
const MAX_BINARY_BYTES = 64_000_000;
const MAX_UNPACKED_BYTES = 128_000_000;
const inFlight = new Map();

const executableName = osPlatform => osPlatform === 'win32' ? 'frpc.exe' : 'frpc';
const pluginHome = () => join(process.env.DSH_HOME || join(homedir(), '.dsh'), 'dsh-mobile-plugin');
async function isExecutable(file, osPlatform) {
  try {
    const s = await stat(file);
    if (!s.isFile()) return false;
    await access(file, osPlatform === 'win32' ? constants.F_OK : constants.X_OK);
    return true;
  } catch { return false; }
}
async function findOnPath(exe, systemPath, osPlatform) {
  const items = osPlatform === 'win32' && !exe.toLowerCase().endsWith('.exe') ? [exe + '.exe', exe] : [exe];
  for (const folder of systemPath.split(delimiter).filter(Boolean)) {
    for (const item of items) {
      const file = join(folder, item);
      if (await isExecutable(file, osPlatform)) return file;
    }
  }
  return '';
}

/** Follow only official HTTPS release-asset redirects; bound time and size. */
export async function fetchOfficialAsset(url, { fetchFn = fetch, maxBytes = MAX_ARCHIVE_BYTES, downloadSource = 'official', downloadMirror = '' } = {}) {
  let current = url;
  for (let i = 0; i < 6; i++) {
    const u = new URL(current);
    if (!allowedDownloadUrl(current,downloadSource,downloadMirror))
      throw new Error('frpc 下载重定向被安全策略阻止');
    const response = await fetchFn(current, { redirect: 'manual', signal: AbortSignal.timeout(90_000) });
    if ([301,302,303,307,308].includes(response.status)) {
      const next = response.headers.get('location');
      if (!next) throw new Error('frpc 下载重定向缺少地址');
      current = new URL(next, current).href;
      continue;
    }
    if (!response.ok) throw new Error(`GitHub 官方下载 HTTP ${response.status}`);
    if (!response.body) throw new Error('frpc 下载响应缺少数据');
    const parts = []; let bytes = 0;
    for await (const part of response.body) {
      bytes += part.length;
      if (bytes > maxBytes) throw new Error('frpc 下载文件超过大小限制');
      parts.push(part);
    }
    return Buffer.concat(parts, bytes);
  }
  throw new Error('frpc 下载重定向次数过多');
}

export function checksumForArchive(manifest, filename) {
  if (typeof manifest !== 'string' || manifest.length > 24_000) throw new Error('frp 官方 SHA-256 清单无效');
  // 官方 frp_sha256_checksums.txt 格式：<sha256>  <asset_name>
  const matches = manifest.split(/\r?\n/).map(line => /^([a-fA-F0-9]{64})\s+\*?(\S+)\s*$/.exec(line))
    .filter(match => match && match[2] === filename);
  if (matches.length !== 1) throw new Error('frp 官方 SHA-256 清单未包含唯一的当前平台文件');
  return matches[0][1].toLowerCase();
}

/** tar.gz archive parser: only reads the named, regular-file frpc entry. */
export function extractFrpcTarGz(compressed, expectedDir) {
  const tar = gunzipSync(compressed, { maxOutputLength: MAX_UNPACKED_BYTES });
  for (let offset = 0; offset + 512 <= tar.length;) {
    const header = tar.subarray(offset, offset + 512);
    if (header.every(byte => byte === 0)) break;
    const filename = header.subarray(0, 100).toString('utf8').replace(/\0.*$/, '');
    const octal = header.subarray(124, 136).toString('ascii').replace(/\0.*$/, '').trim();
    if (!/^[0-7]+$/.test(octal)) throw new Error('frp tar 条目大小格式错误');
    const size = Number.parseInt(octal, 8);
    if (!Number.isSafeInteger(size) || size < 0 || offset + 512 + size > tar.length) throw new Error('frp tar 文件损坏');
    if (filename === `${expectedDir}/frpc` && (header[156] === 0 || header[156] === 48)) {
      if (size < 10_000 || size > MAX_BINARY_BYTES) throw new Error('frpc 可执行程序尺寸异常');
      return Buffer.from(tar.subarray(offset + 512, offset + 512 + size));
    }
    offset += 512 + Math.ceil(size / 512) * 512;
  }
  throw new Error('frp 压缩包中没有找到 frpc 可执行程序');
}

/** ZIP central-directory reader, supports stored/deflated entries but no ZIP64 or symlink extraction. */
export function extractFrpcZip(archive, expectedDir) {
  let end = -1;
  for (let i = archive.length - 22; i >= Math.max(0, archive.length - 65557); i--) {
    if (archive.readUInt32LE(i) === 0x06054b50 && i + 22 + archive.readUInt16LE(i + 20) === archive.length) {
      end = i; break;
    }
  }
  if (end < 0) throw new Error('frp ZIP 压缩包缺少目录');
  const entries = archive.readUInt16LE(end + 10);
  let cursor = archive.readUInt32LE(end + 16);
  const directorySize = archive.readUInt32LE(end + 12);
  if (entries > 512 || cursor + directorySize > end) throw new Error('frp ZIP 目录无效');
  for (let index = 0; index < entries; index++) {
    if (cursor + 46 > end || archive.readUInt32LE(cursor) !== 0x02014b50) throw new Error('frp ZIP 条目损坏');
    const method = archive.readUInt16LE(cursor + 10);
    const packedSize = archive.readUInt32LE(cursor + 20);
    const size = archive.readUInt32LE(cursor + 24);
    const nameLength = archive.readUInt16LE(cursor + 28);
    const extraLength = archive.readUInt16LE(cursor + 30);
    const commentLength = archive.readUInt16LE(cursor + 32);
    const attrs = archive.readUInt32LE(cursor + 38);
    const localOffset = archive.readUInt32LE(cursor + 42);
    const next = cursor + 46 + nameLength + extraLength + commentLength;
    if (next > end) throw new Error('frp ZIP 文件名无效');
    const filename = archive.subarray(cursor + 46, cursor + 46 + nameLength).toString('utf8');
    if (filename === `${expectedDir}/frpc.exe`) {
      const unixMode = attrs >>> 16;
      if ((unixMode & 0o170000) === 0o120000) throw new Error('frp ZIP 的 frpc 不能是符号链接');
      if (size < 10_000 || size > MAX_BINARY_BYTES || packedSize > MAX_ARCHIVE_BYTES) throw new Error('frpc 可执行程序尺寸异常');
      if (localOffset + 30 > archive.length || archive.readUInt32LE(localOffset) !== 0x04034b50) throw new Error('frp ZIP 本地文件头无效');
      const start = localOffset + 30 + archive.readUInt16LE(localOffset + 26) + archive.readUInt16LE(localOffset + 28);
      if (start + packedSize > archive.length) throw new Error('frp ZIP 文件内容不完整');
      const packed = archive.subarray(start, start + packedSize);
      const binary = method === 0 ? Buffer.from(packed) : method === 8 ? inflateRawSync(packed, { maxOutputLength: MAX_BINARY_BYTES }) : null;
      if (!binary || binary.length !== size) throw new Error('frp ZIP 文件解压失败');
      return binary;
    }
    cursor = next;
  }
  throw new Error('frp ZIP 压缩包中没有找到 frpc.exe');
}

export async function resolveFrpc({
  explicit = '', allowDownload = true, fetchFn = fetch, home = pluginHome(),
  systemPath = process.env.PATH || '', osPlatform = currentPlatform(), cpuArch = currentArch(),
  downloadSource = 'official', downloadMirror = '',
  onProgress = () => {},
} = {}) {
  const selected = explicit || process.env.DSH_MOBILE_FRPC || '';
  if (selected) {
    if (isAbsolute(selected) && await isExecutable(selected, osPlatform)) return selected;
    if (selected.includes('/') || selected.includes('\\')) throw new Error(`frpc 指定路径无效或无执行权限：${selected}`);
    const located = await findOnPath(selected, systemPath, osPlatform);
    if (located) return located;
    throw new Error(`未找到指定的 frpc 命令：${selected}`);
  }
  const binDir = join(home, 'bin');
  const target = join(binDir, executableName(osPlatform));
  if (await isExecutable(target, osPlatform)) return target;
  const found = await findOnPath(executableName(osPlatform), systemPath, osPlatform);
  if (found) return found;
  if (!allowDownload) throw new Error('未找到 frpc。请配置程序路径或启用自动下载。');
  const assetSuffix = ARCHIVES[`${osPlatform}-${cpuArch}`];
  if (!assetSuffix) throw new Error(`暂不支持在 ${osPlatform}/${cpuArch} 自动安装 frpc，请手动配置 frpc 程序路径`);

  // Prevent duplicate downloads for simultaneous starts within one plugin process.
  const promiseKey = `${target}|${assetSuffix}`;
  if (inFlight.has(promiseKey)) return inFlight.get(promiseKey);
  const promise = (async () => {
    const filename = `frp_${FRP_VERSION}_${assetSuffix}`;
    const folder = `frp_${FRP_VERSION}_${assetSuffix.replace(/\.(zip|tar\.gz)$/, '')}`;
    onProgress(`本机未发现 frpc，正在通过${downloadSourceLabel(downloadSource)}下载官方 frp v${FRP_VERSION} 资产 ${filename}`);
    let manifest, compressed;
    try {
      [manifest, compressed] = await Promise.all([
        fetchOfficialAsset(buildDownloadUrl(`${RELEASE}/frp_sha256_checksums.txt`,downloadSource,downloadMirror), { fetchFn, maxBytes: 24_000,downloadSource,downloadMirror }),
        fetchOfficialAsset(buildDownloadUrl(`${RELEASE}/${filename}`,downloadSource,downloadMirror), { fetchFn,downloadSource,downloadMirror }),
      ]);
    } catch (error) {
      throw new Error(`frpc 自动下载失败：${error.message}。请检查 GitHub 网络，或在高级设置填写 frpc 完整路径。`);
    }
    onProgress('frpc 下载完成，正在校验官方 SHA-256');
    const expected = checksumForArchive(manifest.toString('utf8'), filename);
    const digest = createHash('sha256').update(compressed).digest('hex');
    if (digest !== expected) throw new Error('frpc 下载包 SHA-256 校验失败，已取消安装');
    const binary = filename.endsWith('.zip') ? extractFrpcZip(compressed, folder) : extractFrpcTarGz(compressed, folder);
    await mkdir(binDir, { recursive: true, mode: 0o700 });
    if (await isExecutable(target, osPlatform)) return target;
    const temporary = `${target}.${process.pid}.${randomUUID()}.tmp`;
    try {
      await writeFile(temporary, binary, { flag: 'wx', mode: 0o700 });
      if (osPlatform !== 'win32') await chmod(temporary, 0o700);
      await rename(temporary, target);
    } finally {
      await rm(temporary, { force: true }).catch(() => {});
    }
    if (!await isExecutable(target, osPlatform)) throw new Error('frpc 下载后未获得执行权限');
    onProgress(`frpc 已自动安装至 ${target}，后续启动复用此程序`);
    return target;
  })();
  inFlight.set(promiseKey, promise);
  try { return await promise; } finally { if (inFlight.get(promiseKey) === promise) inFlight.delete(promiseKey); }
}

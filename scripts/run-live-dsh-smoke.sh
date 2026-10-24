#!/usr/bin/env bash
# Real DSH integration smoke test. Uses a disposable DSH_HOME and disables
# both public tunnels to avoid exposing this disposable Host to the Internet.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dsh-mobile-live.XXXXXX")"
export DSH_HOME="$WORK/home"
PORT="${DSH_TEST_WEB_PORT:-3080}"
GATEWAY_PORT="${DSH_TEST_GATEWAY_PORT:-39081}"
DSH_PID=""
finish(){
  if [[ -n "$DSH_PID" ]]; then kill "$DSH_PID" 2>/dev/null || true; wait "$DSH_PID" 2>/dev/null || true; fi
  printf '\n测试数据和日志目录：%s\n' "$WORK"
  printf 'DSH 日志：%s\n' "$WORK/dsh-web.log"
}
trap finish EXIT

if [[ "${DSH_MOBILE_REQUIRE_FULL_AUDIT:-0}" == "1" && ( -z "${DSH_MOBILE_AUDIT_MANIFEST:-}" || ! -f "${DSH_MOBILE_AUDIT_MANIFEST:-}" ) ]]; then
  echo '严格全接口验收已要求，但未提供真实 DSH 对应版本的完整接口清单：DSH_MOBILE_AUDIT_MANIFEST'; exit 3
fi
node -e 'const v=process.versions.node.split(".").map(Number);if(!(v[0]>=24||v[0]===22&&v[1]>=19)){console.error("DSH 需要 Node.js >=22.19 或 >=24，请先升级 Node.js");process.exit(1)}'
if [[ "$PORT" = "$GATEWAY_PORT" ]]; then echo 'DSH 与网关端口不能相同'; exit 1; fi
mkdir -p "$DSH_HOME"
# The npm package installer itself needs network access.
PKG="$WORK/$(cd "$ROOT" && npm pack --ignore-scripts --silent --pack-destination "$WORK")"
printf '正在通过 npx 创建隔离 DSH profile 并安装插件...\n'
npx --yes @deepseek-ai/dsh plugin --profile web add "$PKG"

# The first-run defaults enable Cloudflare, so write a secure test-only
# configuration before launching DSH. Passwords are generated once here.
(cd "$ROOT" && node --input-type=module - "$ROOT" "$GATEWAY_PORT" <<'JS'
import {join} from 'node:path';
import {initialSettings,saveSettings,loadSettings} from './lib/settings.js';
const port=Number(process.argv[3]);
const config=initialSettings();config.gateway.port=port;
config.lan.enabled=true;config.public.enabled=false;config.frpc.enabled=false;
const file=join(process.env.DSH_HOME,'dsh-mobile-plugin','settings.json');
await saveSettings(config,file);await loadSettings(file);
JS
)

printf '正在按指定命令启动 DSH Web...\n'
npx --yes @deepseek-ai/dsh web --no-open --port "$PORT" >"$WORK/dsh-web.log" 2>&1 & DSH_PID=$!
for i in $(seq 1 75); do
  if ! kill -0 "$DSH_PID" 2>/dev/null; then echo 'DSH 启动失败'; tail -45 "$WORK/dsh-web.log"; exit 1; fi
  if curl -fsS --max-time 1 "http://127.0.0.1:$GATEWAY_PORT/_dsh_mobile/v1/info" >"$WORK/info.json"; then break; fi
  sleep 2
done
if [[ ! -s "$WORK/info.json" ]]; then echo '插件网关未启动'; tail -50 "$WORK/dsh-web.log"; exit 1; fi
node "$ROOT/scripts/live-dsh-proxy-smoke.mjs" "$GATEWAY_PORT" "$DSH_HOME/dsh-mobile-plugin/settings.json"

if [[ -n "${DSH_MOBILE_AUDIT_MANIFEST:-}" ]]; then
  echo '按真实 DSH 版本接口清单，仅经插件网关逐项进行严格审计...';
  DSH_MOBILE_GATEWAY_URL="http://127.0.0.1:$GATEWAY_PORT" DSH_MOBILE_TEST_PASSWORD="$(node -e "console.log(require('fs').readFileSync(process.argv[1],'utf8')&&JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).lan.password)" "$DSH_HOME/dsh-mobile-plugin/settings.json")" \
    node "$ROOT/scripts/audit-gateway-only.mjs" "$DSH_MOBILE_AUDIT_MANIFEST" "$WORK/gateway-audit-report.json"
else
  echo '仅完成基础冒烟测试：未提供完整接口清单，DSH 所有接口仍未验收。'
fi

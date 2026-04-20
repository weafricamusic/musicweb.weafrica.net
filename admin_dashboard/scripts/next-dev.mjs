import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import path from 'node:path'

const nodeMajor = Number(process.versions.node.split('.')[0])

const forceWebpack = process.env.FORCE_WEBPACK === '1'
const forceTurbo = process.env.FORCE_TURBO === '1'

const useWebpack = forceWebpack || (!forceTurbo && nodeMajor !== 20)

const bin = process.platform === 'win32' ? 'next.cmd' : 'next'
const nextBin = path.join(process.cwd(), 'node_modules', '.bin', bin)

if (!existsSync(nextBin)) {
  console.error('[admin_dashboard] Missing next binary. Run `npm install` in admin_dashboard first.')
  process.exit(1)
}

const forwardedArgs = process.argv.slice(2)
const args = ['dev', ...(useWebpack ? ['--webpack'] : []), ...forwardedArgs]

if (useWebpack) {
  console.warn(`[admin_dashboard] Starting Next dev with webpack (Node ${process.versions.node}).`) 
} else {
  console.log('[admin_dashboard] Starting Next dev (Turbopack default).')
}

const child = spawn(nextBin, args, {
  stdio: 'inherit',
  env: process.env,
})

child.on('exit', (code, signal) => {
  if (signal) process.kill(process.pid, signal)
  process.exit(code ?? 0)
})

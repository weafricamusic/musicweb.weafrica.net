const requiredMajor = 20

function parseMajor(version) {
  const match = /^v?(\d+)/.exec(version ?? '')
  return match ? Number(match[1]) : NaN
}

const current = process.version
const major = parseMajor(current)

if (!Number.isFinite(major)) {
  console.error(`[admin_dashboard] Unable to parse Node version: ${current}`)
  process.exit(1)
}

if (major !== requiredMajor) {
  console.warn(
    [
      `[admin_dashboard] Node.js version: ${current}`,
      `[admin_dashboard] Recommended: Node ${requiredMajor}.x (see admin_dashboard/.nvmrc and package.json engines).`,
      `[admin_dashboard] Continuing anyway; dev mode may fall back to webpack for compatibility.`,
      '',
      'Fix for best results:',
      '  - If you use nvm:  cd admin_dashboard && nvm install && nvm use',
      '  - Or install Node 20 and re-run: npm run admin',
    ].join('\n'),
  )
  process.exit(0)
}

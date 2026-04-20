import { createHmac } from 'crypto'
import dotenv from 'dotenv'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'

// Prefer `.env.local` (Next.js local convention), fallback to `.env`.
// Use override so values pulled via `vercel env pull` apply reliably.
dotenv.config({ path: fs.existsSync('.env.local') ? '.env.local' : '.env', override: true })

const WEBHOOK_URL = process.env.WEBHOOK_URL || 'http://localhost:3000/api/webhooks/paychangu'
const PAYCHANGU_WEBHOOK_SECRET = process.env.PAYCHANGU_WEBHOOK_SECRET

if (!PAYCHANGU_WEBHOOK_SECRET) {
	console.error('❌ Error: PAYCHANGU_WEBHOOK_SECRET environment variable is not set')
	process.exit(1)
}

// Test payload - simulates a successful payment
const intervalCountRaw = process.env.TEST_INTERVAL_COUNT || process.env.TEST_MONTHS || '1'
const intervalCount = Math.max(1, Math.min(24, Number(intervalCountRaw) || 1))

const testPayload = {
	transaction_id: 'test-txn-' + Date.now(),
	// NOTE: the webhook handler expects subscription identifiers inside `meta`.
	meta: {
		user_id: process.env.TEST_USER_ID || 'test-user-123',
		plan_id: process.env.TEST_PLAN_ID || 'premium',
		// Backward-compatible: keep `months`, but treat it as interval count.
		months: intervalCount,
		interval_count: intervalCount,
		country_code: process.env.TEST_COUNTRY_CODE || 'MW',
	},
	email: 'test@example.com',
	amount: 2999,
	currency: 'KES',
	status: 'success',
	phone_number: '+254712345678',
	timestamp: new Date().toISOString(),
}

const rawBody = JSON.stringify(testPayload)
const signature = createHmac('sha256', PAYCHANGU_WEBHOOK_SECRET).update(rawBody).digest('hex')

console.log('🚀 Testing Paychangu Webhook Integration\n')
console.log('📤 Payload:', testPayload)
console.log('\n🔐 Signature:', signature)

async function testWebhook() {
	try {
		const u = new URL(WEBHOOK_URL)
		const useVercelCurl = u.hostname.endsWith('vercel.app') && String(process.env.USE_VERCEL_CURL || '1').trim() !== '0'

		if (useVercelCurl) {
			const writeOut = '\n__HTTP_CODE__:%{http_code}\n'
			const out = execFileSync(
				'vercel',
				[
					'curl',
					`${u.pathname}${u.search}`,
					'--deployment',
					u.origin,
					'--',
					'--silent',
					'--show-error',
					'--location',
					'--write-out',
					writeOut,
					'--request',
					'POST',
					'--header',
					'Content-Type: application/json',
					'--header',
					`x-paychangu-signature: ${signature}`,
					'--data-raw',
					rawBody,
				],
				{ encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
			)

			const lines = out.split('\n')
			const markerIdx = lines.findIndex((l) => l.startsWith('__HTTP_CODE__:'))
			const status = markerIdx >= 0 ? Number(lines[markerIdx].slice('__HTTP_CODE__:'.length)) : 0
			const text = markerIdx >= 0 ? lines.slice(0, markerIdx).join('\n') : out
			let data: any
			try {
				data = JSON.parse(text)
			} catch {
				data = { raw: text }
			}

			console.log('\n📨 Response Status:', status)
			console.log('📨 Response:', data)

			if (status >= 200 && status < 300) {
				console.log('\n✅ Webhook test PASSED')
			} else {
				console.log('\n❌ Webhook test FAILED')
			}
			return
		}

		const response = await fetch(WEBHOOK_URL, {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
				'x-paychangu-signature': signature,
			},
			body: rawBody,
		})

		const data = await response.json()

		console.log('\n📨 Response Status:', response.status)
		console.log('📨 Response:', data)

		if (response.ok) {
			console.log('\n✅ Webhook test PASSED')
		} else {
			console.log('\n❌ Webhook test FAILED')
		}
	} catch (error) {
		console.error('\n❌ Error testing webhook:', error)
		process.exit(1)
	}
}

testWebhook()

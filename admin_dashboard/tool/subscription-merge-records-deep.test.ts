import assert from 'node:assert/strict'

const { getSubscriptionEntitlementsExact } = await import(
	new URL('../src/lib/subscription/plans.ts', import.meta.url).href
)
const { mergeRecordsDeep } = await import(
	new URL('../src/lib/subscription/merge-records-deep.ts', import.meta.url).href
)

function getNestedValue(record: Record<string, unknown>, path: string): unknown {
	let current: unknown = record
	for (const part of path.split('.')) {
		if (!current || typeof current !== 'object' || Array.isArray(current) || !(part in current)) {
			return undefined
		}
		current = (current as Record<string, unknown>)[part]
	}
	return current
}

function verifyMergedArtistPlatinumFeatures() {
	const fallback = getSubscriptionEntitlementsExact('artist_premium')
	const mergedFeatures = mergeRecordsDeep(
		(fallback.features ?? {}) as Record<string, unknown>,
		{
			creator: {
				uploads: { songs: -1, videos: -1 },
				analytics: { level: 'advanced' },
			},
		},
	)

	assert.equal(getNestedValue(mergedFeatures ?? {}, 'creator.live.multi_guest'), true)
	assert.equal(getNestedValue(mergedFeatures ?? {}, 'creator.live.song_requests'), true)
	assert.equal(getNestedValue(mergedFeatures ?? {}, 'creator.withdrawals.access'), 'unlimited')
	assert.equal(getNestedValue(mergedFeatures ?? {}, 'vip_badge'), true)
	assert.deepEqual(getNestedValue(mergedFeatures ?? {}, 'tickets.sell.tiers'), ['standard', 'vip', 'priority'])
	assert.equal(getNestedValue(mergedFeatures ?? {}, 'monthly_bonus_coins'), 200)
}

function verifyMergedArtistPlatinumPerks() {
	const fallback = getSubscriptionEntitlementsExact('artist_premium')
	const mergedPerks = mergeRecordsDeep(
		(fallback.perks ?? {}) as Record<string, unknown>,
		{
			creator: {
				uploads: { songs: 'unlimited' },
			},
		},
	)

	assert.equal(getNestedValue(mergedPerks ?? {}, 'creator.live.multi_guest'), true)
	assert.equal(getNestedValue(mergedPerks ?? {}, 'creator.withdrawals.access'), 'unlimited')
	assert.deepEqual(getNestedValue(mergedPerks ?? {}, 'tickets.sell.tiers'), ['standard', 'vip', 'priority'])
	assert.equal(getNestedValue(mergedPerks ?? {}, 'monthly_bonus_coins'), 200)
}

verifyMergedArtistPlatinumFeatures()
verifyMergedArtistPlatinumPerks()
console.log('subscription-merge-records-deep: ok')
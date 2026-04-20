export type ReportReason =
	| 'copyright_infringement'
	| 'nudity_sexual_content'
	| 'hate_violence'
	| 'spam_scam'
	| 'harassment'
	| 'fake_account'
	| 'other'

export type ReportStatus = 'open' | 'resolved' | 'dismissed' | 'pending' | 'reviewed'

export type ContentType = 'song' | 'video' | 'live' | 'comment' | 'profile'

export function reasonLabel(r: string): string {
	switch (r) {
		case 'copyright_infringement':
			return 'Copyright infringement'
		case 'nudity_sexual_content':
			return 'Nudity / sexual content'
		case 'hate_violence':
			return 'Hate / violence'
		case 'spam_scam':
			return 'Spam / scam'
		case 'harassment':
			return 'Harassment'
		case 'fake_account':
			return 'Fake account'
		case 'other':
			return 'Other'
		default:
			return r
	}
}

export function contentTypeLabel(t: string): string {
	switch (t) {
		case 'song':
			return 'Song'
		case 'video':
			return 'Video'
		case 'live':
			return 'Live'
		case 'comment':
			return 'Comment'
		case 'profile':
			return 'Profile'
		default:
			return t
	}
}

export function backendReportStatus(value: string): 'pending' | 'reviewed' | 'dismissed' | undefined {
	switch (String(value).toLowerCase()) {
		case 'open':
		case 'pending':
			return 'pending'
		case 'resolved':
		case 'reviewed':
			return 'reviewed'
		case 'dismissed':
			return 'dismissed'
		default:
			return undefined
	}
}

export function reportStatusLabel(value: string): string {
	switch (String(value).toLowerCase()) {
		case 'pending':
		case 'open':
			return 'Open'
		case 'reviewed':
		case 'resolved':
			return 'Reviewed'
		case 'dismissed':
			return 'Dismissed'
		default:
			return value
	}
}

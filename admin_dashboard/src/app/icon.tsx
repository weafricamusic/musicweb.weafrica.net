import { ImageResponse } from 'next/og'

export const size = {
	width: 512,
	height: 512,
}

export const contentType = 'image/png'

export default function Icon() {
	return new ImageResponse(
		(
			<div
				style={{
					width: '100%',
					height: '100%',
					display: 'flex',
					alignItems: 'center',
					justifyContent: 'center',
					background: 'linear-gradient(135deg, #0b1220 0%, #111827 60%, #0b1220 100%)',
					color: 'white',
					fontSize: 168,
					fontWeight: 800,
					letterSpacing: -6,
				}}
			>
				WA
			</div>
		),
		size,
	)
}

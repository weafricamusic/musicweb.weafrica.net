import type { MetadataRoute } from 'next'

export default function manifest(): MetadataRoute.Manifest {
	return {
		name: 'WeAfrica Music Admin',
		short_name: 'WeAfrica Admin',
		description: 'WeAfrica Music admin dashboard',
		start_url: '/admin',
		display: 'standalone',
		background_color: '#0b1220',
		theme_color: '#0b1220',
		icons: [
			{
				src: '/icon',
				sizes: '512x512',
				type: 'image/png',
				purpose: 'any',
			},
			{
				src: '/icon',
				sizes: '512x512',
				type: 'image/png',
				purpose: 'maskable',
			},
		],
	}
}

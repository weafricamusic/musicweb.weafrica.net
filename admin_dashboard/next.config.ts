import type { NextConfig } from 'next'
import { fileURLToPath } from 'node:url'

const projectRoot = fileURLToPath(new URL('.', import.meta.url))
const adminLoginDestination = '/auth/login?next=/admin/dashboard'

const nextConfig: NextConfig = {
	// Next.js (Turbopack) may infer an incorrect workspace root if there are
	// multiple lockfiles above this project directory. Pin it to this repo.
	turbopack: {
		root: projectRoot,
	},

	async redirects() {
		return [
			{
				source: '/auth/login',
				destination: '/login',
				permanent: false,
			},
			{
				source: '/artist',
				destination: adminLoginDestination,
				permanent: false,
			},
			{
				source: '/artist/dashboard',
				destination: adminLoginDestination,
				permanent: false,
			},
			{
				source: '/artist/dashboard/overview',
				destination: adminLoginDestination,
				permanent: false,
			},
			{
				source: '/dj',
				destination: adminLoginDestination,
				permanent: false,
			},
			{
				source: '/dj/dashboard',
				destination: adminLoginDestination,
				permanent: false,
			},
			{
				source: '/dj/dashboard/overview',
				destination: adminLoginDestination,
				permanent: false,
			},
		]
	},
}

export default nextConfig

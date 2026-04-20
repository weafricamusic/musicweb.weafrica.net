'use client'

import { useEffect, useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import type { FFmpeg as FFmpegType } from '@ffmpeg/ffmpeg'

type ArtistOption = { id: string; label: string }

const DEFAULT_GENRE_OPTIONS = [
	'R&B',
	'Afrobeats',
	'Amapiano',
	'Hip-Hop',
	'Gospel',
	'Dancehall',
	'Reggae',
	'House',
	'EDM',
	'Pop',
	'Rock',
	'Jazz',
	'Traditional',
	'Other',
] as const

type TaxonomyResponse =
	| { ok: true; genres: unknown; categories?: unknown; source?: unknown }
	| { ok?: false; error?: unknown }

function uniqStrings(values: unknown[]): string[] {
	const out: string[] = []
	const seen = new Set<string>()
	for (const v of values) {
		if (typeof v !== 'string') continue
		const s = v.trim()
		if (!s) continue
		const key = s.toLowerCase()
		if (seen.has(key)) continue
		seen.add(key)
		out.push(s)
	}
	return out
}

const MOOD_OPTIONS = [
	'Love',
	'Romance',
	'Sad',
	'Happy',
	'Party',
	'Chill',
	'Workout',
	'Worship',
	'Praise',
	'Grit',
	'Focus',
	'Other',
] as const

type UploadTrackOk = {
	ok: true
	song_id?: unknown
	public_url?: unknown
	signed_preview_url?: unknown
}

type UploadTrackErr = {
	ok?: false
	error?: unknown
	extra?: unknown
}

type UploadTrackResponse = UploadTrackOk | UploadTrackErr

function asStringOrNull(v: unknown): string | null {
	return typeof v === 'string' && v.trim() ? v : null
}

function asId(v: unknown): string | number | null {
	if (typeof v === 'string' && v.trim()) return v
	if (typeof v === 'number' && Number.isFinite(v)) return v
	return null
}

function formatUploadError(data: UploadTrackErr | null): string {
	const base = asStringOrNull(data?.error) ?? 'Upload failed'
	if (!data?.extra || typeof data.extra !== 'object') return base
	const extra = data.extra as { code?: unknown; used_columns?: unknown }
	const code = asStringOrNull(extra.code)
	const used = Array.isArray(extra.used_columns) ? extra.used_columns.length : null
	if (code && typeof used === 'number') return `${base} (code=${code}, columns=${used})`
	if (code) return `${base} (code=${code})`
	if (typeof used === 'number') return `${base} (columns=${used})`
	return base
}

function clamp01(n: number): number {
	if (!Number.isFinite(n)) return 0
	return Math.max(0, Math.min(1, n))
}

function readProgress(ev: unknown): number | null {
	if (!ev || typeof ev !== 'object') return null
	const v = (ev as { progress?: unknown }).progress
	if (typeof v !== 'number' || !Number.isFinite(v)) return null
	return clamp01(v)
}

let ffmpegSingleton: FFmpegType | null = null
let ffmpegLoadPromise: Promise<FFmpegType> | null = null

async function toBlobURLSafe(toBlobURL: (url: string, mimeType: string) => Promise<string>, url: string, mimeType: string) {
	try {
		return { ok: true as const, value: await toBlobURL(url, mimeType) }
	} catch (e) {
		return { ok: false as const, error: e instanceof Error ? e.message : 'Failed to fetch' }
	}
}

async function loadCoreUrls() {
	const { toBlobURL } = await import('@ffmpeg/util')

	const sources = [
		{
			name: 'jsdelivr',
			core: 'https://cdn.jsdelivr.net/npm/@ffmpeg/core@0.12.6/dist/ffmpeg-core.js',
			wasm: 'https://cdn.jsdelivr.net/npm/@ffmpeg/core@0.12.6/dist/ffmpeg-core.wasm',
		},
		{
			name: 'unpkg',
			core: 'https://unpkg.com/@ffmpeg/core@0.12.6/dist/ffmpeg-core.js',
			wasm: 'https://unpkg.com/@ffmpeg/core@0.12.6/dist/ffmpeg-core.wasm',
		},
	] as const

	let lastError = 'Failed to fetch ffmpeg core'
	for (const s of sources) {
		const coreRes = await toBlobURLSafe(toBlobURL, s.core, 'text/javascript')
		if (!coreRes.ok) {
			lastError = `[${s.name}] core: ${coreRes.error}`
			continue
		}
		const wasmRes = await toBlobURLSafe(toBlobURL, s.wasm, 'application/wasm')
		if (!wasmRes.ok) {
			lastError = `[${s.name}] wasm: ${wasmRes.error}`
			continue
		}
		return { coreURL: coreRes.value, wasmURL: wasmRes.value, source: s.name }
	}

	throw new Error(lastError)
}

async function getFfmpeg(): Promise<FFmpegType> {
	if (ffmpegSingleton) return ffmpegSingleton
	if (ffmpegLoadPromise) return ffmpegLoadPromise

	ffmpegLoadPromise = (async () => {
		const [{ FFmpeg }] = await Promise.all([
			import('@ffmpeg/ffmpeg'),
			import('@ffmpeg/util'),
		])
		const ffmpeg = new FFmpeg()
		// Load core from a CDN to avoid shipping large binaries inside the app bundle.
		// Some networks block certain CDNs; retry a couple sources.
		const urls = await loadCoreUrls()
		await ffmpeg.load({ coreURL: urls.coreURL, wasmURL: urls.wasmURL })

		ffmpegSingleton = ffmpeg
		return ffmpeg
	})()

	return ffmpegLoadPromise
}

async function transcodeToMp3(input: File, onProgress?: (p01: number) => void): Promise<File> {
	const ffmpeg = await getFfmpeg()
	const { fetchFile } = await import('@ffmpeg/util')

	const inName = `input-${Date.now()}`
	const outName = `output-${Date.now()}.mp3`

	const handler = (ev: unknown) => {
		const p = readProgress(ev)
		if (p != null) onProgress?.(p)
	}
	ffmpeg.on('progress', handler)

	try {
		await ffmpeg.writeFile(inName, await fetchFile(input))
		await ffmpeg.exec(['-i', inName, '-vn', '-ar', '44100', '-ac', '2', '-b:a', '128k', outName])
		const data = await ffmpeg.readFile(outName)
		// `@ffmpeg/ffmpeg` may return a Uint8Array backed by a SharedArrayBuffer.
		// Convert to a real ArrayBuffer so it satisfies `BlobPart` typings.
		const bytes =
			data instanceof Uint8Array
				? data
				: typeof data === 'string'
					? new TextEncoder().encode(data)
					: new Uint8Array(data as unknown as ArrayBufferLike)
		const ab = new ArrayBuffer(bytes.byteLength)
		new Uint8Array(ab).set(bytes)
		const blob = new Blob([ab], { type: 'audio/mpeg' })
		const base = input.name.replace(/\.[^/.]+$/u, '') || 'track'
		return new File([blob], `${base}.mp3`, { type: 'audio/mpeg' })
	} finally {
		try {
			await ffmpeg.deleteFile(inName)
		} catch {
			// ignore
		}
		try {
			await ffmpeg.deleteFile(outName)
		} catch {
			// ignore
		}
		ffmpeg.off('progress', handler)
		onProgress?.(1)
	}
}

type Props = {
	artists: ArtistOption[]
}

export default function UploadTrackClient({ artists }: Props) {
	const router = useRouter()
	const [genreOptions, setGenreOptions] = useState<string[]>([...DEFAULT_GENRE_OPTIONS])
	const [artistId, setArtistId] = useState(artists[0]?.id ?? '')
	const [artistName, setArtistName] = useState(artists[0]?.label ?? '')
	const [title, setTitle] = useState('')
	const [genre, setGenre] = useState('')
	const [mood, setMood] = useState('')
	const [tags, setTags] = useState('')
	const [approved, setApproved] = useState(true)
	const [isActive, setIsActive] = useState(true)
	const [file, setFile] = useState<File | null>(null)
	const [localPreviewUrl, setLocalPreviewUrl] = useState<string | null>(null)
	const [compress, setCompress] = useState(true)
	const [fallbackToOriginal, setFallbackToOriginal] = useState(true)
	const [compressing, setCompressing] = useState(false)
	const [compressProgress, setCompressProgress] = useState<number | null>(null)
	const [busy, setBusy] = useState(false)
	const [error, setError] = useState<string | null>(null)
	const [warning, setWarning] = useState<string | null>(null)
	const [result, setResult] = useState<{
		song_id: string | number | null
		public_url: string | null
		signed_preview_url: string | null
	} | null>(null)

	useEffect(() => {
		const selected = artists.find((a) => a.id === artistId)
		if (!selected) return
		// If artistName is empty or still matches previous selection, keep it in sync.
		setArtistName((prev) => {
			const trimmed = prev.trim()
			if (!trimmed) return selected.label
			// If user didn't customize and it's exactly a known label, update it.
			const labelSet = new Set(artists.map((a) => a.label))
			return labelSet.has(trimmed) ? selected.label : prev
		})
	}, [artistId, artists])

	useEffect(() => {
		let cancelled = false
		;(async () => {
			try {
				const res = await fetch('/api/admin/taxonomy', { method: 'GET' })
				if (!res.ok) return
				const data = (await res.json()) as TaxonomyResponse
				if (!data || typeof data !== 'object' || data.ok !== true) return
				const genresRaw = data.genres
				const fromApi = Array.isArray(genresRaw) ? uniqStrings(genresRaw) : []
				if (cancelled) return
				if (fromApi.length) setGenreOptions((prev) => uniqStrings([...prev, ...fromApi]))
			} catch {
				// ignore (fallback is the hardcoded list)
			}
		})()

		return () => {
			cancelled = true
		}
	}, [])

	const canSubmit = useMemo(() => {
		return !!artistId && title.trim().length > 0 && file != null && !busy && !compressing
	}, [artistId, title, file, busy, compressing])

	useEffect(() => {
		// Heuristic defaults: compress if file isn't already MP3 or is very large.
		if (!file) return
		const isMp3 = (file.type === 'audio/mpeg') || file.name.toLowerCase().endsWith('.mp3')
		if (!isMp3) {
			setCompress(true)
			return
		}
		// MP3 can still be huge; allow turning off by user. Default on for > 20MB.
		setCompress(file.size > 20 * 1024 * 1024)
	}, [file])

	useEffect(() => {
		if (!file) {
			setLocalPreviewUrl((prev) => {
				if (prev) URL.revokeObjectURL(prev)
				return null
			})
			return
		}
		const url = URL.createObjectURL(file)
		setLocalPreviewUrl((prev) => {
			if (prev) URL.revokeObjectURL(prev)
			return url
		})
		return () => {
			URL.revokeObjectURL(url)
		}
	}, [file])

	async function onSubmit(e: React.FormEvent) {
		e.preventDefault()
		setError(null)
		setWarning(null)
		setResult(null)
		if (!canSubmit || !file) return

		setBusy(true)
		try {
			let uploadFile = file
			if (compress) {
				setCompressing(true)
				setCompressProgress(0)
				try {
					uploadFile = await transcodeToMp3(file, (p) => setCompressProgress(p))
				} catch (e) {
					const msg = `Compression failed (will ${fallbackToOriginal ? 'upload original instead' : 'stop'}). ${e instanceof Error ? e.message : 'Failed to fetch'}`
					if (!fallbackToOriginal) {
						throw new Error(msg)
					}
					setWarning(msg)
					uploadFile = file
				} finally {
					setCompressing(false)
				}
			}

			const form = new FormData()
			form.set('artist_id', artistId)
			form.set('artist_name', artistName.trim())
			form.set('title', title.trim())
			form.set('genre', genre.trim())
			form.set('mood', mood.trim())
			form.set('tags', tags.trim())
			form.set('approved', String(approved))
			form.set('is_active', String(isActive))
			form.set('audio', uploadFile)

			const res = await fetch('/api/admin/tracks/upload', {
				method: 'POST',
				body: form,
			})
			const raw = (await res.json().catch(() => null)) as unknown
			const data = (raw && typeof raw === 'object' ? (raw as UploadTrackResponse) : null)
			if (!res.ok) {
				setError(formatUploadError(data as UploadTrackErr | null))
				return
			}

			setResult({
				song_id: asId((data as UploadTrackOk | null)?.song_id),
				public_url: asStringOrNull((data as UploadTrackOk | null)?.public_url),
				signed_preview_url: asStringOrNull((data as UploadTrackOk | null)?.signed_preview_url),
			})
			setTitle('')
			setFile(null)
			router.refresh()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Upload failed')
		} finally {
			setBusy(false)
		}
	}

	return (
		<div className="space-y-6">
			<form onSubmit={onSubmit} className="rounded-2xl border border-white/10 bg-white/5 p-6 space-y-4">
				<div>
					<h1 className="text-lg font-semibold">Upload Track (Admin)</h1>
					<p className="mt-1 text-sm text-gray-400">Uploads to Supabase Storage and creates a row in <code className="rounded bg-black/30 px-1">songs</code>.</p>
				</div>

				<div className="grid gap-4 md:grid-cols-2">
					<label className="space-y-1">
						<span className="text-sm text-gray-300">Artist</span>
						<select
							value={artistId}
							onChange={(e) => setArtistId(e.target.value)}
							className="h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm"
						>
							{artists.map((a) => (
								<option key={a.id} value={a.id}>
									{a.label}
								</option>
							))}
						</select>
					</label>

					<label className="space-y-1">
						<span className="text-sm text-gray-300">Artist Name (display)</span>
						<input
							value={artistName}
							onChange={(e) => setArtistName(e.target.value)}
							placeholder="Artist name to store on the song"
							className="h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm"
						/>
					</label>

					<label className="space-y-1">
						<span className="text-sm text-gray-300">Title</span>
						<input
							value={title}
							onChange={(e) => setTitle(e.target.value)}
							placeholder="Song title"
							className="h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm"
						/>
					</label>
				</div>

				<div className="grid gap-4 md:grid-cols-3">
					<label className="space-y-1">
						<span className="text-sm text-gray-300">Genre</span>
						<input
							value={genre}
							onChange={(e) => setGenre(e.target.value)}
							list="genre-options"
							placeholder="e.g. R&B"
							className="h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm"
						/>
					</label>
					<label className="space-y-1">
						<span className="text-sm text-gray-300">Mood</span>
						<input
							value={mood}
							onChange={(e) => setMood(e.target.value)}
							list="mood-options"
							placeholder="e.g. Love"
							className="h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm"
						/>
					</label>
					<label className="space-y-1">
						<span className="text-sm text-gray-300">Tags</span>
						<input
							value={tags}
							onChange={(e) => setTags(e.target.value)}
							placeholder="comma separated (e.g. love, r&b)"
							className="h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm"
						/>
					</label>
				</div>

				<datalist id="genre-options">
					{genreOptions.map((g) => (
						<option key={g} value={g} />
					))}
				</datalist>
				<datalist id="mood-options">
					{MOOD_OPTIONS.map((m) => (
						<option key={m} value={m} />
					))}
				</datalist>

				<label className="space-y-1 block">
					<span className="text-sm text-gray-300">Audio file</span>
					<input
						type="file"
						accept="audio/*"
						onChange={(e) => setFile(e.target.files?.[0] ?? null)}
						className="block w-full text-sm text-gray-300 file:mr-4 file:rounded-lg file:border-0 file:bg-white/10 file:px-3 file:py-2 file:text-sm file:text-white hover:file:bg-white/15"
					/>
					<p className="text-xs text-gray-500">Max 50MB via this route. For larger files, switch to signed uploads.</p>
				</label>

				{localPreviewUrl ? (
					<div className="rounded-xl border border-white/10 bg-black/20 p-3">
						<div className="text-xs font-semibold text-gray-300">Preview (local)</div>
						<audio className="mt-2 w-full" controls preload="metadata" src={localPreviewUrl} />
					</div>
				) : null}

				<div className="flex flex-wrap items-center gap-4">
					<label className="inline-flex items-center gap-2 text-sm text-gray-300">
						<input
							type="checkbox"
							checked={compress}
							onChange={(e) => setCompress(e.target.checked)}
							disabled={busy || compressing}
						/>
						Compress to MP3 (128kbps)
					</label>
					<label className="inline-flex items-center gap-2 text-sm text-gray-300">
						<input
							type="checkbox"
							checked={fallbackToOriginal}
							onChange={(e) => setFallbackToOriginal(e.target.checked)}
							disabled={busy || compressing}
						/>
						If compression fails, upload original
					</label>
					{compressing ? (
						<span className="text-xs text-gray-400">Compressing… {compressProgress != null ? `${Math.round(compressProgress * 100)}%` : ''}</span>
					) : null}
				</div>

				<div className="flex flex-wrap gap-4">
					<label className="inline-flex items-center gap-2 text-sm text-gray-300">
						<input type="checkbox" checked={approved} onChange={(e) => setApproved(e.target.checked)} />
						Approved
					</label>
					<label className="inline-flex items-center gap-2 text-sm text-gray-300">
						<input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />
						Active
					</label>
				</div>

				{error ? (
					<div className="rounded-xl border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-200">{error}</div>
				) : null}
				{warning ? (
					<div className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-amber-100">{warning}</div>
				) : null}

				<button
					type="submit"
					disabled={!canSubmit}
					className="inline-flex h-10 items-center justify-center rounded-xl bg-white px-4 text-sm font-medium text-black disabled:opacity-50"
				>
					{busy ? 'Uploading…' : 'Upload'}
				</button>
			</form>

			{result ? (
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6 space-y-2">
					<div className="text-sm font-semibold">Upload complete</div>
					<div className="text-sm text-gray-300">Song ID: {String(result.song_id ?? '—')}</div>
					{result.public_url ? (
						<>
							<a className="text-sm underline" href={result.public_url} target="_blank" rel="noreferrer">
								Open public URL
							</a>
							<audio className="mt-2 w-full" controls preload="metadata" src={result.public_url} />
						</>
					) : result.signed_preview_url ? (
						<>
							<a className="text-sm underline" href={result.signed_preview_url} target="_blank" rel="noreferrer">
								Open preview (signed)
							</a>
							<audio className="mt-2 w-full" controls preload="metadata" src={result.signed_preview_url} />
						</>
					) : (
						<div className="text-sm text-gray-400">No URL available (bucket may be private).</div>
					)}
				</div>
			) : null}
		</div>
	)
}

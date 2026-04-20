import 'server-only'

import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawn } from 'node:child_process'
import ffmpegStatic from 'ffmpeg-static'

// ffmpeg-static returns a platform-specific absolute path to the ffmpeg binary.
// Types vary by module system, so keep this permissive.
const ffmpegPath: string | null = typeof ffmpegStatic === 'string' ? ffmpegStatic : null

type SpawnResult = { code: number; stdout: string; stderr: string }

async function runFfmpeg(args: string[], timeoutMs: number): Promise<SpawnResult> {
	if (!ffmpegPath) throw new Error('ffmpeg binary not available')

	return await new Promise<SpawnResult>((resolve, reject) => {
		const child = spawn(ffmpegPath, args, { stdio: ['ignore', 'pipe', 'pipe'] })
		let stdout = ''
		let stderr = ''

		const killTimer = setTimeout(() => {
			try {
				child.kill('SIGKILL')
			} catch {
				// ignore
			}
		}, Math.max(1_000, timeoutMs))

		child.stdout.on('data', (d) => (stdout += String(d)))
		child.stderr.on('data', (d) => (stderr += String(d)))

		child.on('error', (err) => {
			clearTimeout(killTimer)
			reject(err)
		})

		child.on('close', (code) => {
			clearTimeout(killTimer)
			resolve({ code: code ?? -1, stdout, stderr })
		})
	})
}

async function withTempDir<T>(fn: (dir: string) => Promise<T>): Promise<T> {
	const dir = await mkdtemp(join(tmpdir(), 'weafrica-media-'))
	try {
		return await fn(dir)
	} finally {
		try {
			await rm(dir, { recursive: true, force: true })
		} catch {
			// ignore
		}
	}
}

export type TranscodeAudioOptions = {
	mp3Bitrate?: string // e.g. '128k', '160k', '192k'
	timeoutMs?: number
}

export async function transcodeAudioToMp3(input: Buffer, opts?: TranscodeAudioOptions): Promise<Buffer> {
	const bitrate = (opts?.mp3Bitrate ?? process.env.AUDIO_MP3_BITRATE ?? '160k').trim() || '160k'
	const timeoutMs = opts?.timeoutMs ?? (Number(process.env.FFMPEG_TIMEOUT_MS ?? '') || 180_000)

	if (!ffmpegPath) return input

	return await withTempDir(async (dir) => {
		const inPath = join(dir, 'in')
		const outPath = join(dir, 'out.mp3')
		await writeFile(inPath, input)

		// Notes:
		// - `-vn` strips any video stream.
		// - `-map_metadata -1` avoids copying huge/odd metadata.
		const args = [
			'-hide_banner',
			'-y',
			'-i',
			inPath,
			'-vn',
			'-map_metadata',
			'-1',
			'-codec:a',
			'libmp3lame',
			'-b:a',
			bitrate,
			'-ar',
			'44100',
			outPath,
		]

		const res = await runFfmpeg(args, timeoutMs)
		if (res.code !== 0) {
			throw new Error(`ffmpeg audio transcode failed (code=${res.code})`) // stderr is noisy; omit by default
		}

		return await readFile(outPath)
	})
}

export type TranscodeVideoOptions = {
	crf?: number // lower = better quality, bigger files
	preset?: string // ultrafast|superfast|veryfast|faster|fast|medium|slow
	maxWidth?: number
	aacBitrate?: string
	timeoutMs?: number
}

export async function transcodeVideoToMp4(input: Buffer, opts?: TranscodeVideoOptions): Promise<Buffer> {
	const crf = Number.isFinite(opts?.crf) ? (opts!.crf as number) : Number(process.env.VIDEO_CRF ?? '') || 28
	const preset = (opts?.preset ?? process.env.VIDEO_PRESET ?? 'veryfast').trim() || 'veryfast'
	const maxWidth = Number.isFinite(opts?.maxWidth)
		? (opts!.maxWidth as number)
		: Number(process.env.VIDEO_MAX_WIDTH ?? '') || 1280
	const aacBitrate = (opts?.aacBitrate ?? process.env.VIDEO_AAC_BITRATE ?? '128k').trim() || '128k'
	const timeoutMs = opts?.timeoutMs ?? (Number(process.env.FFMPEG_TIMEOUT_MS ?? '') || 300_000)

	if (!ffmpegPath) return input

	return await withTempDir(async (dir) => {
		const inPath = join(dir, 'in')
		const outPath = join(dir, 'out.mp4')
		await writeFile(inPath, input)

		// Scale down if needed; keep aspect ratio; ensure even dimensions for H.264.
		const scale = `scale='min(${maxWidth},iw)':-2`

		const args = [
			'-hide_banner',
			'-y',
			'-i',
			inPath,
			'-map_metadata',
			'-1',
			'-vf',
			scale,
			'-codec:v',
			'libx264',
			'-preset',
			preset,
			'-crf',
			String(crf),
			'-pix_fmt',
			'yuv420p',
			'-movflags',
			'+faststart',
			'-codec:a',
			'aac',
			'-b:a',
			aacBitrate,
			outPath,
		]

		const res = await runFfmpeg(args, timeoutMs)
		if (res.code !== 0) {
			throw new Error(`ffmpeg video transcode failed (code=${res.code})`)
		}

		return await readFile(outPath)
	})
}

export type CompressResult = {
	bytes: Buffer
	contentType: string
	ext: string
	transcoded: boolean
}

export async function compressMediaBestEffort(input: { bytes: Buffer; contentType: string; filename: string }): Promise<CompressResult> {
	const disabled = String(process.env.DISABLE_MEDIA_COMPRESSION ?? '').trim() === '1'
	if (disabled) {
		return { bytes: input.bytes, contentType: input.contentType, ext: '', transcoded: false }
	}

	const ct = String(input.contentType || '').toLowerCase()
	const isAudio = ct.startsWith('audio/')
	const isVideo = ct.startsWith('video/')

	// If already in our target formats, skip to avoid quality loss and wasted CPU.
	if (ct === 'audio/mpeg') {
		return { bytes: input.bytes, contentType: 'audio/mpeg', ext: 'mp3', transcoded: false }
	}
	if (ct === 'video/mp4') {
		return { bytes: input.bytes, contentType: 'video/mp4', ext: 'mp4', transcoded: false }
	}

	if (!isAudio && !isVideo) {
		return { bytes: input.bytes, contentType: input.contentType, ext: '', transcoded: false }
	}

	try {
		if (isAudio) {
			const out = await transcodeAudioToMp3(input.bytes)
			return { bytes: out, contentType: 'audio/mpeg', ext: 'mp3', transcoded: true }
		}
		const out = await transcodeVideoToMp4(input.bytes)
		return { bytes: out, contentType: 'video/mp4', ext: 'mp4', transcoded: true }
	} catch {
		// Best-effort: if ffmpeg fails (runtime limitations), just store the original.
		return { bytes: input.bytes, contentType: input.contentType, ext: '', transcoded: false }
	}
}

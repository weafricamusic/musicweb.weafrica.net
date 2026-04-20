import dotenv from 'dotenv';
import { createClient } from '@supabase/supabase-js';

dotenv.config({ path: '.env.local', override: true });

function getEnv(name) {
	const raw = process.env[name];
	if (!raw) return '';
	return String(raw).trim().replace(/^['"]|['"]$/g, '');
}

function getArg(flag) {
	const argv = process.argv.slice(2);
	const eq = argv.find((a) => a.startsWith(`${flag}=`));
	if (eq) return eq.slice(flag.length + 1);
	const i = argv.indexOf(flag);
	if (i >= 0) return argv[i + 1] ?? '';
	return '';
}

function hasFlag(flag) {
	return process.argv.slice(2).includes(flag) || process.argv.slice(2).some((a) => a.startsWith(`${flag}=`));
}

function parseBool(raw, fallback) {
	const v = String(raw ?? '').trim().toLowerCase();
	if (!v) return fallback;
	if (['1', 'true', 'yes', 'y', 'on'].includes(v)) return true;
	if (['0', 'false', 'no', 'n', 'off'].includes(v)) return false;
	return fallback;
}

function jsonOut(data) {
	console.log(JSON.stringify(data, null, 2));
}

const url = getEnv('NEXT_PUBLIC_SUPABASE_URL');
const serviceRoleKey = getEnv('SUPABASE_SERVICE_ROLE_KEY');

if (!url || !serviceRoleKey) {
	jsonOut({
		ok: false,
		error: 'Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY (set them in .env.local).',
	});
	process.exit(1);
}

const djName = (getArg('--dj-name') || getArg('--name') || process.argv[2] || '').trim();
const firebaseUid = (getArg('--firebase-uid') || getArg('--uid') || '').trim() || null;
const userId = (getArg('--user-id') || '').trim() || null;
const id = (getArg('--id') || '').trim() || null;

const approved = parseBool(getArg('--approved'), true);
const status = (getArg('--status') || (approved ? 'active' : 'pending')).trim().toLowerCase();
const blocked = parseBool(getArg('--blocked'), false);
const canGoLive = parseBool(getArg('--can-go-live'), approved && status === 'active' && !blocked);

if (!djName) {
	jsonOut({
		ok: false,
		error: 'Missing DJ name. Usage: node scripts/setup-dj.mjs --dj-name "DJ Tasha"',
		examples: [
			'node scripts/setup-dj.mjs --dj-name "DJ Tasha"',
			'node scripts/setup-dj.mjs --dj-name "DJ Tasha" --firebase-uid <firebase_uid>',
			'node scripts/setup-dj.mjs --id <dj_row_uuid> --status blocked',
		],
	});
	process.exit(1);
}

const supabase = createClient(url, serviceRoleKey, {
	auth: { persistSession: false, autoRefreshToken: false },
});

async function findExisting() {
	if (id) {
		const { data, error } = await supabase.from('djs').select('id').eq('id', id).maybeSingle();
		if (error) throw error;
		return data?.id ? String(data.id) : null;
	}
	if (firebaseUid) {
		const { data, error } = await supabase.from('djs').select('id').eq('firebase_uid', firebaseUid).maybeSingle();
		if (!error && data?.id) return String(data.id);
	}
	if (userId) {
		const { data, error } = await supabase.from('djs').select('id').eq('user_id', userId).maybeSingle();
		if (!error && data?.id) return String(data.id);
	}
	return null;
}

async function upsertDj(existingId) {
	const base = {
		dj_name: djName,
		approved: Boolean(approved),
		status,
		blocked: Boolean(blocked),
		can_go_live: Boolean(canGoLive),
		firebase_uid: firebaseUid,
		user_id: userId,
	};

	const attempts = [
		base,
		(() => {
			const { can_go_live: _a, ...rest } = base;
			return rest;
		})(),
		(() => {
			const { status: _s, blocked: _b, can_go_live: _c, firebase_uid: _f, user_id: _u, ...rest } = base;
			return rest;
		})(),
	];

	let lastError = null;
	for (const payload of attempts) {
		if (existingId) {
			const { data, error } = await supabase
				.from('djs')
				.update(payload)
				.eq('id', existingId)
				.select('*')
				.maybeSingle();
			if (!error) return { mode: 'update', row: data };
			lastError = error;
		} else {
			const { data, error } = await supabase
				.from('djs')
				.insert(payload)
				.select('*')
				.maybeSingle();
			if (!error) return { mode: 'insert', row: data };
			lastError = error;
		}
	}
	throw lastError ?? new Error('Failed to write djs row');
}

try {
	const existingId = await findExisting();
	if (hasFlag('--dry-run')) {
		jsonOut({
			ok: true,
			dry_run: true,
			would_update: Boolean(existingId),
			match: { id: existingId, firebase_uid: firebaseUid, user_id: userId },
		});
		process.exit(0);
	}

	const result = await upsertDj(existingId);
	const djId = result?.row?.id ? String(result.row.id) : existingId;

	jsonOut({
		ok: true,
		mode: result.mode,
		dj: result.row ?? null,
		quick_checks: {
			public_list_api: '/api/djs (filters approved=true,status=active,blocked=false)',
			admin_page: '/admin/djs',
			dashboard_detail: djId ? `/dashboard/djs/${encodeURIComponent(djId)}` : null,
		},
	});
} catch (e) {
	jsonOut({ ok: false, error: String(e?.message ?? e) });
	process.exit(1);
}

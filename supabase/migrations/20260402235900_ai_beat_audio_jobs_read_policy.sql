-- Allow authenticated clients to read usable beat jobs.
-- Root cause fixed: table was configured with deny-all policy + revoked grants.

alter table if exists public.ai_beat_audio_jobs enable row level security;

grant select on table public.ai_beat_audio_jobs to authenticated;

-- Read policy: allow authenticated users to read succeeded jobs
-- (global beat catalog) and their own jobs for status tracking.
do $$
begin
	if not exists (
		select 1
		from pg_policies
		where schemaname = 'public'
			and tablename = 'ai_beat_audio_jobs'
			and policyname = 'authenticated_read_ai_beat_audio_jobs'
	) then
		create policy authenticated_read_ai_beat_audio_jobs
			on public.ai_beat_audio_jobs
			for select
			to authenticated
			using (
				status = 'succeeded'
				or user_id = auth.uid()::text
			);
	end if;
end $$;


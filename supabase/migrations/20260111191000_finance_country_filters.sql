-- Add optional country filters to finance RPCs

-- 1) Top summary filtered by p_country_code (optional)
create or replace function public.finance_top_summary(p_country_code text default null)
returns table (
  total_revenue_mwk numeric(14,2),
  coins_sold bigint,
  artist_earnings_mwk numeric(14,2),
  dj_earnings_mwk numeric(14,2),
  weafrica_commission_mwk numeric(14,2),
  pending_withdrawals_mwk numeric(14,2),
  commission_percent numeric(5,2),
  artist_share_percent numeric(5,2),
  dj_share_percent numeric(5,2)
)
language sql
stable
as $$
  with
    normalized as (
      select nullif(trim(upper(p_country_code)), '') as code
    ),
    revenue as (
      select coalesce(sum(amount_mwk), 0)::numeric(14,2) as total
      from public.transactions t
      where t.type in ('coin_purchase','subscription','ad')
        and (
          (select code from normalized) is null
          or t.country_code = (select code from normalized)
        )
    ),
    coins as (
      select coalesce(sum(coins), 0)::bigint as sold
      from public.transactions t
      where t.type = 'coin_purchase'
        and (
          (select code from normalized) is null
          or t.country_code = (select code from normalized)
        )
    ),
    artist as (
      select coalesce(sum(amount_mwk), 0)::numeric(14,2) as total
      from public.transactions t
      where t.type in ('gift','battle_reward') and t.target_type = 'artist'
        and (
          (select code from normalized) is null
          or t.country_code = (select code from normalized)
        )
    ),
    dj as (
      select coalesce(sum(amount_mwk), 0)::numeric(14,2) as total
      from public.transactions t
      where t.type in ('gift','battle_reward') and t.target_type = 'dj'
        and (
          (select code from normalized) is null
          or t.country_code = (select code from normalized)
        )
    ),
    pending as (
      select coalesce(sum(amount_mwk), 0)::numeric(14,2) as total
      from public.withdrawals w
      where w.status = 'pending'
        and (
          (select code from normalized) is null
          or w.country_code = (select code from normalized)
        )
    ),
    settings as (
      select
        commission_percent,
        artist_share_percent,
        dj_share_percent
      from public.finance_settings
      order by id asc
      limit 1
    )
  select
    revenue.total as total_revenue_mwk,
    coins.sold as coins_sold,
    artist.total as artist_earnings_mwk,
    dj.total as dj_earnings_mwk,
    greatest(revenue.total - artist.total - dj.total, 0)::numeric(14,2) as weafrica_commission_mwk,
    pending.total as pending_withdrawals_mwk,
    coalesce(settings.commission_percent, 30.00) as commission_percent,
    coalesce(settings.artist_share_percent, 50.00) as artist_share_percent,
    coalesce(settings.dj_share_percent, 20.00) as dj_share_percent
  from revenue, coins, artist, dj, pending
  left join settings on true;
$$;
-- 2) Earnings overview filtered by beneficiary type and optional country
create or replace function public.finance_earnings_overview(p_beneficiary_type text, p_country_code text default null)
returns table (
  beneficiary_id text,
  total_coins bigint,
  earned_mwk numeric(14,2),
  withdrawn_mwk numeric(14,2),
  pending_withdrawals_mwk numeric(14,2),
  available_mwk numeric(14,2),
  status text
)
language sql
stable
as $$
  with
    normalized as (
      select nullif(trim(upper(p_country_code)), '') as code
    ),
    earned as (
      select
        t.target_id as beneficiary_id,
        coalesce(sum(t.coins), 0)::bigint as total_coins,
        coalesce(sum(t.amount_mwk), 0)::numeric(14,2) as earned_mwk
      from public.transactions t
      where t.type in ('gift','battle_reward')
        and t.target_type = p_beneficiary_type
        and t.target_id is not null
        and (
          (select code from normalized) is null
          or t.country_code = (select code from normalized)
        )
      group by t.target_id
    ),
    withdrawn as (
      select
        w.beneficiary_id,
        coalesce(sum(w.amount_mwk), 0)::numeric(14,2) as withdrawn_mwk
      from public.withdrawals w
      where w.beneficiary_type = p_beneficiary_type
        and w.status in ('approved','paid')
        and (
          (select code from normalized) is null
          or w.country_code = (select code from normalized)
        )
      group by w.beneficiary_id
    ),
    pending as (
      select
        w.beneficiary_id,
        coalesce(sum(w.amount_mwk), 0)::numeric(14,2) as pending_withdrawals_mwk
      from public.withdrawals w
      where w.beneficiary_type = p_beneficiary_type
        and w.status = 'pending'
        and (
          (select code from normalized) is null
          or w.country_code = (select code from normalized)
        )
      group by w.beneficiary_id
    ),
    freeze_state as (
      select
        s.beneficiary_id,
        s.frozen
      from public.earnings_freeze_state s
      where s.beneficiary_type = p_beneficiary_type
    )
  select
    e.beneficiary_id,
    e.total_coins,
    e.earned_mwk,
    coalesce(w.withdrawn_mwk, 0)::numeric(14,2) as withdrawn_mwk,
    coalesce(p.pending_withdrawals_mwk, 0)::numeric(14,2) as pending_withdrawals_mwk,
    greatest(e.earned_mwk - coalesce(w.withdrawn_mwk, 0) - coalesce(p.pending_withdrawals_mwk, 0), 0)::numeric(14,2) as available_mwk,
    case when coalesce(f.frozen, false) then 'frozen' else 'active' end as status
  from earned e
  left join withdrawn w using (beneficiary_id)
  left join pending p using (beneficiary_id)
  left join freeze_state f using (beneficiary_id)
  order by e.earned_mwk desc;
$$;

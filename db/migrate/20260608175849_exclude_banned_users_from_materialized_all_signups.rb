class ExcludeBannedUsersFromMaterializedAllSignups < ActiveRecord::Migration[8.1]
  # Exclude banned users from the canonical reporting matview. Banning is a
  # property of a `users` row (users.banned), but the matview's grain is one row
  # per normalized email deduplicated across `users` AND `rsvps`. A banned person
  # may therefore surface via an RSVP row even with their user row removed, so we
  # exclude the whole normalized email (the `banned_emails` anti-join in
  # email_rollup) rather than just filtering the users source. This also drops
  # banned people from the assumed-referral-source distribution, since that is
  # derived downstream of email_rollup.
  #
  # Materialized views can't be CREATE OR REPLACE-d, and the prior definition
  # (20260608154500) already ran in production, so we drop and recreate. The only
  # change from that migration is the new `banned_emails` CTE and its anti-join;
  # the Linus-Tech-Tips => AMD mapping is preserved. See 20260608132316 for the
  # full rationale on why this matview lives outside schema.rb.
  def up
    recreate_view!(banned_filtered: true)
  end

  def down
    recreate_view!(banned_filtered: false)
  end

  private

  def recreate_view!(banned_filtered:)
    banned_emails_cte = if banned_filtered
      <<~SQL.strip
        , banned_emails as (
          select distinct lower(trim(email)) as email
          from users
          where banned and nullif(trim(email),'') is not null
        )
      SQL
    else
      ""
    end

    email_rollup_filter = if banned_filtered
      <<~SQL.strip
        where not exists (
          select 1 from banned_emails be where be.email = lower(trim(combined_rows.email))
        )
      SQL
    else
      ""
    end

    safety_assured do
      execute "DROP MATERIALIZED VIEW IF EXISTS materialized_all_signups;"

      execute <<~SQL
        CREATE MATERIALIZED VIEW materialized_all_signups AS
      with users_filtered as (
        select * from users where nullif(trim(email),'') is not null
      )#{banned_emails_cte}, user_ips as (
        select u.id as user_id, ui.ip_address,
               rg.geocoded_country, rg.geocoded_subdivision, rg.geocoded_lat, rg.geocoded_lon
        from users_filtered u
        left join lateral (
          select a.ip_address
          from active_insights_requests a
          where a.started_at between u.created_at - interval '30 seconds'
                                and u.created_at + interval '30 seconds'
            and a.ip_address <> '127.0.0.1'
            and coalesce(a.user_agent,'') not in ('node','curl/7.88.1')
          order by
            case when a.path like '/oauth/callback%' then 0
                 when a.path in ('/onboarding/start','/onboarding/welcome') then 1
                 else 2 end,
            abs(extract(epoch from (a.started_at - u.created_at)))
          limit 1
        ) ui on true
        left join lateral (
          select r.geocoded_country, r.geocoded_subdivision, r.geocoded_lat, r.geocoded_lon
          from rsvps r
          where r.ip_address = ui.ip_address and r.geocoded_country is not null
          order by abs(extract(epoch from (r.created_at - u.created_at)))
          limit 1
        ) rg on true
        where u.geocoded_country is null
      ), user_rows as (
        select 'users'::text as signup_source, u.email, u.created_at, coalesce(nullif(trim(u.ip_address),''), ui.ip_address) as ip_address, u.ref, u.user_ref,
          coalesce(u.geocoded_country, ui.geocoded_country) as geocoded_country,
          coalesce(u.geocoded_subdivision, ui.geocoded_subdivision) as geocoded_subdivision,
          coalesce(u.geocoded_lat, ui.geocoded_lat) as geocoded_lat,
          coalesce(u.geocoded_lon, ui.geocoded_lon) as geocoded_lon,
          case when u.geocoded_country is not null then 'Native user IP geocode.'
               when nullif(trim(u.ip_address),'') is not null then 'User has IP but no geocode.'
               when ui.ip_address is null then 'No user IP found near user creation.'
               when ui.geocoded_country is not null then 'Fallback: user IP derived from ActiveInsights request near user creation; geocode copied from nearest RSVP with same IP.'
               else 'Fallback: user IP derived from ActiveInsights request near user creation; no matching geocoded RSVP IP found.' end as geocode_methodology
        from users_filtered u
        left join user_ips ui on ui.user_id=u.id
      ), combined_rows as (
        select 'rsvps'::text as signup_source, email, created_at, ip_address, geocoded_country, geocoded_subdivision, geocoded_lat, geocoded_lon, ref, user_ref,
          case when geocoded_country is not null then 'Native RSVP IP geocode.' when ip_address is not null then 'RSVP has IP but no geocode.' else 'RSVP has no IP.' end as geocode_methodology
        from rsvps where nullif(trim(email),'') is not null
        union all
        select signup_source,email,created_at,ip_address,geocoded_country,geocoded_subdivision,geocoded_lat,geocoded_lon,ref,user_ref,geocode_methodology from user_rows
      ), email_rollup as (
        select lower(trim(email)) as email,
          min(created_at) as first_seen_at_utc,
          min(((created_at at time zone 'UTC') at time zone 'America/New_York')::date) as first_seen_day_et,
          bool_or(signup_source='rsvps') as seen_in_rsvps,
          bool_or(signup_source='users') as seen_in_users,
          (array_agg(ip_address order by case when ip_address is null then 1 else 0 end, created_at))[1] as ip_address,
          (array_agg(geocoded_country order by case when geocoded_country is null then 1 else 0 end, created_at))[1] as geocoded_country,
          (array_agg(geocoded_subdivision order by case when geocoded_subdivision is null then 1 else 0 end, created_at))[1] as geocoded_subdivision,
          (array_agg(geocoded_lat order by case when geocoded_lat is null then 1 else 0 end, created_at))[1] as geocoded_lat,
          (array_agg(geocoded_lon order by case when geocoded_lon is null then 1 else 0 end, created_at))[1] as geocoded_lon,
          (array_agg(geocode_methodology order by case when geocoded_country is null then 1 else 0 end, created_at))[1] as geocode_methodology,
          (array_agg(nullif(trim(ref),'') order by case when nullif(trim(ref),'') is null then 1 else 0 end, created_at))[1] as first_ref,
          (array_agg(nullif(trim(user_ref),'') order by case when nullif(trim(user_ref),'') is null then 1 else 0 end, created_at))[1] as first_user_ref,
          array_remove(array_agg(distinct nullif(trim(ref),'') order by nullif(trim(ref),'')), null) as raw_refs,
          array_remove(array_agg(distinct nullif(trim(user_ref),'') order by nullif(trim(user_ref),'')), null) as raw_user_refs
        from combined_rows
        #{email_rollup_filter}
        group by 1
      ), base_people as (
        select *, coalesce(first_ref, first_user_ref) as actual_referral_source_raw,
          case when lower(coalesce(first_ref,'')) like 'a-%' then 'stardance_ambassador'
               when lower(coalesce(first_ref,'')) like 'r-%' then 'gpu_raffle'
               when lower(coalesce(first_ref, first_user_ref)) = 'gh-edu' then 'github'
               when lower(coalesce(first_ref, first_user_ref)) = 'linus tech tips' then 'amd'
               else nullif(lower(coalesce(first_ref, first_user_ref)), '') end as direct_referral_source
        from email_rollup
      ), known_counts as (
        select direct_referral_source as source, count(*)::bigint as known_count
        from base_people where direct_referral_source is not null group by 1
      ), source_ranges as (
        select source, known_count,
          coalesce(sum(known_count) over (order by source rows between unbounded preceding and 1 preceding),0)::numeric
            / nullif(sum(known_count) over (), 0)::numeric as start_ratio,
          sum(known_count) over (order by source)::numeric
            / nullif(sum(known_count) over (), 0)::numeric as end_ratio,
          sum(known_count) over ()::bigint as known_total
        from known_counts
      ), assigned as (
        select b.*, r.source as assumed_referral_source, r.known_count::numeric/nullif(r.known_total,0) as assumed_referral_source_rate
        from base_people b
        left join source_ranges r
          on b.direct_referral_source is null
         and ((('x' || substr(md5(b.email),1,15))::bit(60)::bigint)::numeric / 1152921504606846976::numeric) >= r.start_ratio
         and ((('x' || substr(md5(b.email),1,15))::bit(60)::bigint)::numeric / 1152921504606846976::numeric) < r.end_ratio
      ), final_people as (
        select *, coalesce(direct_referral_source, assumed_referral_source, 'Other') as primary_referral_source
        from assigned
      )
      select email, first_seen_at_utc, first_seen_day_et, seen_in_rsvps, seen_in_users, ip_address,
        geocoded_country as country_code,
        case geocoded_country when 'US' then 'United States' when 'IN' then 'India' when 'GB' then 'United Kingdom' when 'UK' then 'United Kingdom' when 'CA' then 'Canada' when 'AU' then 'Australia' when 'NZ' then 'New Zealand' when 'DE' then 'Germany' when 'NL' then 'Netherlands' when 'NP' then 'Nepal' when 'PK' then 'Pakistan' when 'SG' then 'Singapore' when 'FR' then 'France' else coalesce(nullif(trim(geocoded_country),''),'Unknown') end as country,
        geocoded_subdivision as region_code,
        coalesce(nullif(trim(geocoded_subdivision),''),'Unknown') as region,
        geocoded_lat as latitude, geocoded_lon as longitude,
        geocoded_country='US' as is_us,
        geocode_methodology,
        primary_referral_source,
        case when direct_referral_source is not null and first_ref is not null then 'Direct: /ref URL suffix present; ref prioritized over user_ref.'
             when direct_referral_source is not null and first_user_ref is not null then 'Direct: post-sign-up survey user_ref present and no /ref URL suffix.'
             when assumed_referral_source is not null then 'Assumed: no /ref URL suffix and no post-sign-up survey user_ref; row assigned a concrete referral source deterministically according to the known referral-source distribution across all other sign-ups.'
             else 'No attribution signal and no known-source distribution available.' end as primary_referral_methodology,
        coalesce(first_ref, first_user_ref, 'Other') as actual_referral_source,
        case when first_ref is not null then 'ref' when first_user_ref is not null then 'user_ref' when assumed_referral_source is not null then 'assumed' else 'missing' end as actual_referral_source_from,
        lower(coalesce(first_ref,'')) like 'a-%' as is_ambassador_signup,
        lower(coalesce(first_ref,'')) like 'r-%' as is_gpu_raffle_signup,
        assumed_referral_source,
        assumed_referral_source_rate,
        case when primary_referral_source='amd' then 'AMD' else 'Other' end as amd_referral_group,
        case when primary_referral_source='nasa' then 'NASA' else 'Other' end as nasa_referral_group,
        case when primary_referral_source='gpu_raffle' then 'GPU Raffle' else 'Other' end as gpu_raffle_referral_group,
        case
          when primary_referral_source='teacher' then 'teacher'
          when primary_referral_source='amd' then 'amd'
          when primary_referral_source='github' then 'github'
          when primary_referral_source='nasa' then 'nasa'
          when primary_referral_source='stardance_ambassador' then 'stardance_ambassador'
          when primary_referral_source='gpu_raffle' then 'gpu_raffle'
          else 'other'
        end as source_group,
        actual_referral_source_raw as known_referral_source,
        direct_referral_source is null as missing_referral_source,
        raw_refs, raw_user_refs
      from final_people
      WITH DATA;
      SQL

      # Required for REFRESH MATERIALIZED VIEW CONCURRENTLY. The grain is one row
      # per normalized email, so `email` is the natural unique key.
      execute <<~SQL
        CREATE UNIQUE INDEX index_materialized_all_signups_on_email
          ON materialized_all_signups (email);
      SQL

      execute <<~SQL
        COMMENT ON MATERIALIZED VIEW materialized_all_signups IS
          'CANONICAL reporting view of people/signups. One row per normalized email '
          '(lower(trim(email))), deduplicated across public.users and public.rsvps. '
          'Excludes banned users (users.banned) -- a banned person''s normalized '
          'email is dropped entirely, even when it also appears via an RSVP. '
          'Use THIS for all user/signup reporting and attribution. Do NOT query '
          'public.users for reporting -- different grain (one-row-per-account, '
          'excludes RSVP-only people). Includes geocoding (native + fallback '
          'methodology) and referral attribution. NOTE: primary_referral_source is '
          'partly synthetic -- rows with no ref/user_ref get a deterministic '
          'assumed source (see primary_referral_methodology / '
          'actual_referral_source_from to distinguish observed vs assumed). Sign-ups '
          'whose only signal is user_ref = ''Linus Tech Tips'' are credited to AMD '
          '(amd) at the primary_referral_source level, since AMD sponsored that '
          'placement; actual_referral_source still shows the raw observed value. '
          'Materialized; refreshed every 2 minutes via REFRESH MATERIALIZED VIEW '
          'CONCURRENTLY (RefreshMaterializedAllSignupsJob), so data is stale '
          'between refreshes.';
      SQL
    end
  end
end

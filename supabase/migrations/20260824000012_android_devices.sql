-- Android support for push.
--
-- Apple and Google are different services with different credentials, so a
-- device row has to say which one it belongs to. Existing rows are all iPhones.

alter table public.device_tokens
    add column platform text not null default 'ios'
        check (platform in ('ios', 'android'));

-- `environment` (sandbox/production) is an APNs concept. Android has no
-- equivalent, so Google's senders ignore it rather than a nullable column
-- being introduced that means nothing on one platform.
comment on column public.device_tokens.environment is
    'APNs host to use. Ignored for platform = android.';

-- Sending fans out per platform, so this is the access pattern.
create index device_tokens_platform_idx on public.device_tokens (platform);

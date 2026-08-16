-- PostgREST PGRST203: calling list_member_order_alerts with only p_phone
-- cannot choose between 1-arg and 2-arg overloads → Member Inbox returns [].
-- Keep the 2-arg version (p_after default null); drop the thin 1-arg wrapper.

drop function if exists public.list_member_order_alerts(text);

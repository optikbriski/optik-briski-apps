-- AWS Face Liveness metadata on attendance_logs
alter table public.attendance_logs
  add column if not exists liveness_confidence double precision,
  add column if not exists liveness_session_id text,
  add column if not exists liveness_provider text;

comment on column public.attendance_logs.liveness_confidence is
  'Skor confidence Face Liveness (0-100), biasanya dari AWS Rekognition';
comment on column public.attendance_logs.liveness_session_id is
  'SessionId CreateFaceLivenessSession (AWS)';
comment on column public.attendance_logs.liveness_provider is
  'Penyedia liveness: aws | local';

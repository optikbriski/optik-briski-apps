-- AWS Rekognition face id untuk absensi hybrid
alter table public.karyawan
  add column if not exists aws_face_id text;

comment on column public.karyawan.aws_face_id is
  'FaceId dari AWS Rekognition IndexFaces (collection optik-briski-attendance)';

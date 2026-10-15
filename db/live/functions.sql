-- Định nghĩa THẬT (pg_get_functiondef) đọc từ Supabase production, chỉ đọc, ngày 2026-10-15.

CREATE OR REPLACE FUNCTION public.classify_room_building(room_id text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN room_id IS NULL OR room_id = 'N/A' THEN 'Chưa có phòng'
    WHEN room_id ILIKE 'ONLINE%' THEN 'Online'
    WHEN room_id IN ('BIH','BV BINHDUONG') THEN 'Cơ sở thực tập bệnh viện (ngoài trường)'
    WHEN room_id IN ('AMC.A','AMC.A102','AMC.A106') THEN 'Khu nhà xưởng AMC (ngoài trường)'
    WHEN room_id IN ('BKB 1','BMT 1','TEN 1','VLB 1','FB 1') THEN 'Khu thể thao TP mới (ngoài trường)'
    WHEN room_id = 'LIB' THEN 'Thư viện (phòng chức năng đặc biệt, trong trường)'
    WHEN room_id IN ('RAINTREE','BAMBOO','SYCAMORE') THEN 'Tòa B08'
    WHEN room_id ~ '\.B[0-9]+$' THEN 'Tòa ' || substring(room_id FROM '\.([A-Z][0-9]+)$')
    ELSE 'Khác'
  END;
$function$
;


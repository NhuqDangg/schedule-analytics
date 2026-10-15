-- ============================================================
-- TOÀN BỘ VIEW/FUNCTION/BẢNG PHỤC VỤ DASHBOARD (Supabase)
-- Chạy đúng theo thứ tự từ trên xuống (có phụ thuộc giữa các phần).
-- Đây là bản ĐANG CHẠY THẬT trên Supabase của dự án tại thời điểm xuất file này.
-- ============================================================


-- ============================================================
-- PHẦN 1 — TAB TỔNG QUAN
-- ============================================================

CREATE OR REPLACE VIEW v_overview_kpi AS
SELECT
  (SELECT count(DISTINCT instructor_id) FROM fact_schedule WHERE has_instructor) AS so_gv,
  (SELECT count(*) FROM dim_course) AS so_mon,
  (SELECT count(*) FROM dim_room WHERE room_id <> 'N/A') AS so_phong,
  (SELECT round(sum(total_hours)) FROM fact_schedule_day) AS tong_gio,
  (SELECT count(*) FROM dim_section WHERE is_unscheduled) AS nhom_chua_xep_lich;

-- v_hours_by_building dùng hàm classify_room_building() ở PHẦN 3 bên dưới —
-- tạo tạm placeholder ở đây, sẽ CREATE OR REPLACE lại đúng bản cuối ở cuối PHẦN 3.

CREATE OR REPLACE VIEW v_top_instructors AS
SELECT i.instructor_id, i.instructor_name,
       round(sum(d.total_hours), 1) AS total_hours
FROM fact_schedule f
JOIN dim_instructor i USING (instructor_id)
LEFT JOIN fact_schedule_day d USING (schedule_id)
WHERE f.has_instructor
GROUP BY i.instructor_id, i.instructor_name
ORDER BY total_hours DESC;
-- Lưu ý quan trọng: khi gọi qua REST (PostgREST), LUÔN thêm &order=total_hours.desc
-- tường minh trong query string. KHÔNG dựa vào ORDER BY trong view — PostgREST không
-- đảm bảo giữ thứ tự này khi có &limit=, dễ gây bug (từng xảy ra: 1 người có 0 giờ
-- vì NULL bị coalesce sai lọt vào "Top 8" dù không thuộc top thật).


-- ============================================================
-- PHẦN 2 — TAB ĐÁNH GIÁ GIẢNG VIÊN + MODAL LỊCH CÁ NHÂN
-- ============================================================

CREATE OR REPLACE VIEW v_instructor_workload AS
SELECT
  i.instructor_id,
  i.instructor_name,
  count(DISTINCT (f.course_id, f.group_code)) AS so_nhom_lop,
  round(coalesce(sum(d.total_hours),0), 1) AS tong_gio,
  round(coalesce(sum(f.credit_alloc),0), 2) AS tong_tc,
  string_agg(DISTINCT f.course_id, ', ' ORDER BY f.course_id) AS mon_phu_trach,
  (i.instructor_id ~ '^(LIB|OCE|AAO|AMC|BOM|OSA|OIL)') AS is_support_staff,
  CASE
    WHEN i.instructor_id ~ 'FT[0-9]+$' THEN 'FT'
    WHEN i.instructor_id ~ 'PT[0-9]+$' THEN 'PT'
    ELSE 'OTHER'
  END AS employment_type
FROM fact_schedule f
JOIN dim_instructor i USING (instructor_id)
LEFT JOIN fact_schedule_day d USING (schedule_id)
WHERE f.has_instructor
GROUP BY i.instructor_id, i.instructor_name;

CREATE OR REPLACE VIEW v_workload_thresholds_by_group AS
SELECT employment_type,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY so_nhom_lop) AS median_so_nhom,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY tong_gio) AS median_gio,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY tong_tc) AS median_tc,
       count(*) AS so_gv
FROM v_instructor_workload
WHERE NOT is_support_staff
GROUP BY employment_type
UNION ALL
SELECT 'ALL',
       percentile_cont(0.5) WITHIN GROUP (ORDER BY so_nhom_lop),
       percentile_cont(0.5) WITHIN GROUP (ORDER BY tong_gio),
       percentile_cont(0.5) WITHIN GROUP (ORDER BY tong_tc),
       count(*)
FROM v_instructor_workload
WHERE NOT is_support_staff;

CREATE OR REPLACE VIEW v_instructor_sessions AS
SELECT
  f.instructor_id,
  t.session_date,
  t.day_code,
  f.time_slot,
  f.room_id,
  f.course_id,
  f.group_code
FROM fact_schedule f
JOIN fact_teaching_session t USING (schedule_id)
WHERE f.has_instructor;


-- ============================================================
-- PHẦN 3 — TAB PHÒNG & TÒA NHÀ
-- ============================================================

-- Hàm phân loại tòa nhà/địa điểm — nguồn sự thật DUY NHẤT, mọi view liên quan đến
-- phòng/tòa đều gọi hàm này, không viết lại CASE WHEN ở nơi khác.
-- Xác nhận thủ công từ người quản lý lịch (xem PROJECT_CONTEXT.md):
--  - RAINTREE, BAMBOO, SYCAMORE: phòng thật thuộc Tòa B08 (chỉ đặt tên khác số)
--  - LIB: thư viện, TRONG trường nhưng chỉ phục vụ 1 buổi làm quen (môn FEXP 2),
--    không phải phòng học linh hoạt → tách riêng, không tính vào so sánh "Tòa"
--  - AMC.A/A102/A106: khu nhà xưởng nghiên cứu sản xuất tiên tiến, NGOÀI khuôn viên
--  - BKB 1/BMT 1/TEN 1/VLB 1/FB 1: khu thể thao TP mới, NGOÀI khuôn viên
--  - BIH, BV BINHDUONG: 2 bệnh viện thực tập lâm sàng, NGOÀI khuôn viên
CREATE OR REPLACE FUNCTION classify_room_building(room_id TEXT) RETURNS TEXT AS $$
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
$$ LANGUAGE sql IMMUTABLE;

-- Bản CUỐI CÙNG của v_hours_by_building (dùng chung hàm phân loại ở trên,
-- ghi đè bản placeholder ở PHẦN 1)
CREATE OR REPLACE VIEW v_hours_by_building AS
SELECT classify_room_building(f.room_id) AS building,
       round(coalesce(sum(d.total_hours),0), 1) AS total_hours
FROM fact_schedule f
LEFT JOIN fact_schedule_day d USING (schedule_id)
GROUP BY 1
ORDER BY total_hours DESC;

-- Chỉ giữ 5 tòa thật (loại thư viện + mọi nhóm ngoài trường), tính cả phòng
-- CHƯA TỪNG được xếp lịch (0 giờ) nhờ LEFT JOIN từ dim_room, không phải từ fact_schedule.
CREATE OR REPLACE VIEW v_building_summary AS
SELECT classify_room_building(r.room_id) AS building,
       count(DISTINCT r.room_id) AS so_phong,
       round(coalesce(sum(d.total_hours),0), 0) AS tong_gio,
       round(coalesce(sum(d.total_hours),0) / count(DISTINCT r.room_id), 1) AS gio_tb_moi_phong
FROM dim_room r
LEFT JOIN fact_schedule f ON f.room_id = r.room_id
LEFT JOIN fact_schedule_day d ON d.schedule_id = f.schedule_id
WHERE classify_room_building(r.room_id) LIKE 'Tòa %'
GROUP BY 1
ORDER BY gio_tb_moi_phong DESC;

CREATE OR REPLACE VIEW v_room_detail AS
SELECT r.room_id,
       classify_room_building(r.room_id) AS building,
       round(coalesce(sum(d.total_hours),0), 1) AS tong_gio
FROM dim_room r
LEFT JOIN fact_schedule f ON f.room_id = r.room_id
LEFT JOIN fact_schedule_day d ON d.schedule_id = f.schedule_id
WHERE classify_room_building(r.room_id) LIKE 'Tòa %'
GROUP BY r.room_id
ORDER BY tong_gio DESC;

CREATE OR REPLACE VIEW v_offcampus_summary AS
SELECT classify_room_building(f.room_id) AS nhom,
       round(coalesce(sum(d.total_hours),0), 0) AS tong_gio
FROM fact_schedule f
LEFT JOIN fact_schedule_day d USING (schedule_id)
WHERE classify_room_building(f.room_id) NOT LIKE 'Tòa %'
GROUP BY 1
ORDER BY tong_gio DESC;


-- ============================================================
-- PHẦN 4 — TAB XUNG ĐỘT LỊCH (+ dùng chung bởi modal và tab Theo tuần)
-- ============================================================

-- Bảng xác nhận thủ công: cặp (phòng, môn A, môn B) đã được người quản lý xác nhận
-- là dùng chung phòng CÓ CHỦ ĐÍCH (không phải lỗi xếp lịch). course_a/course_b
-- luôn lưu theo thứ tự alphabet (LEAST/GREATEST) để so khớp không phụ thuộc chiều.
CREATE TABLE IF NOT EXISTS room_share_confirmed (
  id SERIAL PRIMARY KEY,
  room_id TEXT NOT NULL,
  course_a TEXT NOT NULL,
  course_b TEXT NOT NULL,
  ly_do TEXT,
  nguoi_xac_nhan TEXT,
  ngay_xac_nhan DATE DEFAULT CURRENT_DATE,
  UNIQUE (room_id, course_a, course_b)
);

-- v_conflicts: nguồn DUY NHẤT tính "thế nào là trùng lịch" cho toàn hệ thống
-- (modal cá nhân, tab Theo tuần, tab Xung đột lịch đều gọi view này, không ai
-- tự tính lại trong JS — tránh 2 nơi lệch nhau, đã từng xảy ra và phải sửa 2 lần).
-- Nguyên tắc cốt lõi: so trùng theo NGÀY DƯƠNG LỊCH THẬT (session_date), KHÔNG
-- phải theo "cùng thứ trong tuần" — vì 2 môn có thể cùng "Thứ Sáu 07:30" nhưng
-- học ở 2 khoảng tuần khác nhau trong kỳ, nên chưa chắc đã thật sự trùng.
CREATE OR REPLACE VIEW v_conflicts AS
WITH ranged AS (
  SELECT
    t.schedule_id, t.session_date, t.week_no,
    f.instructor_id, f.room_id, f.course_id, f.group_code,
    f.time_slot,
    substring(f.time_slot from 1 for 5)::time AS t_start,
    substring(f.time_slot from 7 for 5)::time AS t_end
  FROM fact_teaching_session t
  JOIN fact_schedule f USING (schedule_id)
  WHERE f.time_slot <> '-'
),
gv_conflict AS (
  SELECT a.week_no, a.session_date, 'GV' AS loai,
         a.instructor_id AS key_id, i.instructor_name AS key_name,
         a.course_id AS mon_a, a.group_code AS nhom_a, a.time_slot AS gio_a,
         b.course_id AS mon_b, b.group_code AS nhom_b, b.time_slot AS gio_b,
         false AS da_xac_nhan
  FROM ranged a
  JOIN ranged b ON a.instructor_id = b.instructor_id
    AND a.session_date = b.session_date AND a.schedule_id < b.schedule_id
    AND NOT (a.course_id = b.course_id AND a.group_code = b.group_code)
    AND a.t_start < b.t_end AND b.t_start < a.t_end
  JOIN dim_instructor i ON i.instructor_id = a.instructor_id
  WHERE a.instructor_id IS NOT NULL
),
room_conflict AS (
  SELECT a.week_no, a.session_date, 'Phòng' AS loai,
         a.room_id AS key_id, a.room_id AS key_name,
         a.course_id AS mon_a, a.group_code AS nhom_a, a.time_slot AS gio_a,
         b.course_id AS mon_b, b.group_code AS nhom_b, b.time_slot AS gio_b,
         (rc.id IS NOT NULL) AS da_xac_nhan
  FROM ranged a
  JOIN ranged b ON a.room_id = b.room_id
    AND a.session_date = b.session_date AND a.schedule_id < b.schedule_id
    AND a.course_id <> b.course_id
    AND a.t_start < b.t_end AND b.t_start < a.t_end
  LEFT JOIN room_share_confirmed rc
    ON rc.room_id = a.room_id
    AND rc.course_a = LEAST(a.course_id, b.course_id)
    AND rc.course_b = GREATEST(a.course_id, b.course_id)
  WHERE a.room_id <> 'N/A' AND a.room_id NOT ILIKE 'ONLINE%'
)
SELECT * FROM gv_conflict
UNION ALL
SELECT * FROM room_conflict;

-- 9 cặp đã được xác nhận thủ công là dùng chung có chủ đích (xem PROJECT_CONTEXT.md
-- để biết lý do từng nhóm: thực tập lâm sàng chung bệnh viện, dùng chung thiết bị lab,
-- gộp lớp sinh hoạt định hướng đầu kỳ).
INSERT INTO room_share_confirmed (room_id, course_a, course_b, ly_do, nguoi_xac_nhan) VALUES
('BIH','SNG 309','SNG 421','Thực tập lâm sàng chung bệnh viện','Oriana'),
('BIH','SNG 431','SNG 439','Thực tập lâm sàng chung bệnh viện','Oriana'),
('BIH','SNG 421','SNG 435','Thực tập lâm sàng chung bệnh viện','Oriana'),
('BIH','SNG 416','SNG 439','Thực tập lâm sàng chung bệnh viện','Oriana'),
('BIH','SNG 309','SNG 435','Thực tập lâm sàng chung bệnh viện','Oriana'),
('FABLAB 204.B11','ECE 100','ECE 110','Dùng chung thiết bị lab','Oriana'),
('FABLAB104.B11','ECE 413','ECE 414','Dùng chung thiết bị lab','Oriana'),
('200.B03','ORI 104','ORI 106','Gộp lớp sinh hoạt định hướng đầu kỳ','Oriana'),
('200.B03','ORI 105','ORI 107','Gộp lớp sinh hoạt định hướng đầu kỳ','Oriana')
ON CONFLICT (room_id, course_a, course_b) DO NOTHING;
-- LƯU Ý: ca duy nhất KHÔNG có trong danh sách này mà vẫn được loại tự động là
-- phòng ONLINE* (loại thẳng trong WHERE của room_conflict ở trên, vì phòng ảo
-- không có giới hạn sức chứa vật lý để mà "trùng").


-- ============================================================
-- PHẦN 5 — TAB THEO TUẦN
-- ============================================================

-- Bảng tra cứu nhãn tuần theo đúng lịch CHÍNH THỨC của trường (ảnh "Kế hoạch giảng
-- dạy và học tập năm học 2025-2026"), khóa theo từng học kỳ để sau này thêm HK2/HK3
-- chỉ cần INSERT thêm dòng, không sửa công thức/code. Xem PROJECT_CONTEXT.md mục
-- "Lịch học chính thức" để biết cách tuần nội bộ 1-16 khớp với Ori/Tuần học ra sao.
CREATE TABLE IF NOT EXISTS hoc_ky_week_map (
  hoc_ky TEXT,
  week_no INT,
  nhan_hien_thi TEXT,
  PRIMARY KEY (hoc_ky, week_no)
);

INSERT INTO hoc_ky_week_map (hoc_ky, week_no, nhan_hien_thi) VALUES
('HK1_2025-2026', 1, 'Ori 1'),
('HK1_2025-2026', 2, 'Ori 2'),
('HK1_2025-2026', 3, 'Ori 3'),
('HK1_2025-2026', 4, 'Ori 4'),
('HK1_2025-2026', 5, 'Tuần 1'),
('HK1_2025-2026', 6, 'Tuần 2'),
('HK1_2025-2026', 7, 'Tuần 3'),
('HK1_2025-2026', 8, 'Tuần 4'),
('HK1_2025-2026', 9, 'Tuần 5'),
('HK1_2025-2026', 10, 'Tuần 6'),
('HK1_2025-2026', 11, 'Tuần 7'),
('HK1_2025-2026', 12, 'Tuần 8'),
('HK1_2025-2026', 13, 'Tuần 9'),
('HK1_2025-2026', 14, 'Tuần 10'),
('HK1_2025-2026', 15, 'Tuần 11 (thi)'),
('HK1_2025-2026', 16, 'Tuần 12 (thi)')
ON CONFLICT (hoc_ky, week_no) DO UPDATE SET nhan_hien_thi = EXCLUDED.nhan_hien_thi;

-- Cả 3 view dưới đây đều LOẠI nhân viên hỗ trợ (12 mã LIB/OCE/AAO/AMC/BOM/OSA/OIL)
-- khỏi đếm/xếp hạng giảng viên, và loại phòng đặc biệt/ngoài trường khỏi đếm/xếp
-- hạng phòng — sửa sau khi phát hiện 1 thủ thư từng đứng #1 "Top giảng viên" tuần 2.
CREATE OR REPLACE VIEW v_week_summary AS
SELECT t.week_no,
       round(sum(t.hours),0) AS tong_gio,
       count(DISTINCT f.instructor_id) FILTER (WHERE f.has_instructor AND f.instructor_id !~ '^(LIB|OCE|AAO|AMC|BOM|OSA|OIL)') AS so_gv,
       count(DISTINCT f.room_id) FILTER (WHERE classify_room_building(f.room_id) LIKE 'Tòa %') AS so_phong,
       wm.nhan_hien_thi
FROM fact_teaching_session t
JOIN fact_schedule f USING (schedule_id)
LEFT JOIN hoc_ky_week_map wm ON wm.week_no = t.week_no AND wm.hoc_ky = 'HK1_2025-2026'
GROUP BY t.week_no, wm.nhan_hien_thi
ORDER BY t.week_no;

CREATE OR REPLACE VIEW v_week_room_hours AS
SELECT t.week_no, f.room_id, round(sum(t.hours),1) AS hours
FROM fact_teaching_session t
JOIN fact_schedule f USING (schedule_id)
WHERE classify_room_building(f.room_id) LIKE 'Tòa %'
GROUP BY t.week_no, f.room_id;

CREATE OR REPLACE VIEW v_week_instructor_hours AS
SELECT t.week_no, f.instructor_id, i.instructor_name, round(sum(t.hours),1) AS hours
FROM fact_teaching_session t
JOIN fact_schedule f USING (schedule_id)
JOIN dim_instructor i USING (instructor_id)
WHERE f.has_instructor AND f.instructor_id !~ '^(LIB|OCE|AAO|AMC|BOM|OSA|OIL)'
GROUP BY t.week_no, f.instructor_id, i.instructor_name;


-- ============================================================
-- PHẦN 6 — QUYỀN TRUY CẬP (bắt buộc, nếu không FE sẽ lỗi 401/permission denied)
-- ============================================================
GRANT SELECT ON
  v_overview_kpi, v_hours_by_building, v_top_instructors,
  v_instructor_workload, v_workload_thresholds_by_group, v_instructor_sessions,
  v_building_summary, v_room_detail, v_offcampus_summary,
  room_share_confirmed, v_conflicts,
  hoc_ky_week_map, v_week_summary, v_week_room_hours, v_week_instructor_hours
TO anon, authenticated;

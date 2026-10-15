-- Định nghĩa THẬT (pg_get_viewdef) đọc từ Supabase production, chỉ đọc, ngày 2026-10-15.
-- Sắp theo tên (không theo thứ tự phụ thuộc — xem dependencies.txt). Tham chiếu, KHÔNG chạy file này.

CREATE OR REPLACE VIEW v_building_summary AS
 SELECT classify_room_building(r.room_id::text) AS building,
    count(DISTINCT r.room_id) AS so_phong,
    round(COALESCE(sum(d.total_hours), 0::numeric), 0) AS tong_gio,
    round(COALESCE(sum(d.total_hours), 0::numeric) / count(DISTINCT r.room_id)::numeric, 1) AS gio_tb_moi_phong
   FROM dim_room r
     LEFT JOIN fact_schedule f ON f.room_id::text = r.room_id::text
     LEFT JOIN fact_schedule_day d ON d.schedule_id = f.schedule_id
  WHERE classify_room_building(r.room_id::text) ~~ 'Tòa %'::text
  GROUP BY (classify_room_building(r.room_id::text))
  ORDER BY (round(COALESCE(sum(d.total_hours), 0::numeric) / count(DISTINCT r.room_id)::numeric, 1)) DESC;

CREATE OR REPLACE VIEW v_conflicts AS
 WITH ranged AS (
         SELECT t.schedule_id,
            t.session_date,
            t.week_no,
            f.instructor_id,
            f.room_id,
            f.course_id,
            f.group_code,
            f.time_slot,
            SUBSTRING(f.time_slot FROM 1 FOR 5)::time without time zone AS t_start,
            SUBSTRING(f.time_slot FROM 7 FOR 5)::time without time zone AS t_end
           FROM fact_teaching_session t
             JOIN fact_schedule f USING (schedule_id)
          WHERE f.time_slot::text <> '-'::text
        ), gv_conflict AS (
         SELECT a.week_no,
            a.session_date,
            'GV'::text AS loai,
            a.instructor_id AS key_id,
            i.instructor_name AS key_name,
            a.course_id AS mon_a,
            a.group_code AS nhom_a,
            a.time_slot AS gio_a,
            b.course_id AS mon_b,
            b.group_code AS nhom_b,
            b.time_slot AS gio_b,
            false AS da_xac_nhan
           FROM ranged a
             JOIN ranged b ON a.instructor_id::text = b.instructor_id::text AND a.session_date = b.session_date AND a.schedule_id < b.schedule_id AND NOT (a.course_id::text = b.course_id::text AND a.group_code::text = b.group_code::text) AND a.t_start < b.t_end AND b.t_start < a.t_end
             JOIN dim_instructor i ON i.instructor_id::text = a.instructor_id::text
          WHERE a.instructor_id IS NOT NULL
        ), room_conflict AS (
         SELECT a.week_no,
            a.session_date,
            'Phòng'::text AS loai,
            a.room_id AS key_id,
            a.room_id AS key_name,
            a.course_id AS mon_a,
            a.group_code AS nhom_a,
            a.time_slot AS gio_a,
            b.course_id AS mon_b,
            b.group_code AS nhom_b,
            b.time_slot AS gio_b,
            rc.id IS NOT NULL AS da_xac_nhan
           FROM ranged a
             JOIN ranged b ON a.room_id::text = b.room_id::text AND a.session_date = b.session_date AND a.schedule_id < b.schedule_id AND a.course_id::text <> b.course_id::text AND a.t_start < b.t_end AND b.t_start < a.t_end
             LEFT JOIN room_share_confirmed rc ON rc.room_id = a.room_id::text AND rc.course_a = LEAST(a.course_id, b.course_id)::text AND rc.course_b = GREATEST(a.course_id, b.course_id)::text
          WHERE a.room_id::text <> 'N/A'::text AND a.room_id::text !~~* 'ONLINE%'::text
        )
 SELECT gv_conflict.week_no,
    gv_conflict.session_date,
    gv_conflict.loai,
    gv_conflict.key_id,
    gv_conflict.key_name,
    gv_conflict.mon_a,
    gv_conflict.nhom_a,
    gv_conflict.gio_a,
    gv_conflict.mon_b,
    gv_conflict.nhom_b,
    gv_conflict.gio_b,
    gv_conflict.da_xac_nhan
   FROM gv_conflict
UNION ALL
 SELECT room_conflict.week_no,
    room_conflict.session_date,
    room_conflict.loai,
    room_conflict.key_id,
    room_conflict.key_name,
    room_conflict.mon_a,
    room_conflict.nhom_a,
    room_conflict.gio_a,
    room_conflict.mon_b,
    room_conflict.nhom_b,
    room_conflict.gio_b,
    room_conflict.da_xac_nhan
   FROM room_conflict;

CREATE OR REPLACE VIEW v_hours_by_building AS
 SELECT classify_room_building(f.room_id::text) AS building,
    round(COALESCE(sum(d.total_hours), 0::numeric), 1) AS total_hours
   FROM fact_schedule f
     LEFT JOIN fact_schedule_day d USING (schedule_id)
  GROUP BY (classify_room_building(f.room_id::text))
  ORDER BY (round(COALESCE(sum(d.total_hours), 0::numeric), 1)) DESC;

CREATE OR REPLACE VIEW v_instructor_sessions AS
 SELECT f.instructor_id,
    t.session_date,
    t.day_code,
    f.time_slot,
    f.room_id,
    f.course_id,
    f.group_code
   FROM fact_schedule f
     JOIN fact_teaching_session t USING (schedule_id)
  WHERE f.has_instructor;

CREATE OR REPLACE VIEW v_instructor_workload AS
 SELECT i.instructor_id,
    i.instructor_name,
    count(DISTINCT ROW(f.course_id, f.group_code)) AS so_nhom_lop,
    round(COALESCE(sum(d.total_hours), 0::numeric), 1) AS tong_gio,
    round(COALESCE(sum(f.credit_alloc), 0::numeric), 2) AS tong_tc,
    string_agg(DISTINCT f.course_id::text, ', '::text ORDER BY (f.course_id::text)) AS mon_phu_trach,
    i.instructor_id::text ~ '^(LIB|OCE|AAO|AMC|BOM|OSA|OIL)'::text AS is_support_staff,
        CASE
            WHEN i.instructor_id::text ~ 'FT[0-9]+$'::text THEN 'FT'::text
            WHEN i.instructor_id::text ~ 'PT[0-9]+$'::text THEN 'PT'::text
            ELSE 'OTHER'::text
        END AS employment_type
   FROM fact_schedule f
     JOIN dim_instructor i USING (instructor_id)
     LEFT JOIN fact_schedule_day d USING (schedule_id)
  WHERE f.has_instructor
  GROUP BY i.instructor_id, i.instructor_name;

CREATE OR REPLACE VIEW v_offcampus_summary AS
 SELECT classify_room_building(f.room_id::text) AS nhom,
    round(COALESCE(sum(d.total_hours), 0::numeric), 0) AS tong_gio
   FROM fact_schedule f
     LEFT JOIN fact_schedule_day d USING (schedule_id)
  WHERE classify_room_building(f.room_id::text) !~~ 'Tòa %'::text
  GROUP BY (classify_room_building(f.room_id::text))
  ORDER BY (round(COALESCE(sum(d.total_hours), 0::numeric), 0)) DESC;

CREATE OR REPLACE VIEW v_overview_kpi AS
 SELECT ( SELECT count(DISTINCT fact_schedule.instructor_id) AS count
           FROM fact_schedule
          WHERE fact_schedule.has_instructor) AS so_gv,
    ( SELECT count(*) AS count
           FROM dim_course) AS so_mon,
    ( SELECT count(*) AS count
           FROM dim_room
          WHERE dim_room.room_id::text <> 'N/A'::text) AS so_phong,
    ( SELECT round(sum(fact_schedule_day.total_hours)) AS round
           FROM fact_schedule_day) AS tong_gio,
    ( SELECT count(*) AS count
           FROM dim_section
          WHERE dim_section.is_unscheduled) AS nhom_chua_xep_lich;

CREATE OR REPLACE VIEW v_room_detail AS
 SELECT r.room_id,
    classify_room_building(r.room_id::text) AS building,
    round(COALESCE(sum(d.total_hours), 0::numeric), 1) AS tong_gio
   FROM dim_room r
     LEFT JOIN fact_schedule f ON f.room_id::text = r.room_id::text
     LEFT JOIN fact_schedule_day d ON d.schedule_id = f.schedule_id
  WHERE classify_room_building(r.room_id::text) ~~ 'Tòa %'::text
  GROUP BY r.room_id
  ORDER BY (round(COALESCE(sum(d.total_hours), 0::numeric), 1)) DESC;

CREATE OR REPLACE VIEW v_top_instructors AS
 SELECT i.instructor_id,
    i.instructor_name,
    round(COALESCE(sum(d.total_hours), 0::numeric), 1) AS total_hours
   FROM fact_schedule f
     JOIN dim_instructor i USING (instructor_id)
     LEFT JOIN fact_schedule_day d USING (schedule_id)
  WHERE f.has_instructor
  GROUP BY i.instructor_id, i.instructor_name
  ORDER BY (round(COALESCE(sum(d.total_hours), 0::numeric), 1)) DESC;

CREATE OR REPLACE VIEW v_week_instructor_hours AS
 SELECT t.week_no,
    f.instructor_id,
    i.instructor_name,
    round(sum(t.hours), 1) AS hours
   FROM fact_teaching_session t
     JOIN fact_schedule f USING (schedule_id)
     JOIN dim_instructor i USING (instructor_id)
  WHERE f.has_instructor AND f.instructor_id::text !~ '^(LIB|OCE|AAO|AMC|BOM|OSA|OIL)'::text
  GROUP BY t.week_no, f.instructor_id, i.instructor_name;

CREATE OR REPLACE VIEW v_week_room_hours AS
 SELECT t.week_no,
    f.room_id,
    round(sum(t.hours), 1) AS hours
   FROM fact_teaching_session t
     JOIN fact_schedule f USING (schedule_id)
  WHERE classify_room_building(f.room_id::text) ~~ 'Tòa %'::text
  GROUP BY t.week_no, f.room_id;

CREATE OR REPLACE VIEW v_week_summary AS
 SELECT t.week_no,
    round(sum(t.hours), 0) AS tong_gio,
    count(DISTINCT f.instructor_id) FILTER (WHERE f.has_instructor AND f.instructor_id::text !~ '^(LIB|OCE|AAO|AMC|BOM|OSA|OIL)'::text) AS so_gv,
    count(DISTINCT f.room_id) FILTER (WHERE classify_room_building(f.room_id::text) ~~ 'Tòa %'::text) AS so_phong,
    wm.nhan_hien_thi
   FROM fact_teaching_session t
     JOIN fact_schedule f USING (schedule_id)
     LEFT JOIN hoc_ky_week_map wm ON wm.week_no = t.week_no AND wm.hoc_ky = 'HK1_2025-2026'::text
  GROUP BY t.week_no, wm.nhan_hien_thi
  ORDER BY t.week_no;

CREATE OR REPLACE VIEW v_workload_thresholds_by_group AS
 SELECT v_instructor_workload.employment_type,
    percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (v_instructor_workload.so_nhom_lop::double precision)) AS median_so_nhom,
    percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (v_instructor_workload.tong_gio::double precision)) AS median_gio,
    percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (v_instructor_workload.tong_tc::double precision)) AS median_tc,
    count(*) AS so_gv
   FROM v_instructor_workload
  WHERE NOT v_instructor_workload.is_support_staff
  GROUP BY v_instructor_workload.employment_type
UNION ALL
 SELECT 'ALL'::text AS employment_type,
    percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (v_instructor_workload.so_nhom_lop::double precision)) AS median_so_nhom,
    percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (v_instructor_workload.tong_gio::double precision)) AS median_gio,
    percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (v_instructor_workload.tong_tc::double precision)) AS median_tc,
    count(*) AS so_gv
   FROM v_instructor_workload
  WHERE NOT v_instructor_workload.is_support_staff;

CREATE MATERIALIZED VIEW mv_lecturer_workload AS
 SELECT i.instructor_id,
    i.instructor_name,
    count(DISTINCT ROW(f.course_id, f.group_code)) AS so_nhom_lop,
    sum(d.total_hours) AS tong_gio,
    sum(f.credit_alloc) AS tong_tin_chi
   FROM fact_schedule f
     JOIN dim_instructor i USING (instructor_id)
     LEFT JOIN fact_schedule_day d USING (schedule_id)
  GROUP BY i.instructor_id, i.instructor_name;


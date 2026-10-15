-- ============================================================
-- SCHEMA GỐC (12 bảng) — PostgreSQL star schema cho timetable EIU học kỳ 251
-- Tái tạo lại từ thiết kế đã chốt (ETL Python + pandas, không lưu sẵn file .sql gốc).
-- Đây là bản tham chiếu; nguồn xác thực thật là database Supabase đang chạy.
-- Mọi lỗi dữ liệu gốc (xem PROJECT_CONTEXT.md mục "8 lỗi đã sửa") đã được xử lý
-- TRƯỚC khi nạp vào các bảng dưới đây — tức dữ liệu trong bảng đã sạch.
-- ============================================================

-- ---------- DIMENSION ----------
CREATE TABLE dim_instructor (
    instructor_id VARCHAR(50) PRIMARY KEY,
    instructor_name VARCHAR(255)
);

CREATE TABLE dim_course (
    course_id VARCHAR(50) PRIMARY KEY,
    course_name_vi VARCHAR(255),
    course_name_en VARCHAR(255),
    credits NUMERIC,
    course_category VARCHAR(100)
);

CREATE TABLE dim_faculty (
    faculty_id VARCHAR(10) PRIMARY KEY,   -- '01','02'... — VARCHAR, KHÔNG phải NUMERIC (lỗi #5 đã sửa)
    faculty_name VARCHAR(255)
);

CREATE TABLE dim_major (
    major_id VARCHAR(20) PRIMARY KEY,     -- gồm cả 'GENED','99'
    major_name VARCHAR(255)
);

CREATE TABLE dim_room (
    room_id VARCHAR(50) PRIMARY KEY       -- bao gồm cả 'N/A' = chưa gán phòng
);

CREATE TABLE dim_class (
    class_code VARCHAR(50) PRIMARY KEY    -- đã tách khỏi ô gộp nhiều lớp (1NF, lỗi dữ liệu gốc)
);

-- dim_week ĐÚNG (16 tuần thật, khác hẳn bản nháp cũ 65 dòng khoảng-ngày/bitmask — lỗi #6 đã sửa)
CREATE TABLE dim_week (
    week_no SMALLINT PRIMARY KEY,         -- 1..16
    start_date DATE,                      -- luôn là Thứ 2
    end_date DATE                         -- luôn là Thứ 7
);

CREATE TABLE dim_section (
    course_id VARCHAR(50),
    group_code VARCHAR(10),               -- tách khỏi tổ thực hành (lỗi #4 đã sửa)
    credits NUMERIC,
    total_hours NUMERIC,
    is_unscheduled BOOLEAN,               -- TRUE nếu có TC nhưng total_hours = 0
    PRIMARY KEY (course_id, group_code)
);

-- ---------- FACT ----------
-- Grain: 1 dòng Excel gốc
CREATE TABLE fact_schedule (
    schedule_id INT PRIMARY KEY,
    course_id VARCHAR(50) REFERENCES dim_course(course_id),
    group_code VARCHAR(10),
    faculty_id VARCHAR(10) REFERENCES dim_faculty(faculty_id),
    major_id VARCHAR(20) REFERENCES dim_major(major_id),
    instructor_id VARCHAR(50) REFERENCES dim_instructor(instructor_id),
    room_id VARCHAR(50) REFERENCES dim_room(room_id),
    day_pattern VARCHAR(20),              -- chuỗi thứ gốc, vd 'TR', 'U'
    time_slot VARCHAR(20),                -- 'HH:MM-HH:MM' hoặc '-'
    week_range TEXT,                      -- mô tả khoảng ngày (text, không phải FK)
    week_pattern CHAR(16),                -- bitmask 16 ký tự, vị trí = tuần
    reg_limit INT,
    reg_count INT,
    group_size INT,
    combo_code VARCHAR(20),               -- Tổ TH gốc
    combo_seq VARCHAR(50),
    has_instructor BOOLEAN,
    has_room BOOLEAN,
    is_scheduled BOOLEAN,                 -- TRUE nếu giờ×ngày×tuần > 0 (lỗi #7 đã sửa, KHÔNG dùng 'U' làm 1 thứ)
    so_gio_1_buoi NUMERIC,
    so_tuan INT,
    credits NUMERIC,
    credit_alloc NUMERIC,                 -- TC quy đổi = credits × (giờ dòng này / tổng giờ cả nhóm lớp)
    FOREIGN KEY (course_id, group_code) REFERENCES dim_section(course_id, group_code)
);

-- Grain: 1 dòng gốc × 1 thứ
CREATE TABLE fact_schedule_day (
    schedule_id INT REFERENCES fact_schedule(schedule_id),
    day_code CHAR(1),                     -- M T W R F S (không có 'U')
    so_gio_1_buoi NUMERIC,
    number_of_weeks INT,
    total_hours NUMERIC,
    PRIMARY KEY (schedule_id, day_code)
);

-- Grain: 1 dòng gốc × 1 thứ × 1 tuần — mức chi tiết nhất, có ngày dương lịch thật
CREATE TABLE fact_teaching_session (
    schedule_id INT REFERENCES fact_schedule(schedule_id),
    day_code CHAR(1),
    week_no SMALLINT REFERENCES dim_week(week_no),
    session_date DATE,
    hours NUMERIC,
    PRIMARY KEY (schedule_id, day_code, week_no)
);

-- ---------- BRIDGE ----------
CREATE TABLE bridge_class_schedule (
    schedule_id INT REFERENCES fact_schedule(schedule_id),
    class_code VARCHAR(50) REFERENCES dim_class(class_code),
    PRIMARY KEY (schedule_id, class_code)
);

-- ---------- MATERIALIZED VIEW gốc (từ phiên thiết kế schema ban đầu) ----------
CREATE MATERIALIZED VIEW mv_lecturer_workload AS
SELECT i.instructor_id, i.instructor_name,
       count(DISTINCT (f.course_id, f.group_code)) AS so_nhom_lop,
       sum(d.total_hours) AS tong_gio,
       sum(f.credit_alloc) AS tong_tin_chi
FROM fact_schedule f
JOIN dim_instructor i USING (instructor_id)
LEFT JOIN fact_schedule_day d USING (schedule_id)
WHERE f.has_instructor
GROUP BY i.instructor_id, i.instructor_name;
-- Lưu ý: dashboard web (phần dưới) dùng trực tiếp view/bảng, KHÔNG dùng mv này.
-- Giữ lại vì đã tạo ở phiên thiết kế gốc, có thể refresh sau mỗi lần ETL nếu cần dùng.

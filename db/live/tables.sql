-- Định nghĩa THẬT đọc từ Supabase production (project turtugkqxwgxljvjkgbe), chỉ đọc, ngày 2026-10-15.
-- Tái tạo từ pg_catalog (cột theo đúng thứ tự attnum). Tham chiếu, KHÔNG chạy file này.

CREATE TABLE bridge_class_schedule (
    schedule_id integer NOT NULL,
    class_code character varying(20) NOT NULL
);
ALTER TABLE bridge_class_schedule ADD CONSTRAINT bridge_class_schedule_pkey PRIMARY KEY (schedule_id, class_code);
ALTER TABLE bridge_class_schedule ADD CONSTRAINT bridge_class_schedule_class_code_fkey FOREIGN KEY (class_code) REFERENCES dim_class(class_code);
ALTER TABLE bridge_class_schedule ADD CONSTRAINT bridge_class_schedule_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES fact_schedule(schedule_id) ON DELETE CASCADE;
CREATE INDEX ix_bcs_class ON public.bridge_class_schedule USING btree (class_code);

CREATE TABLE dim_class (
    class_code character varying(20) NOT NULL
);
ALTER TABLE dim_class ADD CONSTRAINT dim_class_pkey PRIMARY KEY (class_code);

CREATE TABLE dim_course (
    course_id character varying(20) NOT NULL,
    course_name_vi character varying(255) NOT NULL,
    course_name_en character varying(255),
    credits smallint NOT NULL,
    course_category character varying(100)
);
ALTER TABLE dim_course ADD CONSTRAINT dim_course_pkey PRIMARY KEY (course_id);
ALTER TABLE dim_course ADD CONSTRAINT dim_course_credits_check CHECK ((credits >= 0));

CREATE TABLE dim_faculty (
    faculty_id character varying(5) NOT NULL,
    faculty_name character varying(255) NOT NULL
);
ALTER TABLE dim_faculty ADD CONSTRAINT dim_faculty_pkey PRIMARY KEY (faculty_id);

CREATE TABLE dim_instructor (
    instructor_id character varying(20) NOT NULL,
    instructor_name character varying(255) NOT NULL
);
ALTER TABLE dim_instructor ADD CONSTRAINT dim_instructor_pkey PRIMARY KEY (instructor_id);

CREATE TABLE dim_major (
    major_id character varying(10) NOT NULL,
    major_name character varying(255) NOT NULL
);
ALTER TABLE dim_major ADD CONSTRAINT dim_major_pkey PRIMARY KEY (major_id);

CREATE TABLE dim_room (
    room_id character varying(30) NOT NULL
);
ALTER TABLE dim_room ADD CONSTRAINT dim_room_pkey PRIMARY KEY (room_id);

CREATE TABLE dim_section (
    course_id character varying(20) NOT NULL,
    group_code character varying(10) NOT NULL,
    credits smallint,
    total_hours numeric(7,2),
    is_unscheduled boolean NOT NULL DEFAULT false,
    section_id integer NOT NULL DEFAULT nextval('dim_section_section_id_seq'::regclass)
);
ALTER TABLE dim_section ADD CONSTRAINT uq_section UNIQUE (course_id, group_code);
ALTER TABLE dim_section ADD CONSTRAINT uq_section_id UNIQUE (section_id);
ALTER TABLE dim_section ADD CONSTRAINT dim_section_pkey PRIMARY KEY (course_id, group_code);
ALTER TABLE dim_section ADD CONSTRAINT dim_section_course_id_fkey FOREIGN KEY (course_id) REFERENCES dim_course(course_id);

CREATE TABLE dim_week (
    week_no smallint NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL
);
ALTER TABLE dim_week ADD CONSTRAINT dim_week_pkey PRIMARY KEY (week_no);
ALTER TABLE dim_week ADD CONSTRAINT dim_week_week_no_check CHECK (((week_no >= 1) AND (week_no <= 16)));

CREATE TABLE fact_schedule (
    schedule_id integer NOT NULL,
    course_id character varying(20) NOT NULL,
    group_code character varying(10) NOT NULL,
    faculty_id character varying(5) NOT NULL,
    major_id character varying(10) NOT NULL,
    instructor_id character varying(20),
    room_id character varying(30),
    day_pattern character varying(7),
    time_slot character varying(20),
    week_range text,
    week_pattern character(16),
    reg_limit integer,
    reg_count integer,
    group_size integer,
    combo_code character varying(10),
    combo_seq character varying(10),
    has_instructor boolean NOT NULL,
    has_room boolean NOT NULL,
    is_scheduled boolean NOT NULL,
    so_gio_1_buoi numeric(4,2) NOT NULL,
    so_tuan smallint NOT NULL,
    credits smallint,
    credit_alloc numeric(8,4) NOT NULL DEFAULT 0,
    section_id integer NOT NULL
);
ALTER TABLE fact_schedule ADD CONSTRAINT fact_schedule_pkey PRIMARY KEY (schedule_id);
ALTER TABLE fact_schedule ADD CONSTRAINT fact_schedule_course_id_group_code_fkey FOREIGN KEY (course_id, group_code) REFERENCES dim_section(course_id, group_code);
ALTER TABLE fact_schedule ADD CONSTRAINT fact_schedule_faculty_id_fkey FOREIGN KEY (faculty_id) REFERENCES dim_faculty(faculty_id);
ALTER TABLE fact_schedule ADD CONSTRAINT fact_schedule_instructor_id_fkey FOREIGN KEY (instructor_id) REFERENCES dim_instructor(instructor_id);
ALTER TABLE fact_schedule ADD CONSTRAINT fact_schedule_major_id_fkey FOREIGN KEY (major_id) REFERENCES dim_major(major_id);
ALTER TABLE fact_schedule ADD CONSTRAINT fact_schedule_room_id_fkey FOREIGN KEY (room_id) REFERENCES dim_room(room_id);
ALTER TABLE fact_schedule ADD CONSTRAINT fk_fs_section FOREIGN KEY (section_id) REFERENCES dim_section(section_id);
CREATE INDEX ix_fs_room ON public.fact_schedule USING btree (room_id);
CREATE INDEX ix_fs_instructor ON public.fact_schedule USING btree (instructor_id);
CREATE INDEX ix_fs_section ON public.fact_schedule USING btree (course_id, group_code);

CREATE TABLE fact_schedule_day (
    schedule_id integer NOT NULL,
    day_code character(1) NOT NULL,
    so_gio_1_buoi numeric(4,2) NOT NULL,
    number_of_weeks smallint NOT NULL,
    total_hours numeric(6,2) NOT NULL
);
ALTER TABLE fact_schedule_day ADD CONSTRAINT fact_schedule_day_pkey PRIMARY KEY (schedule_id, day_code);
ALTER TABLE fact_schedule_day ADD CONSTRAINT fact_schedule_day_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES fact_schedule(schedule_id) ON DELETE CASCADE;
ALTER TABLE fact_schedule_day ADD CONSTRAINT fact_schedule_day_day_code_check CHECK ((day_code = ANY (ARRAY['M'::bpchar, 'T'::bpchar, 'W'::bpchar, 'R'::bpchar, 'F'::bpchar, 'S'::bpchar])));

CREATE TABLE fact_teaching_session (
    schedule_id integer NOT NULL,
    day_code character(1) NOT NULL,
    week_no smallint NOT NULL,
    session_date date NOT NULL,
    hours numeric(4,2) NOT NULL
);
ALTER TABLE fact_teaching_session ADD CONSTRAINT fact_teaching_session_pkey PRIMARY KEY (schedule_id, day_code, week_no);
ALTER TABLE fact_teaching_session ADD CONSTRAINT fact_teaching_session_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES fact_schedule(schedule_id) ON DELETE CASCADE;
ALTER TABLE fact_teaching_session ADD CONSTRAINT fact_teaching_session_week_no_fkey FOREIGN KEY (week_no) REFERENCES dim_week(week_no);
CREATE INDEX ix_fts_week ON public.fact_teaching_session USING btree (week_no);

CREATE TABLE hoc_ky_week_map (
    hoc_ky text NOT NULL,
    week_no integer NOT NULL,
    nhan_hien_thi text
);
ALTER TABLE hoc_ky_week_map ADD CONSTRAINT hoc_ky_week_map_pkey PRIMARY KEY (hoc_ky, week_no);

CREATE TABLE room_share_confirmed (
    id integer NOT NULL DEFAULT nextval('room_share_confirmed_id_seq'::regclass),
    room_id text NOT NULL,
    course_a text NOT NULL,
    course_b text NOT NULL,
    ly_do text,
    nguoi_xac_nhan text,
    ngay_xac_nhan date DEFAULT CURRENT_DATE
);
ALTER TABLE room_share_confirmed ADD CONSTRAINT room_share_confirmed_room_id_course_a_course_b_key UNIQUE (room_id, course_a, course_b);
ALTER TABLE room_share_confirmed ADD CONSTRAINT room_share_confirmed_pkey PRIMARY KEY (id);


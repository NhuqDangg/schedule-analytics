University Course Timetabling Analytics


[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com/)
[![Chart.js](https://img.shields.io/badge/Chart.js-FF6384?logo=chartdotjs&logoColor=white)](https://www.chartjs.org/)
[![GitHub Pages](https://img.shields.io/badge/GitHub%20Pages-222222?logo=github&logoColor=white)](https://pages.github.com/)

---

## Overview

A data-driven analytics platform for optimizing university course timetabling and resource allocation. This system analyzes semester 251 data across four faculties to provide actionable insights into instructor workload distribution and classroom utilization.

**Live Dashboard:** [schedule-analytics.github.io](https://nhuqdangg.github.io/schedule-analytics/)

---

## Key Features

### Dashboard Tabs

1. **Tổng Quan (Overview)**
   - Total teaching hours and KPI metrics
   - Building utilization breakdown (doughnut chart)
   - Top 8 instructors by teaching hours

2. **Đánh Giá Giảng Viên (Instructor Workload)**
   - Workload distribution matrix (courses vs. hours)
   - Classification: Underutilized, Specialized, Scattered, Overloaded
   - Sortable instructor table with subject assignments
   - Click instructor name to view full schedule modal

3. **Phòng & Tòa Nhà (Room Utilization)**
   - Average teaching hours per room by building
   - Top high-use and available rooms
   - Off-campus location tracking
   - Interactive building filter

4. **Theo Tuần (Weekly Analysis)**
   - 16-week teaching load trend
   - Week-over-week percentage change
   - Top rooms and instructors per week
   - Conflict detection per week

5. **Xung Đột Lịch (Conflict Detection)**
   - Unconfirmed schedule overlaps requiring review
   - Confirmed shared-use sessions (intentional double-booking)
   - Conflict frequency and date tracking

---

## Data Architecture

### Star Schema (14 Tables)

**Dimension Tables (8)**
- `dim_instructor`, `dim_course`, `dim_room`, `dim_building`
- `dim_major`, `dim_faculty`, `dim_time_slot`, `dim_day_of_week`

**Fact Tables (3)**
- `fact_schedule` (primary teaching events)
- `fact_session` (alternative grain for conflict detection)
- `fact_workload` (instructor load aggregation)

**Bridge Tables (3)**
- `bridge_course_instructor`, `bridge_class_instructor`, `bridge_schedule_conflict`

### Data Quality

- **441 online/self-study rows** flagged and excluded from workload metrics
- **584 faculty-unassigned rows** segmented by type: IELP testing, MODULE skills, general education, ORI orientation
- **Unknown Member pattern** applied for robust null handling
- **Cross-validation:** Teaching hours reconciled across fact tables
- **Boolean flags** (`uses_instructor_time`, `uses_room_capacity`) ensure analytical accuracy

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| **Database** | PostgreSQL (Supabase) |
| **API** | Supabase REST (auto-generated) |
| **Frontend** | HTML5, CSS3, JavaScript (ES6) |
| **Visualization** | Chart.js 4.4.4 |
| **Typography** | Source Serif 4, Inter |
| **Deployment** | GitHub Pages |

---

## Setup & Deployment

### For Local Development

1. Clone the repository
2. Open `index.html` in a modern web browser
3. No build step or environment variables needed (Supabase credentials are embedded)

### For GitHub Pages

1. Push files to your GitHub repository
2. Enable GitHub Pages in repository settings (source: main branch / root directory)
3. Dashboard will be live at `https://<username>.github.io/<repo-name>/`

---

## How to Use

- **Explore tabs** at the top to switch between views
- **Click instructor names** in the Workload tab to see their full schedule in a modal
- **Click building bars** in the Room tab to filter rooms by that building; click again to clear filter
- **Click week bars** in the Weekly tab to drill into that week's details
- **Download schedule** as `.ics` file from the instructor modal for calendar import

---

## Project Deliverables

- PostgreSQL star schema with 14 optimized tables
- Python ETL pipeline (`extract_tkb_full.py`)
- Interactive Supabase-backed dashboard
- 14-slide presentation deck
- 11-page academic report (EIUSC conference format)
- GitHub repository with documentation

---

## Dataset

**Source File:** `tkb__251.xlsx`

**Scope:** Semester 251 (approximately September-December 2025)

**Coverage:** 4 faculties
- Kỹ Thuật (Engineering)
- QTKD (Economics & Business)
- CNTT (Information Technology)
- Điều Dưỡng (Nursing)

---

## Key Metrics & Thresholds

- **Workload threshold:** 14 hours/week (95th percentile, statistical benchmark)
- **Conflict definition:** 2+ sessions same calendar day, overlapping hours, different instructor/room, not yet confirmed as intentional
- **Workload classifications:** Based on median hours and course count by employment type (Full-time, Part-time, All-staff)

---

## Known Limitations

- General education course faculty assignment pending confirmation
- Column semantics for `Tổ TH` and `Tên tổ hợp` remain descriptive attributes
- 14-hour threshold is statistical (95th percentile), not official university policy

---



This project is part of academic coursework at Eastern International University. For institutional use or redistribution, contact the project lead.

---

*For detailed schema documentation and SQL queries, see the GitHub repository.*

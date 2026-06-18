import streamlit as st
import pandas as pd
import sqlite3
from pathlib import Path
import plotly.graph_objects as go
import plotly.express as px
import re
from thefuzz import fuzz
from cv_parser import extract_info
from llm_reviewer import review_cv_with_llm, get_learning_roadmap
#app
# ─── 1. CẤU HÌNH HỆ THỐNG  ───────────────────────────────────────────────
BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "career_navigator.db"

st.set_page_config(page_title="AI Career Navigator Pro", page_icon="🎯", layout="wide")

# ─── 2. QUẢN LÝ BỘ NHỚ (SESSION STATE) ───────────────────────────────────
if "search_active" not in st.session_state: st.session_state.search_active = False
if "skills_box" not in st.session_state: st.session_state.skills_box = ""
if "roadmaps" not in st.session_state: st.session_state.roadmaps = {}
if "cv_review" not in st.session_state: st.session_state.cv_review = ""
if "cv_text" not in st.session_state: st.session_state.cv_text = ""


# ─── 3. CÁC HÀM XỬ LÝ THÔNG MINH ─────────────────────────────────────────
def smart_calc_score(user_skills_str, job_skills_raw):
    """Thuật toán tính điểm 10-90% thực tế dựa trên số kỹ năng đáp ứng"""
    if pd.isna(job_skills_raw) or str(job_skills_raw).strip() in ["", "nan"]: return 0
    if not user_skills_str or str(user_skills_str).strip() == "": return 0

    user_skills = [s.strip().lower() for s in str(user_skills_str).split(",") if s.strip()]
    job_skills = [s.strip().lower() for s in str(job_skills_raw).split(",") if s.strip()]

    if not job_skills: return 0

    matched_count = 0
    # Đếm xem ứng viên đáp ứng được bao nhiêu % yêu cầu của Job
    for j_skill in job_skills:
        for u_skill in user_skills:
            if fuzz.partial_ratio(j_skill, u_skill) >= 80 or j_skill in u_skill:
                matched_count += 1
                break  # Tìm thấy 1 cái giống là tính điểm cho kỹ năng đó rồi ngắt

    # Tính tỷ lệ: Trúng 3/4 kỹ năng -> 75%
    score = int((matched_count / len(job_skills)) * 100)

    # Giới hạn điểm tối đa là 100
    return min(score, 100)


def get_courses_from_sql(missing_skills):
    if not missing_skills: return pd.DataFrame()
    try:
        conn = sqlite3.connect(str(DB_PATH))
        conds = [f"target_skill LIKE '%{s.strip()}%'" for s in missing_skills[:3]]
        query = f"SELECT * FROM courses WHERE {' OR '.join(conds)}"
        df_c = pd.read_sql(query, conn)
        conn.close()
        return df_c
    except:
        return pd.DataFrame()

def get_manual_roadmap(missing_skills, job_title):
    """Lộ trình thủ công khi AI quá tải"""
    steps = [
        f"**Bước 1: Củng cố nền tảng** - Tập trung học kỹ {', '.join(missing_skills[:2]) if missing_skills else 'kiến thức cốt lõi'}.",
        f"**Bước 2: Nâng cao kỹ thuật** - Thực hành chuyên sâu {', '.join(missing_skills[2:4]) if len(missing_skills) > 2 else 'các công cụ liên quan'}.",
        f"**Bước 3: Dự án thực tế** - Xây dựng 1 dự án (Pet Project) mô phỏng bài toán của vị trí {job_title}.",
        f"**Bước 4: Tối ưu hồ sơ** - Cập nhật các kỹ năng mới vào CV và Portfolio.",
        f"**Bước 5: Sẵn sàng phỏng vấn** - Luyện tập trả lời các câu hỏi kỹ thuật về các mảng vừa học."
    ]
    return "\n\n".join([f"📍 {s}" for s in steps])
    # Danh sách các từ khóa "vùng xám" muốn loại bỏ khỏi mục Kỹ năng thiếu
    blacklist = ["backend", "frontend", "devops", "thực tập", "fresher"]

    # Lọc bỏ các từ trong blacklist trước khi hiện lên
    clean_missing_skills = [s for s in missing_skills if s.lower().strip() not in blacklist]

    st.write(", ".join([f":red[{s.upper()}]" for s in clean_missing_skills]))
def render_radar_chart(u_skills):
    categories = ['Programming', 'Data/AI', 'Soft Skills', 'DevOps', 'English']
    u_set = {s.lower().strip() for s in u_skills.split(",")}

    def check(keywords): return 4 if any(k in u_set for k in keywords) else 1

    u_scores = [
        check(['python', 'java', 'javascript', 'c++', 'c#', 'php', 'html']),
        check(['sql', 'data', 'machine learning', 'ai', 'big data']),
        check(['communication', 'teamwork', 'leadership', 'presentation']),
        check(['docker', 'aws', 'git', 'cicd', 'linux']),
        check(['english', 'tiếng anh', 'ielts', 'toeic'])
    ]
    fig = go.Figure()
    fig.add_trace(go.Scatterpolar(r=u_scores, theta=categories, fill='toself', name='Bạn'))
    fig.add_trace(go.Scatterpolar(r=[5, 4, 4, 3, 4], theta=categories, fill='toself', name='Thị trường'))
    fig.update_layout(polar=dict(radialaxis=dict(visible=True, range=[0, 5])), height=350)
    return fig


# ─── 4. CỔNG NẠP DỮ LIỆU (SIDEBAR) ────────────────────────────────────────
with st.sidebar:
    st.header("🤖 AI Career Mentor")
    u_file = st.file_uploader("Nạp CV để AI phân tích", type=["pdf", "docx", "jpg", "png", "jpeg"])

    if u_file and st.button("🪄 QUÉT CV & TÌM VIỆC", use_container_width=True, type="primary"):
        with st.spinner("AI đang đọc CV..."):
            text_cv, skills = extract_info(u_file)
            st.session_state.cv_text = text_cv
            st.session_state.skills_box = ", ".join(skills)
            st.session_state.search_active = True
            st.session_state.roadmaps = {}
            st.rerun()

    u_skills_input = st.text_area("Kỹ năng của bạn:", value=st.session_state.skills_box, height=120)
    st.session_state.skills_box = u_skills_input
    u_level = st.selectbox("Cấp bậc mục tiêu:", ["Intern", "Fresher", "Junior", "Senior"])
    if st.button("🔎 Cập nhật tìm kiếm"):
        st.session_state.search_active = True

# ─── 5. NỘI DUNG CHÍNH ────────────────────────────────────────────────────
st.title("🚀 AI Career Navigator Dashboard")

try:
    conn = sqlite3.connect(str(DB_PATH))
    df_all = pd.read_sql("SELECT * FROM jobs", conn)
    conn.close()


    # --- VÁ LỖI CỘT LEVEL ---
    def assign_level(title):
        t = str(title).lower()
        if 'intern' in t or 'thực tập' in t: return 'Intern'
        if 'fresher' in t or 'mới ra trường' in t: return 'Fresher'
        if 'senior' in t: return 'Senior'
        if 'junior' in t: return 'Junior'
        return 'Middle/All'


    # Tự động tạo cột level dựa trên tiêu đề công việc
    df_all['level'] = df_all['title'].apply(assign_level)
    # -------------------------

    # Ép kiểu cột lương về số thực (tránh lỗi khi vẽ biểu đồ)
    df_all['salary'] = pd.to_numeric(df_all['salary'], errors='coerce').fillna(15.0)

except Exception as e:
    st.error(f"⚠️ Lỗi Database: {e}. Hãy chạy file khởi tạo Data trước!")
    st.stop()

tab1, tab2, tab4 = st.tabs(["🎯 Việc làm & Lộ trình", "🗺️ Career Path", "🔍 Review CV"])

with tab1:
    if st.session_state.search_active:
        c1, c2 = st.columns([1, 1])
        with c1:
            st.subheader("🕵️ Skill Gap Analysis")
            st.plotly_chart(render_radar_chart(st.session_state.skills_box), use_container_width=True)
        with c2:
            st.subheader("💡 Tổng quan hồ sơ")
            st.success("✅ Phân tích CV hoàn tất.")
            st.info(f"📌 Đang tìm kiếm ở cấp độ: **{u_level}**")
        st.divider()

        # Thiết lập phân cấp Level để tìm Job thăng tiến
        level_hierarchy = {"Intern": 1, "Fresher": 2, "Junior": 3, "Middle/All": 3, "Senior": 4}
        current_lvl_num = level_hierarchy.get(u_level, 1)

        # ------------------------------------------------------------------
        # KHU VỰC 1: CÔNG VIỆC VỪA SỨC (MATCH CAO)
        # ------------------------------------------------------------------
        st.header("🎯 Các vị trí phù hợp với năng lực hiện tại")

        # Lọc Job đúng cấp bậc
        df_current = df_all[df_all['level'].str.contains(u_level, case=False, na=False)].copy()
        if df_current.empty: df_current = df_all.copy()

        df_current['score'] = df_current['skills'].apply(lambda x: smart_calc_score(st.session_state.skills_box, x))
        top_current_jobs = df_current[df_current['score'] >= 40].sort_values('score', ascending=False).head(5)

        if top_current_jobs.empty:
            st.warning("Chưa tìm thấy công việc phù hợp cao. Hãy bổ sung thêm kỹ năng!")
        else:
            for _, row in top_current_jobs.iterrows():
                with st.expander(f"🟢 Match {row['score']}% | {row['title']} - Mức lương: {row['salary']} Tr"):
                    st.write(f"**Yêu cầu kỹ năng:** {row['skills']}")
                    if pd.notna(row.get('link')): st.link_button("🌐 Ứng tuyển ngay", row['link'])

        st.divider()

        # ------------------------------------------------------------------
        # KHU VỰC 2: ĐỊNH HƯỚNG THĂNG TIẾN (LEVEL & LƯƠNG CAO HƠN)
        # ------------------------------------------------------------------
        # ------------------------------------------------------------------
        # ------------------------------------------------------------------
        # KHU VỰC 2: ĐỊNH HƯỚNG THĂNG TIẾN (Đã sửa lỗi Link Button & Layout 2 cột)
        # ------------------------------------------------------------------
        st.header("🚀 Định hướng thăng tiến (Career Up-Skilling)")
        st.info("💡 AI đã phân tích các lỗ hổng kỹ năng và thiết kế lộ trình 5 bước để bạn đạt mức lương cao hơn.")

        # Lọc Job có cấp bậc cao hơn VÀ lương cao hơn
        df_advance = df_all[df_all['level'].apply(lambda x: level_hierarchy.get(x, 1) > current_lvl_num)].copy()
        if df_advance.empty:
            threshold_salary = df_all['salary'].quantile(0.8)
            df_advance = df_all[df_all['salary'] > threshold_salary].copy()

        df_advance['score'] = df_advance['skills'].apply(lambda x: smart_calc_score(st.session_state.skills_box, x))
        top_advance_jobs = df_advance[(df_advance['score'] >= 5) & (df_advance['score'] <= 85)].sort_values('salary',
                                                                                                            ascending=False).head(
            5)

        for _, row in top_advance_jobs.iterrows():
            with st.expander(f"💎 {row['title']} | Lương: {row['salary']} Tr (Độ khớp: {row['score']}%)"):

                # 1. HIỂN THỊ KỸ NĂNG THIẾU DẠNG BADGE (Cải tiến giao diện)
                u_list = {s.strip().lower() for s in st.session_state.skills_box.split(",")}
                j_list = {s.strip().lower() for s in str(row['skills']).split(",")}
                missing_skills = [s for s in j_list if not any(u in s or s in u for u in u_list)]

                # Lọc bỏ các từ khóa chung chung để tránh "cồng kềnh"
                blacklist = ["backend", "frontend", "devops", "thực tập", "fresher", "middle", "senior",
                             "tiếng anh"]
                clean_missing = [s.strip().upper() for s in missing_skills if s.lower().strip() not in blacklist]

                c_gap1, c_gap2 = st.columns([3, 1])
                with c_gap1:
                    if clean_missing:
                        st.write("🚩 **Kỹ năng mục tiêu cần học thêm:**")
                        # Hiện dạng thẻ màu đỏ-cam trông cực chuyên nghiệp
                        st.markdown(" ".join([f":orange-background[{s}]" for s in clean_missing]))
                    else:
                        st.success("✅ Bạn đã sẵn sàng ứng tuyển vị trí này!")
                with c_gap2:
                    if pd.notna(row.get('link')):
                        st.link_button("🔗 Xem Job Gốc", row['link'], use_container_width=True)

                st.divider()

                # 2. NÚT BẤM (DÙNG GUARD CLAUSE ĐỂ TIẾT KIỆM API)
                if st.button(f"🗺️ Thiết kế Lộ trình 5 bước cho {row['title']}", key=f"adv_{row['id']}",
                             type="primary"):
                    if row['id'] not in st.session_state.roadmaps:
                        with st.spinner("AI Mentor đang lên kế hoạch..."):
                            roadmap_text = get_learning_roadmap(st.session_state.skills_box, row['skills'],
                                                                row['title'])
                            courses_df = get_courses_from_sql(missing_skills)
                            st.session_state.roadmaps[row['id']] = {"text": roadmap_text, "courses": courses_df}
                    else:
                        st.toast("Lộ trình đã sẵn sàng bên dưới!")

                # 3. HIỂN THỊ: LỘ TRÌNH (FULL) & KHÓA HỌC (GRID)
                if row['id'] in st.session_state.roadmaps:
                    data = st.session_state.roadmaps[row['id']]

                    # KIỂM TRA LỖI AI "ĐÌNH CÔNG" -> DÙNG HÀM THỦ CÔNG BẠN VỪA DÁN
                    final_roadmap = data['text']
                    if "AI đang nghỉ" in final_roadmap or len(final_roadmap) < 30:
                        final_roadmap = get_manual_roadmap(missing_skills, row['title'])
                        st.warning("⚠️ AI đang quá tải, hệ thống đã kích hoạt Lộ trình chuẩn dự phòng cho bạn!")

                    st.markdown(f"### 📍 Lộ trình thực thi từng bước")
                    with st.container(border=True):
                        st.markdown(final_roadmap)

                    st.markdown("#### 📚 Tài nguyên học tập (Xếp dạng lưới gọn gàng)")
                    if not data['courses'].empty:
                        # Gom nhóm theo kỹ năng để biết học cái này bổ sung cho cái gì
                        grouped = data['courses'].groupby('target_skill')
                        for skill, group in grouped:
                            with st.container(border=True):
                                st.markdown(f"**🛠️ Bổ trợ cho: :red[{skill.upper()}]**")
                                # Chia 2 cột để tiết kiệm diện tích, bớt cồng kềnh
                                c_cols = st.columns(2)
                                for idx, (_, c) in enumerate(group.iterrows()):
                                    with c_cols[idx % 2]:
                                        with st.container(border=True):
                                            st.write(f"**{c['course_name']}**")
                                            st.caption(f"{c['platform']} | {c['price_model']}")
                                            st.link_button("Học ngay ↗️", c['course_url'], use_container_width=True)
                    else:
                        st.info(
                            "💡 Hiện chưa có khóa học khớp trong Database, hãy học theo lộ trình AI gợi ý bên trên.")
with tab2:
    st.header("📈 Toàn cảnh thị trường IT")
    mc1, mc2 = st.columns(2)
    with mc1:
        # Biểu đồ lương giờ đã có cột level để hiển thị bình thường!
        st.plotly_chart(
            px.box(df_all, x="level", y="salary", title="Phân bổ lương (Triệu VNĐ) theo Cấp bậc", color="level"),
            use_container_width=True)
    with mc2:
        all_skills = []
        for s in df_all['skills'].dropna(): all_skills.extend([x.strip().lower() for x in str(s).split(",")])
        s_counts = pd.Series(all_skills).value_counts().head(10).reset_index()
        s_counts.columns = ['Kỹ năng', 'Số lượng']
        st.plotly_chart(
            px.bar(s_counts, x='Số lượng', y='Kỹ năng', orientation='h', title="Top 10 kỹ năng 'Khát' nhân lực nhất"),
            use_container_width=True)

with tab4:
    st.header("📄 AI Resume Review")
    if st.session_state.cv_text:
        if st.button("🤖 Nhận xét CV chi tiết", use_container_width=True):
            with st.spinner("AI đang đọc CV..."):
                st.session_state.cv_review = review_cv_with_llm(st.session_state.cv_text, "Tổng quan", "Tư vấn")
        if st.session_state.cv_review:
            st.markdown(st.session_state.cv_review)
    else:
        st.warning("⚠️ Hãy upload CV trước.")

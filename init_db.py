import pandas as pd
import sqlite3
import os
import re


def extract_it_skills(text):
    """Quét và trích xuất từ khóa IT để chống lỗi 0% Match"""
    if pd.isna(text): return ""
    text = str(text).lower()

    it_keywords = [
        "python", "java", "javascript", "c++", "c#", "php", "ruby", "go", "swift",
        "sql", "mysql", "postgresql", "mongodb", "nosql", "oracle",
        "machine learning", "ai", "deep learning", "nlp", "computer vision", "data science",
        "react", "angular", "vue", "node.js", "nodejs", "express", "spring boot", "django", "flask",
        "aws", "azure", "gcp", "docker", "kubernetes", "linux", "git", "ci/cd",
        "frontend", "backend", "fullstack", "full stack", "mobile", "android", "ios", "flutter",
        "data analyst", "data engineer", "business analyst"
    ]

    found_skills = [kw.title() for kw in it_keywords if kw in text]

    if "ml" in text.split(): found_skills.append("Machine Learning")
    if "js" in text.split(): found_skills.append("JavaScript")
    if "llm" in text.split(): found_skills.append("AI")

    return ", ".join(list(set(found_skills)))


def parse_salary(s):
    """Bộ quy đổi lương chữ -> lương số (Triệu VNĐ) để tránh TypeError"""
    if pd.isna(s): return None

    # Làm sạch dấu phẩy, chấm
    s = str(s).lower().replace(',', '').replace('.', '')

    # Loại bỏ các chữ không thể tính toán
    if 'thoả thuận' in s or 'thỏa thuận' in s or 'cạnh tranh' in s:
        return None

    # Tìm tất cả các con số trong chuỗi
    numbers = [float(x) for x in re.findall(r'\d+', s)]

    if not numbers:
        return None

    # Xử lý quy đổi
    if 'usd' in s:
        # Giả sử 1 USD = 25,000 VNĐ -> Đổi ra Triệu: x * 25 / 1000
        if len(numbers) >= 2:
            return ((numbers[0] + numbers[1]) / 2) * 25 / 1000
        else:
            return numbers[0] * 25 / 1000
    else:
        # Tiền Việt (Tính bằng Triệu)
        if len(numbers) >= 2:
            return (numbers[0] + numbers[1]) / 2
        else:
            return numbers[0]


def clean_and_load_db():
    print("🗄️ BẮT ĐẦU LÀM SẠCH VÀ ĐỔ DỮ LIỆU VÀO SQLITE...")
    csv_file = "data.csv"
    db_file = "career_navigator.db"

    if not os.path.exists(csv_file):
        print(f"❌ Lỗi: Không tìm thấy file {csv_file}. Hãy chạy scraper trước!")
        return

    # 1. ĐỌC DỮ LIỆU
    df = pd.read_csv(csv_file)
    print(f"📊 Dữ liệu thô ban đầu: {len(df)} dòng.")

    # 2. XÓA TRÙNG LẶP VÀ RÁC
    if 'link' in df.columns:
        df = df.drop_duplicates(subset=['link'], keep='last')
    df = df.dropna(subset=['title'])

    # 3. CHUẨN HÓA CỘT LƯƠNG (SỬA LỖI MEDIAN TYPEERROR)
    print("💰 Đang xử lý và quy đổi cột mức lương...")
    if 'salary' in df.columns:
        # Chuyển đổi thành số thực (Triệu VNĐ)
        df['salary_numeric'] = df['salary'].apply(parse_salary)

        # Tính Median an toàn
        median_val = df['salary_numeric'].median()
        if pd.isna(median_val):
            median_val = 15.0  # Mặc định 15 triệu nếu file hỏng toàn bộ lương

        # Điền số Median vào các chỗ rỗng/thoả thuận
        df['salary_numeric'] = df['salary_numeric'].fillna(median_val)

        # Ghi đè lại cột gốc để App hiển thị
        df['salary'] = df['salary_numeric'].round(1)
        df = df.drop(columns=['salary_numeric'])

    # 4. CHUẨN HÓA KỸ NĂNG (DIỆT LỖI 0% MATCH TẬN GỐC)
    print("🧹 Đang trích xuất và làm sạch kỹ năng...")
    source_col = 'description' if 'description' in df.columns else 'title'
    df['skills'] = df[source_col].apply(extract_it_skills)

    df = df[df['skills'] != ""]
    print(f"✅ Đã giữ lại {len(df)} công việc có dữ liệu kỹ năng hợp lệ.")

    # 5. CẤP LẠI ID
    if 'id' in df.columns:
        df = df.drop(columns=['id'])
    df = df.reset_index(drop=True)
    df.insert(0, 'id', range(1, 1 + len(df)))

    # 6. ĐỔ VÀO DATABASE
    try:
        conn = sqlite3.connect(db_file)
        df.to_sql('jobs', conn, if_exists='replace', index=False)
        print(f"✅ HOÀN TẤT ĐẠI PHẪU DATABASE! Sẵn sàng cho App hoạt động.")
    except Exception as e:
        print(f"❌ Lỗi Database: {e}")
    finally:
        if 'conn' in locals():
            conn.close()


if __name__ == "__main__":
    clean_and_load_db()
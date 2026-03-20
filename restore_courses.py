import sqlite3
import pandas as pd
import os


def restore_from_csv():
    # Tên file bạn đã gửi
    csv_file = "link_course.csv"
    db_file = "career_navigator.db"

    if not os.path.exists(csv_file):
        print(f"❌ Lỗi: Không tìm thấy file {csv_file}. Hãy để file này cùng thư mục với code!")
        return

    print(f"📚 Đang nạp {len(pd.read_csv(csv_file, on_bad_lines='skip'))} khóa học vào Database...")

    try:
        # Đọc CSV và bỏ qua các dòng lỗi định dạng (bad lines)
        df = pd.read_csv(csv_file, on_bad_lines='skip')

        # Làm sạch tên kỹ năng để khi so khớp với CV không bị lệch (ví dụ: " Python " -> "Python")
        df['target_skill'] = df['target_skill'].str.strip()

        conn = sqlite3.connect(db_file)
        # Ghi đè bảng courses
        df.to_sql('courses', conn, if_exists='replace', index=False)
        conn.close()

        print("✅ HOÀN TẤT: Dữ liệu khóa học từ file CSV đã sẵn sàng trong SQL!")

    except Exception as e:
        print(f"❌ Lỗi khi xử lý dữ liệu: {e}")


if __name__ == "__main__":
    restore_from_csv()
import pandas as pd
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.service import Service
from webdriver_manager.chrome import ChromeDriverManager
import time


def run_scraper():
    print("🚀 Khởi động Robot cào dữ liệu (Crawler)...")

    # Cấu hình trình duyệt chạy ngầm (Bỏ comment dòng headless nếu không muốn hiện cửa sổ Chrome)
    options = webdriver.ChromeOptions()
    # options.add_argument('--headless')
    options.add_argument('--disable-gpu')
    options.add_argument('--no-sandbox')

    # Tự động tải ChromeDriver tương thích
    driver = webdriver.Chrome(service=Service(ChromeDriverManager().install()), options=options)

    jobs_data = []

    try:
        # VÍ DỤ: URL cào việc làm IT (Bạn có thể thay bằng link TopCV, ITviec, VietnamWorks...)
        # Lưu ý: Các class CSS bên dưới là ví dụ phổ biến, bạn cần F12 trên web thực tế để chỉnh lại cho khớp
        url = "https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026"
        print(f"Đang truy cập: {url}")
        driver.get(url)

        # Đợi 5 giây để JavaScript render xong trang
        time.sleep(5)

        # Lấy danh sách các thẻ công việc (Job Cards)
        # Tùy trang web, class này có thể là .job-item, .job-card, .result-item...
        job_cards = driver.find_elements(By.CSS_SELECTOR, ".job-item-search-result, .job-item, .job-card")

        print(f"🔍 Tìm thấy {len(job_cards)} công việc. Bắt đầu trích xuất...")

        for card in job_cards:
            try:
                # 1. Lấy Tiêu đề & Link
                title_elem = card.find_element(By.CSS_SELECTOR, "h3.title a, .job-title a, h2 a")
                title = title_elem.text.strip()
                link = title_elem.get_attribute("href")

                # 2. Lấy Tên công ty & Lương
                company = card.find_element(By.CSS_SELECTOR, ".company, .company-name").text.strip()
                salary = card.find_element(By.CSS_SELECTOR, ".salary, .job-salary").text.strip()

                # 3. LẤY KỸ NĂNG (BƯỚC QUAN TRỌNG NHẤT ĐỂ KHÔNG BỊ 0% MATCH)
                # Tìm các tag kỹ năng nhỏ (VD: <span>Python</span>)
                skill_elements = card.find_elements(By.CSS_SELECTOR, ".job-skill-tag, .tech-stack, .skill-tag")

                # BÍ QUYẾT LÀM SẠCH: Nối mảng lại thành chuỗi cách nhau bằng dấu phẩy
                # Kết quả chuẩn: "Python, SQL, React"
                if skill_elements:
                    skills_string = ", ".join([skill.text.strip() for skill in skill_elements])
                else:
                    # Nếu web không có thẻ kỹ năng, lấy tạm Tiêu đề để file init_db.py tự động bóc tách sau
                    skills_string = title

                # 4. Đóng gói dữ liệu
                jobs_data.append({
                    "title": title,
                    "company": company,
                    "salary": salary,
                    "link": link,
                    "skills": skills_string  # <-- Cột sống còn của hệ thống Match
                })
                print(f"  [+] Đã cào: {title}")

            except Exception as e:
                # Nếu một thẻ job bị lỗi cấu trúc, bỏ qua và cào thẻ tiếp theo
                continue

    finally:
        # Luôn luôn đóng trình duyệt khi xong việc
        driver.quit()

    # 5. Lưu thành file CSV
    df = pd.DataFrame(jobs_data)

    # Xóa các công việc bị trùng lặp link
    df = df.drop_duplicates(subset=['link'])

    # Lưu ra file data.csv (dùng utf-8-sig để không bị lỗi font tiếng Việt)
    df.to_csv("data.csv", index=False, encoding="utf-8-sig")
    print(f"✅ HOÀN TẤT! Đã cào và lưu {len(df)} công việc sạch sẽ vào file data.csv.")


if __name__ == "__main__":
    run_scraper()
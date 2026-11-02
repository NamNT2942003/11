# Báo cáo Bài 5: Phân tích mã lỗi thất bại và khắc phục sự cố CI

---

## 1. Tóm tắt sự cố (Incident Summary)
- **Hệ thống**: QuickBite Microservices Platform.
- **Service gặp lỗi**: `notification-service`.
- **Thông báo lỗi trong log GitHub Actions**:
  ```text
  UnsupportedClassVersionError: class file has been compiled by a more recent version of the Java Runtime (class file version 65.0), this version of the Java Runtime only recognizes class file versions up to 61.0
  ```
- **Bối cảnh**: Lập trình viên phát triển và build service bằng Java 21 trên máy cá nhân, nhưng khi push lên GitHub thì pipeline CI thất bại tại bước build.

---

## 2. Phân tích nguyên nhân gốc rễ (Root Cause Analysis)

### 2.1. Bản chất của ngoại lệ `UnsupportedClassVersionError`
Lỗi `java.lang.UnsupportedClassVersionError` xảy ra khi máy ảo Java (JVM) cố gắng nạp một tệp `.class` (bytecode) được biên dịch bởi một phiên bản JDK cao hơn phiên bản Java Runtime đang thực thi.

Theo đặc tả của Java Virtual Machine (JVM Specification):
- Mỗi tệp `.class` bắt đầu bằng 4 byte số ma thuật (`0xCAFEBABE`), tiếp theo là 2 byte **Minor Version** và 2 byte **Major Version**.
- JVM chỉ hỗ trợ đọc các class file có `major_version` nhỏ hơn hoặc bằng phiên bản tối đa mà runtime đó hỗ trợ.

### 2.2. Bảng ánh xạ phiên bản Java & Class File Version

Quy tắc ánh xạ chuẩn của OpenJDK / Oracle:
$$\text{Major Class File Version} = \text{Java SE Version} + 44 \quad (\text{áp dụng từ Java 1.2 trở đi})$$

| Phiên bản Java (JDK / JRE) | Major Class File Version | Ghi chú trạng thái |
| :--- | :---: | :--- |
| **Java 8 (1.8)** | **52.0** | LTS cũ |
| **Java 11** | **55.0** | LTS |
| **Java 17** | **61.0** | LTS (Phiên bản đang chạy trên CI) |
| **Java 21** | **65.0** | LTS (Phiên bản lập trình viên đang dùng) |
| **Java 22** | 66.0 | Short-term |
| **Java 23** | 67.0 | Short-term |

> **Giải mã thông báo lỗi**:
> - `class file version 65.0`: Mã nguồn (hoặc thư viện) đã được biên dịch bởi **Java 21**.
> - `only recognizes class file versions up to 61.0`: Môi trường runtime trên GitHub Actions runner hiện tại là **Java 17**.
> - Vì $65.0 > 61.0$, JVM của Java 17 từ chối nạp bytecode và dừng pipeline ngay lập tức.

### 2.3. Tại sao lỗi không xuất hiện ở local mà lại bị trên GitHub Actions?
- **Tại máy lập trình viên (Local)**:
  - Máy tính đã cài đặt JDK 21. Cả trình biên dịch (`javac`) và Java Runtime (`java`/Gradle daemon) đều đồng nhất là Java 21.
  - Bytecode tạo ra là 65.0 và runtime nhận diện tốt tới 65.0 $\rightarrow$ Build thành công không có cảnh báo.
- **Tại GitHub Actions Runner (CI)**:
  - Runner khởi chạy từ máy ảo trắng (`ubuntu-latest`).
  - Trong workflow file `.github/workflows/ci.yml`, bước cài đặt Java (`actions/setup-java@v4`) đang khai báo tham số `java-version: '17'`.
  - Khi lệnh build chạy, Gradle hoặc JVM thực thi với Java 17, cố gắng đọc bytecode Java 21 $\rightarrow$ Phát sinh lỗi không tương thích phiên bản.
- **Sự khác biệt cốt lõi**:
  - Đây là bài toán kinh điển về **sai lệch môi trường (Environment Discrepancy / Parity Issue)** giữa môi trường phát triển (Dev) và môi trường tích hợp tự động (CI Runner).

---

## 3. Đề xuất giải pháp khắc phục (Remediation Plan)

### 3.1. Vị trí cụ thể cần điều chỉnh trong `.github/workflows/ci.yml`
Cần rà soát step sử dụng action `actions/setup-java` và nâng cấp tham số `java-version` từ `17` lên `21`.

#### 🔴 Cấu hình ban đầu (Gây lỗi):
```yaml
      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          java-version: '17'     # ❌ Nguyên nhân: Chỉ hỗ trợ tối đa class file 61.0
          distribution: 'temurin'
```

#### 🟢 Cấu hình sau khi sửa (Khắc phục hoàn toàn):
```yaml
      - name: Setup Java JDK 21
        uses: actions/setup-java@v4
        with:
          java-version: '21'     # ✅ Khớp với Java 21 (class file version 65.0)
          distribution: 'temurin'
```

---

## 4. Nguyên tắc phòng ngừa sự cố tái diễn (Best Practices)

Để ngăn chặn lỗi không đồng nhất phiên bản runtime tái diễn trong tương lai, đội ngũ DevOps và Backend cần áp dụng các nguyên tắc sau:

1. **Sử dụng Gradle Java Toolchain (`jvmToolchain`)**:
   Khai báo trực tiếp phiên bản Java yêu cầu vào file `build.gradle`:
   ```groovy
   java {
       toolchain {
           languageVersion = JavaLanguageVersion.of(21)
       }
   }
   ```
   *Lợi ích*: Gradle sẽ tự động phát hiện, tải và sử dụng đúng JDK 21 để build mã nguồn dù máy local hay CI runner đang cài phiên bản Java nào đi nữa.

2. **Quản lý phiên bản thống nhất bằng file cấu hình**:
   - Thêm file `.java-version` (dành cho `jEnv` / GitHub Actions) hoặc `.sdkmanrc` (dành cho `SDKMAN!`) ở thư mục gốc của repository.
   - Khi đó, action `actions/setup-java` có thể đọc phiên bản tự động:
     ```yaml
     - uses: actions/setup-java@v4
       with:
         java-version-file: '.java-version'
         distribution: 'temurin'
     ```

3. **Thiết lập Pipeline Matrix Testing**:
   Đối với các thư viện hoặc core microservice, có thể cấu hình ma trận kiểm thử đa phiên bản để phát hiện sớm các vấn đề tương thích ngược.

---

## 5. Hướng dẫn nộp bài

1. Tạo repo mới trên GitHub: **https://github.com/new** (Tên repo: `11` hoặc `quickbite-notification-service`).
2. Push toàn bộ mã nguồn và báo cáo từ thư mục `C:\Devop\11`:
   ```bash
   cd C:\Devop\11
   git remote add origin https://github.com/NamNT2942003/11.git
   git push -u origin main
   ```
3. Copy link repository (hoặc link tới file `README.md`) để dán vào bài nộp Portal.

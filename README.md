# Viettel vAP-120WD — OEM Backup SSH Patcher

Công cụ Python chạy **offline** để giải mã, chỉnh sửa và mã hóa lại file backup cấu hình của **Viettel vAP-120WD**, firmware **OEM `vAP-1.82-230928`**. Tool được viết dựa trên việc phân tích `system.lua`, binary MIPS32 `key_generation`, backup gốc và một backup `OPEN_SSH` dùng làm mẫu so sánh.

> **Phạm vi đã xác minh:** Giải mã AES-256-CBC, kiểm tra MD5, sửa file trong TAR, mã hóa lại, và giải mã đầu ra để đối chiếu. **Chưa kiểm chứng việc restore và đăng nhập SSH thành công trên thiết bị chạy firmware OEM thật.** Router đang chạy OpenWrt **không được** import file backup OEM này.

## 1. Cấu trúc repo

```text
vap120wd-ssh-backup/
├── README.md
├── vap120wd_backup_ssh_clone.py   # Tool CLI độc lập
├── docs/
│   └── WRITEUP.md                 # Phân tích firmware và định dạng backup
├── tests/
│   └── test_tool.py               # Unit tests bằng dữ liệu giả lập
└── .gitignore
```

**Repo không chứa firmware dump, backup gốc, bản `OPEN_SSH`, serial thực, hash mật khẩu hoặc dữ liệu người dùng.** Những file đó cần được giữ riêng trên máy của chủ sở hữu thiết bị.

## 2. Yêu cầu

- macOS hoặc Linux; **Python 3.9+**.
- OpenSSL CLI trên `PATH` (kiểm tra bằng `openssl version`).
- Backup mã hóa xuất từ WebUI của firmware OEM tương ứng và **serial của chính router đó**.
- Không cần thư viện Python bên thứ ba (`pip install` không cần thiết).

Ví dụ macOS nếu thiếu OpenSSL:

```bash
brew install openssl@3
export PATH="$(brew --prefix openssl@3)/bin:$PATH"
```

Tải ZIP về, giải nén, vào thư mục repo:

```bash
unzip vap120wd-ssh-backup.zip
cd vap120wd-ssh-backup
python3 vap120wd_backup_ssh_clone.py --help
```

## 3. Chế độ hoạt động

| Chế độ | Sửa đổi | Khuyến nghị |
|---|---|---|
| `lan-only` (**mặc định**) | Chỉ chuyển rule firewall SSH từ LAN (TCP 22) sang `ACCEPT`. Giữ nguyên `/etc/shadow`, WAN và Telnet. | **Nên dùng để nghiên cứu trước**. Chưa đảm bảo xác thực SSH thành công. |
| `legacy-like` | Tái tạo các thay đổi firewall và root/http của mẫu cũ, **giữ hash admin** từ backup đầu vào. | **Nguy hiểm; chỉ phòng lab cô lập.** |
| `legacy-exact` | Như `legacy-like`, nhưng **sao chép thêm hash `admin`** từ file `--reference` để hai file `firewall`/`shadow` trùng nội dung mẫu `OPEN_SSH`. | **Nguy hiểm; chỉ đối chiếu/kiểm thử offline.** |

**CẢNH BÁO về hai chế độ `legacy-*`:** Mẫu tham chiếu mở SSH/Telnet từ cả LAN và WAN, mở web management WAN, đổi forwarding từ `REJECT` sang `ACCEPT`, và **xóa hash mật khẩu root**. Chế độ `legacy-exact` còn thay đổi hash `admin`, khiến mật khẩu quản trị hiện tại có thể không dùng được. Không restore các bản này lên router kết nối Internet.

## 4. Hướng dẫn sử dụng

Chạy các lệnh **trên Mac/Linux**, trong thư mục repo. Thay `SERIAL_CUA_ROUTER` bằng serial thực và đường dẫn backup của thiết bị.

### 4.1. Xem trước thay đổi, không tạo file

```bash
python3 vap120wd_backup_ssh_clone.py \
  --input /duong-dan/backup-goc.tar.gz \
  --serial SERIAL_CUA_ROUTER \
  --mode lan-only \
  --dry-run
```

Lệnh in ra diff của `etc/config/firewall`; không kết nối router, không ghi file đầu ra.

### 4.2. Tạo backup chỉ mở SSH trong LAN (nên dùng)

```bash
python3 vap120wd_backup_ssh_clone.py \
  --input /duong-dan/backup-goc.tar.gz \
  --output ./backup-ssh-lan-only.tar.gz \
  --serial SERIAL_CUA_ROUTER \
  --mode lan-only
```

Tool sẽ tạo `backup-ssh-lan-only.tar.gz` có định dạng mã hóa WebUI OEM (**đây không phải tar.gz thuần dù tên file có phần mở rộng `.tar.gz`**). File đầu ra được tạo với quyền `0600` và không ghi đè file đã tồn tại.

### 4.3. Mô phỏng thay đổi bản OPEN_SSH cũ, không cần mẫu tham chiếu

> **Cực kỳ không an toàn**: mở quản trị WAN/Telnet và để trống hash root. Chỉ dùng trong lab có mạng cô lập, không restore lên mạng sản xuất.

```bash
python3 vap120wd_backup_ssh_clone.py \
  --input /duong-dan/backup-goc.tar.gz \
  --output ./backup-legacy-like.tar.gz \
  --serial SERIAL_CUA_ROUTER \
  --mode legacy-like \
  --acknowledge-insecure
```

### 4.4. Tái tạo hai file cấu hình giống mẫu tham chiếu

> **Cực kỳ không an toàn**: cần `OPEN_SSH` thuộc cùng serial, sao chép hash `admin` từ mẫu ngoài các thay đổi nguy hiểm khác. Dùng cho mục đích **kiểm chứng offline**, không khuyến nghị restore.

```bash
python3 vap120wd_backup_ssh_clone.py \
  --input /duong-dan/backup-goc.tar.gz \
  --output ./backup-legacy-exact.tar.gz \
  --serial SERIAL_CUA_ROUTER \
  --mode legacy-exact \
  --reference /duong-dan/OPEN_SSH_mau.tar.gz \
  --acknowledge-insecure
```

Để chỉ xem diff trước khi tạo file, thêm `--dry-run` và bỏ dòng `--output`.

**“Exact” ở đây nghĩa là nội dung hai file cấu hình được thay đổi trùng byte với mẫu**, không phải toàn bộ file backup mã hóa giống byte-for-byte. Salt ngẫu nhiên và cách đóng gói TAR/gzip có thể khác.

## 5. Tool hoạt động như thế nào?

```text
Encrypted backup (Base64 / OpenSSL Salted__)
    ↓  Base64 decode (nếu cần)
AES-256-CBC decrypt, OpenSSL EVP_BytesToKey / MD5
    ↓
[32 byte ASCII MD5] + [gzip TAR]
    ↓  So khớp MD5 với gzip TAR
Kiểm tra cấu trúc TAR, giới hạn kích thước
    ↓  Chỉ sửa etc/config/firewall (và etc/shadow nếu legacy)
Đóng gói TAR/gzip, MD5 mới
    ↓
AES-256-CBC encrypt với salt mới → Base64
    ↓
Giải mã lại, kiểm tra MD5/TAR và đối chiếu tất cả file
```

Password mã hóa được tạo từ serial router theo thuật toán được reverse engineer từ firmware: **xoay vòng +8 các chữ cái in hoa `A-Z`**, chữ số giữ nguyên. Tool lấy serial qua `--serial` chứ không cần truy cập router. Không in hash mật khẩu người dùng ra console.

## 6. Kiểm thử

Chạy bộ kiểm thử **bằng fixture giả lập**, không cần backup hoặc serial thật:

```bash
python3 -m unittest discover -s tests -v
```

Tác giả đã kiểm tra offline bằng hai backup mẫu: giải mã và MD5 hợp lệ, hai file `etc/config/firewall` và `etc/shadow` ở chế độ `legacy-exact` có nội dung khớp mẫu tham chiếu, các file còn lại giữ nguyên nội dung và metadata của backup gốc. Không khẳng định firmware OEM trên thiết bị thật sẽ chấp nhận restore hoặc cho đăng nhập SSH.

## 7. Xử lý lỗi thường gặp

| Lỗi | Nguyên nhân thường gặp | Cách khắc phục |
|---|---|---|
| `OpenSSL failed` | Sai serial, file hỏng, firmware khác | Xác minh serial và firmware OEM; dùng bản backup gốc |
| `MD5 verification failed` | Dữ liệu bị hỏng hoặc sai định dạng | Không restore; tạo lại backup từ WebUI |
| `Unexpected ... firewall` | Firmware/backup khác mẫu đã phân tích hoặc rule bị chỉnh sẵn | Dừng, so sánh cấu hình; tool cố tình không sửa mù |
| `legacy-exact requires --reference` | Chưa cung cấp backup tham chiếu | Cung cấp file đúng serial hoặc dùng `lan-only` |
| `File exists` | Không cho ghi đè file đầu ra | Đặt tên file đầu ra mới |
| Restore báo lỗi hoặc SSH vẫn không đăng nhập | OEM restore, dịch vụ Dropbear hoặc xác thực chưa được kiểm chứng | Quay về phân tích riêng; không mở WAN hay xóa mật khẩu để thử mò |

## 8. Quy tắc an toàn

1. Luôn giữ bản gốc và checksum SHA-256; thử `--dry-run` trước.
2. Không đăng public backup, firmware chứa bí mật, cấu hình mạng, `/etc/shadow`, private key, hay serial nhạy cảm.
3. **Không import backup OEM vào OpenWrt.** Firmware đích phải tương thích và có phương án recovery UART/flash.
4. Không thử chế độ legacy trên thiết bị đang nối Internet. Ưu tiên `lan-only` và mật khẩu/SSH key mạnh.
5. Tool **không** flash, reboot, SSH hay can thiệp router; mọi thao tác là offline với file trên máy.

Tài liệu nghiên cứu chi tiết: [`docs/WRITEUP.md`](docs/WRITEUP.md).

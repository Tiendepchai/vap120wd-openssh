# Write-up: Reverse Engineering Backup Viettel vAP-120WD để nghiên cứu mở SSH

**Đối tượng:** Viettel vAP-120WD · Firmware OEM `vAP-1.82-230928`  
**Kiến trúc:** MediaTek MT7621 / MIPS32 little-endian  
**Phạm vi:** Nghiên cứu firmware và backup offline trên thiết bị sở hữu; không khai thác thiết bị bên thứ ba  
**Trạng thái:** Đã giải mã và tái tạo định dạng backup; chưa kiểm chứng khôi phục trên firmware OEM thực tế.

## 1. Bài toán

Firmware Viettel gốc có thành phần Dropbear nhưng người dùng không thể đăng nhập SSH thông thường. Có hai dữ liệu đầu vào: một backup WebUI bình thường và một backup `OPEN_SSH` được tạo bởi người khác. Mục tiêu nghiên cứu là tìm xem backup được mã hóa như thế nào, các cấu hình nào đã thay đổi, và liệu có thể tự phát triển công cụ chuyển đổi backup mà không phải dùng chương trình của bên thứ ba.

Một khó khăn lớn là thiết bị đang chạy OpenWrt, không còn boot firmware Viettel. Vì vậy mọi thao tác phân tích được thực hiện **offline**; không flash lại firmware và không ghi vào NAND.

## 2. Khôi phục firmware OEM từ phân vùng dự phòng

Kiểm tra các phân vùng trên OpenWrt bằng `cat /proc/mtd` cho thấy `firmware2` nằm tại `mtd6`, dung lượng 20 MiB. Đọc 128 byte đầu từ **thiết bị chỉ đọc** `/dev/mtd6ro`:

```sh
dd if=/dev/mtd6ro bs=128 count=1 2>/dev/null | hexdump -C
```

Header bắt đầu bằng `27 05 19 56` (magic của U-Boot uImage) và có chuỗi tên firmware `vAP-1.82-230928`. Đây là bằng chứng phân vùng dự phòng còn chứa image OEM. Image được sao lưu về Mac bằng SSH dưới dạng file nhị phân, không ghi flash:

```sh
ssh -T root@192.168.50.1 \
  'dd if=/dev/mtd6ro bs=131072 count=160 2>/dev/null' \
  > vAP-1.82-230928-OEM-firmware2.bin
```

Kích thước mong đợi: **20.971.520 byte**. Cần kiểm tra dung lượng và checksum trước khi tiếp tục.

## 3. Phân tích uImage và trích xuất SquashFS

`binwalk` nhận diện hai thành phần:

| Offset | Thành phần | Kích thước / thông tin |
|---|---|---|
| `0x000000` | U-Boot uImage | Header 64 byte; kernel LZMA/MIPS32, payload 3.153.993 byte |
| `0x302089` (3.154.057) | SquashFS v4.0 | XZ; kích thước 7.622.713 byte; 1.730 inode |

Trích xuất chính xác vùng SquashFS:

```python
from pathlib import Path
image = Path('vAP-1.82-230928-OEM-firmware2.bin').read_bytes()
start, size = 3154057, 7622713
rootfs = image[start:start + size]
assert len(rootfs) == size and rootfs[:4] == b'hsqs'
Path('rootfs.squashfs').write_bytes(rootfs)
```

Sau đó thực thi `unsquashfs -d OEM-rootfs rootfs.squashfs`. Công cụ trích xuất được **1.377 file, 128 thư mục và 224 symlink**. Có cảnh báo liên quan tùy chọn nén XZ và việc không tạo được `/dev/console` khi không chạy với quyền đặc biệt, nhưng phần lớn tệp cần nghiên cứu đã đọc được. Không cần `sudo` chỉ để phục vụ phân tích tĩnh.

## 4. Truy vết luồng Backup/Restore trong LuCI

Trong `usr/lib/lua/luci/controller/admin/system.lua`, handler backup có các bước đáng chú ý:

```lua
luci.util.exec("/usr/bin/cof_cli backup")
luci.util.exec("sysupgrade -b /tmp/backup.tar.gz")
local checksum_backup_out = os.capture("md5sum /tmp/backup.tar.gz", false)
local checksum_backup = string.sub(checksum_backup_out, 1, 32)
luci.util.exec("echo -n "..checksum_backup.." > /tmp/hash_backup")
luci.util.exec("cat /tmp/backup.tar.gz >> /tmp/hash_backup")
local reader = ltn12_popen(backup_cmd)
```

Ở phần khởi tạo, `backup_cmd` được lấy bằng `/usr/bin/key_generation -b`. Khi restore, LuCI gọi `key_generation -r`, đọc dữ liệu giải mã, tách **32 byte MD5** khỏi `tar.gz`, kiểm tra checksum, chỉ khôi phục các đường dẫn được liệt kê trong `/etc/sysupgrade.conf`, chạy `cof_cli restore` rồi reboot.

Điểm then chốt: file tải về mang tên `.tar.gz` **không phải gzip/tar trực tiếp**. Đó là bản mã hóa và mã hóa Base64 của một cấu trúc chứa checksum cộng với archive gzip.

## 5. Reverse engineering `key_generation`

Binary `/usr/bin/key_generation` là ELF **MIPS32r2 little-endian**, dynamic-link với `ld-uClibc.so.0`, kích thước **3.863 byte**, không có section header. Phân tích chuỗi và mã máy cho thấy chương trình dùng:

```text
/usr/sbin/sysHwInfo serialnumber r
openssl enc -e -aes-256-cbc -a -k
openssl base64 -d
openssl enc -d -aes-256-cbc -k
```

Mật khẩu được suy ra từ serial của thiết bị bằng cách **dịch vòng 8 vị trí đối với các chữ cái in hoa A–Z**. Chữ số không thay đổi. Ví dụ độc lập với serial thực:

```text
Serial ví dụ: ABC123XYZ
Password:      IJK123FGH
```

Đây là phép ROT8 trên phần ký tự in hoa, không phải khóa ngẫu nhiên mạnh. Dữ liệu đầu ra theo cấu trúc:

```text
Base64(
  "Salted__" [8 byte]
  + salt [8 byte]
  + AES-256-CBC(
      MD5_HEX(tar.gz) [32 byte ASCII] + tar.gz,
      password = ROT8(serial),
      KDF = OpenSSL EVP_BytesToKey / MD5
    )
)
```

**Lưu ý:** OpenSSL hiện đại có thể mặc định KDF digest khác. Khi giải mã bằng bản OpenSSL mới cần chỉ rõ `-md md5`. Định dạng `Salted__` tự nó không cho biết cipher/KDF; kết luận trên được rút ra từ binary và được kiểm chứng bằng giải mã thực tế.

## 6. Giải mã và xác thực hai bản backup

Hai file kiểm thử:

| File | SHA-256 |
|---|---|
| `backup-vthomeap-2023-10-24.tar.gz` | `316c0892c3dee47e3a48ab4436b89e67ae6196ec64cd628e35c809b20dfacc96` |
| `OPEN_SSH_<SERIAL>.tar.gz` | `24d676b4daab08e11147a30895ef043cc3abc1bf1f9119dc8c23dd88198d39e9` |

Sau khi Base64-decode và dùng OpenSSL AES-256-CBC với `-md md5`, cả hai đều giải mã thành công. Chuỗi MD5 ở 32 byte đầu **trùng với MD5 của các byte gzip/tar còn lại**:

| Backup | MD5 được lưu và đã kiểm chứng | Mục TAR |
|---|---|---|
| Gốc | `15378418c52d111dde50e5f2b0227b99` | 28 |
| OPEN_SSH | `68773d93438700736224ef05721aa097` | 37 |

Bản OPEN_SSH có thêm 9 mục thư mục trong TAR, nhưng sau khi chuẩn hóa đường dẫn và loại bỏ directory entry, cả hai bản cùng chứa **28 tệp/symlink tương ứng**.

## 7. Diff: thực tế bản OPEN_SSH đã sửa gì?

So sánh SHA-256 nội dung từng tệp cho thấy **26 tệp/symlink giữ nguyên**, chỉ có **hai tệp bị thay đổi**:

### `etc/config/firewall`

| Quy tắc | Backup gốc | OPEN_SSH |
|---|---|---|
| SSH từ LAN, TCP 22 | REJECT | ACCEPT |
| Telnet từ LAN, TCP 23 | REJECT | ACCEPT |
| SSH từ WAN, TCP 22 | REJECT | ACCEPT |
| Telnet từ WAN, TCP 23 | REJECT | ACCEPT |
| Quản trị web từ WAN, TCP 80/443 | REJECT | ACCEPT |
| `wandfroute` input | REJECT | ACCEPT |
| `wandfroute` forward | REJECT | ACCEPT |
| Default forwarding | REJECT | ACCEPT |

Một số tên và ID rule cũng đổi từ `*_reject` thành `*_accept`.

### `etc/shadow`

Bản OPEN_SSH xóa hash mật khẩu tài khoản `root`, đặt trường ngày đổi mật khẩu của root từ `18822` về `0`, **thay đổi cả hash mật khẩu `admin`**, và thêm một dòng tài khoản `http` bị trùng. Không công bố hash thật trong write-up này.

Như vậy, bản tham chiếu **không chỉ mở SSH** mà còn thay đổi cơ chế xác thực và nới lỏng đáng kể chính sách bảo vệ WAN.

## 8. Tái tạo backup bằng Python

Từ định dạng đã tìm được, xây dựng quy trình offline:

```text
Backup mã hóa đầu vào
        |
        v
Base64 decode -> OpenSSL AES-256-CBC decrypt (MD5 KDF)
        |
        v
Xác minh 32-byte MD5 -> Đọc tar.gz trong bộ nhớ
        |
        v
Sửa cấu hình có kiểm soát -> Repack tar.gz
        |
        v
MD5 mới + tar.gz -> AES-256-CBC encrypt -> Base64
        |
        v
Giải mã lại để kiểm chứng -> Backup đầu ra
```

Ba chế độ thử nghiệm được xây dựng:

| Chế độ | Hành vi |
|---|---|
| `lan-only` | Chỉ cho phép SSH TCP 22 từ LAN; giữ nguyên mật khẩu và rule WAN/Telnet. |
| `legacy-like` | Tái tạo các thay đổi firewall và root/http của bản cũ, nhưng giữ hash `admin` của backup nguồn. |
| `legacy-exact` | Ngoài các thay đổi trên, lấy hash `admin` từ backup OPEN_SSH tham chiếu để tái tạo **nội dung hai tệp thay đổi trùng byte**. |

Ví dụ chạy chế độ an toàn hơn, sử dụng serial của chính thiết bị:

```sh
python3 vap120wd_backup_ssh_clone.py \
  -i backup-vthomeap-2023-10-24.tar.gz \
  -o backup-ssh-lan-only.tar.gz \
  --serial "SERIAL_CUA_THIET_BI" \
  --mode lan-only
```

Để **đối chiếu** chế độ tái tạo bản cũ mà không ghi file, có thể dùng `--mode legacy-exact --reference OPEN_SSH_...tar.gz --acknowledge-insecure --dry-run`. Chế độ này không thích hợp cho router đang được kết nối Internet; chỉ sử dụng trong môi trường thử nghiệm cô lập.

**Kiểm thử offline:** Kết quả do công cụ báo cáo cho thấy cả ba chế độ đều qua kiểm tra mã hóa–giải mã và checksum; `legacy-exact` đối chiếu trùng byte đối với `etc/config/firewall` và `etc/shadow` của backup tham chiếu. Ciphertext đầu ra **không bắt buộc giống byte-for-byte** vì salt mới và cách đóng gói TAR/gzip có thể khác.

Chế độ legacy **không an toàn để triển khai trên mạng đang kết nối Internet**: WAN và Telnet bị mở, root có mật khẩu trống, và mật khẩu `admin` có thể thay đổi. Chế độ LAN-only là phương án thử nghiệm hợp lý hơn, nhưng chỉ thay firewall không đảm bảo đăng nhập SSH thành công.

## 9. Giới hạn của kết quả

Đến đây, có thể khẳng định: đã khôi phục được một image OEM có header hợp lệ; trích xuất được SquashFS; xác định được luồng Backup/Restore và chương trình `key_generation`; tìm được cipher/KDF/quy tắc tạo mật khẩu; giải mã và kiểm chứng toàn vẹn hai backup; xác định chính xác các tệp cấu hình khác biệt; và tái tạo được backup mã hóa ở mức **offline**.

**Chưa được kiểm chứng:** Việc import backup tạo mới qua giao diện restore trên thiết bị chạy firmware Viettel OEM thật, Dropbear có khởi chạy hay không, cổng SSH có mở sau reboot hay không, và xác thực đăng nhập có thành công hay không. Thiết bị hiện chạy OpenWrt; không được import backup OEM vào OpenWrt. Mọi thử nghiệm trên OEM cần có phương án cứu hộ UART/flash và mạng cô lập.

## 10. Kết luận

Kết quả quan trọng nhất không chỉ là mô phỏng một bản `OPEN_SSH` đã tồn tại, mà là **tái dựng độc lập cơ chế tạo và đọc backup của firmware Viettel** từ firmware gốc, mã LuCI và một binary MIPS32 nhỏ. Nhờ đó, quá trình nghiên cứu không còn phụ thuộc hoàn toàn vào công cụ đóng của bên thứ ba.

Bản backup của người khác đóng vai trò **mẫu đối chiếu hành vi**, không phải nguồn duy nhất để suy ra thuật toán mã hóa. Bài học kỹ thuật là phải tách biệt ba vấn đề: **mở đường mạng tới TCP/22**, **khởi chạy daemon SSH**, và **xác thực tài khoản**. Chỉ khi cả ba được kiểm chứng trên hệ thống thật mới có thể gọi là mở SSH thành công.

---

*Đây là write-up phân tích bảo mật và tương thích backup trên thiết bị sở hữu, không phải xác nhận mở SSH thành công trên firmware OEM sau restore.*

#!/bin/bash

# Script: Tạo user giám sát read-only cho Linux Server
# Author: Linux Master Server
# Usage: sudo bash create-monitor-user.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

USERNAME="monitor"
TEST_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=true
            shift
            ;;
        --username)
            USERNAME="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo -e "${GREEN}=== Script tạo User giám sát Read-Only ===${NC}\n"

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Script này cần chạy với quyền root!${NC}"
   echo "Sử dụng: sudo bash $0"
   exit 1
fi

# Kiểm tra user đã tồn tại chưa
if id "$USERNAME" &>/dev/null; then
    echo -e "${YELLOW}⚠️  User '$USERNAME' đã tồn tại!${NC}"
    if [ "$TEST_MODE" = false ]; then
        read -p "Bạn có muốn cấu hình lại quyền cho user này? (y/n): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "  Test mode: Tiếp tục với user hiện tại"
    fi
    USER_EXISTS=true
else
    USER_EXISTS=false
fi

# Tạo user mới nếu chưa tồn tại
if [ "$USER_EXISTS" = false ]; then
    echo -e "${GREEN}[1/6]${NC} Tạo user '$USERNAME'..."
    
    # Check xem có adduser hay useradd
    if command -v adduser &> /dev/null; then
        adduser --disabled-password --gecos "" $USERNAME 2>/dev/null || \
        useradd -m -s /bin/bash $USERNAME
    else
        useradd -m -s /bin/bash $USERNAME
    fi
    
    if [ "$TEST_MODE" = false ]; then
        echo -e "\n${YELLOW}Đặt password cho user '$USERNAME':${NC}"
        passwd $USERNAME
    else
        echo "TestPass123" | passwd --stdin $USERNAME 2>/dev/null || \
        echo -e "TestPass123\nTestPass123" | passwd $USERNAME
        echo "  Test mode: Password đã set thành 'TestPass123'"
    fi
else
    echo -e "${GREEN}[1/6]${NC} User đã tồn tại, bỏ qua việc tạo mới."
fi

# Xóa user khỏi nhóm sudo (nếu có)
echo -e "\n${GREEN}[2/6]${NC} Đảm bảo user KHÔNG có quyền sudo..."
if groups $USERNAME 2>/dev/null | grep -qE 'sudo|wheel'; then
    deluser $USERNAME sudo 2>/dev/null || true
    gpasswd -d $USERNAME sudo 2>/dev/null || true
    gpasswd -d $USERNAME wheel 2>/dev/null || true
    echo "  ✓ Đã xóa khỏi nhóm sudo/wheel"
else
    echo "  ✓ User không có trong nhóm sudo/wheel"
fi

# Thêm vào nhóm adm để đọc log
echo -e "\n${GREEN}[3/6]${NC} Thêm user vào nhóm 'adm' (đọc log)..."
if getent group adm > /dev/null 2>&1; then
    if command -v usermod &> /dev/null; then
        usermod -aG adm $USERNAME
        echo "  ✓ Đã thêm vào nhóm adm"
    else
        gpasswd -a $USERNAME adm 2>/dev/null && echo "  ✓ Đã thêm vào nhóm adm" || echo "  ⚠️  Không thể thêm vào nhóm adm"
    fi
else
    echo -e "  ${YELLOW}⚠️  Nhóm 'adm' không tồn tại (có thể là CentOS/RHEL)${NC}"
fi

# Thêm vào nhóm systemd-journal
echo -e "\n${GREEN}[4/6]${NC} Thêm user vào nhóm 'systemd-journal' (đọc journal)..."
if getent group systemd-journal > /dev/null 2>&1; then
    if command -v usermod &> /dev/null; then
        usermod -aG systemd-journal $USERNAME
        echo "  ✓ Đã thêm vào nhóm systemd-journal"
    else
        gpasswd -a $USERNAME systemd-journal 2>/dev/null && echo "  ✓ Đã thêm vào nhóm systemd-journal" || echo "  ⚠️  Không thể thêm vào nhóm systemd-journal"
    fi
else
    echo -e "  ${YELLOW}⚠️  Nhóm 'systemd-journal' không tồn tại${NC}"
fi

# Kiểm tra kết quả
echo -e "\n${GREEN}[5/6]${NC} Kiểm tra cấu hình..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}User ID:${NC}"
id $USERNAME

echo -e "\n${YELLOW}Groups:${NC}"
groups $USERNAME

echo -e "\n${YELLOW}Sudo permissions:${NC}"
if sudo -l -U $USERNAME 2>&1 | grep -qE "not allowed|unknown user"; then
    echo -e "${GREEN}✓ User KHÔNG có quyền sudo (ĐÚNG)${NC}"
else
    echo -e "${RED}✗ User có quyền sudo (SAI - cần kiểm tra lại!)${NC}"
fi

echo -e "\n${YELLOW}Home directory:${NC}"
ls -ld /home/$USERNAME 2>/dev/null || echo "Không có home directory"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ===============================
# MODULE TEST TỰ ĐỘNG
# ===============================
echo -e "\n${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  [6/6] CHẠY TEST TỰ ĐỘNG              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    echo -e "${YELLOW}[TEST]${NC} $test_name"
    
    if eval "$test_command"; then
        if [ "$expected_result" = "pass" ]; then
            echo -e "  ${GREEN}✅ PASS${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "  ${RED}❌ FAIL${NC} (mong đợi lỗi nhưng thành công)"
            ((TESTS_FAILED++))
        fi
    else
        if [ "$expected_result" = "fail" ]; then
            echo -e "  ${GREEN}✅ PASS${NC} (đúng là phải lỗi)"
            ((TESTS_PASSED++))
        else
            echo -e "  ${RED}❌ FAIL${NC}"
            ((TESTS_FAILED++))
        fi
    fi
    echo ""
}

# TEST 1: User tồn tại
run_test "User '$USERNAME' phải tồn tại" \
    "id $USERNAME &>/dev/null" \
    "pass"

# TEST 2: User KHÔNG có sudo
run_test "User KHÔNG được có quyền sudo/wheel" \
    "! groups $USERNAME | grep -qE 'sudo|wheel'" \
    "pass"

# TEST 3: User có thể đọc /etc/passwd
run_test "User có thể đọc file /etc/passwd" \
    "su - $USERNAME -c 'cat /etc/passwd > /dev/null 2>&1'" \
    "pass"

# TEST 4: User KHÔNG thể ghi vào /etc
run_test "User KHÔNG thể ghi file vào /etc (test quyền write)" \
    "su - $USERNAME -c 'touch /etc/test-write-file 2>/dev/null'" \
    "fail"

# TEST 5: User KHÔNG thể chạy sudo
run_test "User KHÔNG thể chạy lệnh sudo" \
    "su - $USERNAME -c 'sudo ls 2>/dev/null'" \
    "fail"

# TEST 6: User có thể xem process
run_test "User có thể xem danh sách process" \
    "su - $USERNAME -c 'ps aux > /dev/null 2>&1'" \
    "pass"

# TEST 7: User có thể xem disk usage
run_test "User có thể xem disk usage" \
    "su - $USERNAME -c 'df -h > /dev/null 2>&1'" \
    "pass"

# TEST 8: User có thể xem memory
run_test "User có thể xem memory info" \
    "su - $USERNAME -c 'free -h > /dev/null 2>&1' || su - $USERNAME -c 'cat /proc/meminfo > /dev/null 2>&1'" \
    "pass"

# TEST 9: User có thể đọc /proc
run_test "User có thể đọc /proc/cpuinfo" \
    "su - $USERNAME -c 'cat /proc/cpuinfo > /dev/null 2>&1'" \
    "pass"

# TEST 10: User KHÔNG thể thay đổi password của user khác
run_test "User KHÔNG thể thay đổi password user khác" \
    "su - $USERNAME -c 'passwd root 2>/dev/null'" \
    "fail"

# TEST 11: User có thể login shell
run_test "User có thể login vào shell" \
    "su - $USERNAME -c 'whoami | grep -q $USERNAME'" \
    "pass"

# TEST 12: User có thể xem network connections (một số có thể cần root)
echo -e "${YELLOW}[TEST]${NC} User có thể xem network connections"
if su - $USERNAME -c 'ss -tulpn > /dev/null 2>&1' || su - $USERNAME -c 'netstat -tulpn > /dev/null 2>&1'; then
    echo -e "  ${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "  ${YELLOW}⚠️  WARNING${NC} (có thể cần root để xem full info)"
    ((TESTS_WARNING++))
fi
echo ""

# TEST 13: Kiểm tra log access (nếu có systemd)
if command -v journalctl &> /dev/null; then
    echo -e "${YELLOW}[TEST]${NC} User có thể đọc journal logs"
    if su - $USERNAME -c 'journalctl -n 1 --no-pager > /dev/null 2>&1'; then
        echo -e "  ${GREEN}✅ PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "  ${YELLOW}⚠️  WARNING${NC} (có thể do container không có systemd)"
        ((TESTS_WARNING++))
    fi
    echo ""
fi

# TEST 14: User KHÔNG thể kill process của user khác
run_test "User KHÔNG thể kill process của root" \
    "su - $USERNAME -c 'kill -9 1 2>/dev/null'" \
    "fail"

# TEST 15: User KHÔNG thể modify files trong /var/log
echo -e "${YELLOW}[TEST]${NC} User KHÔNG thể chỉnh sửa /var/log"
if [ -f "/var/log/syslog" ]; then
    run_test "User KHÔNG thể ghi vào /var/log/syslog" \
        "su - $USERNAME -c 'echo test >> /var/log/syslog 2>/dev/null'" \
        "fail"
else
    echo -e "  ${YELLOW}⚠️  SKIP${NC} (/var/log/syslog không tồn tại)"
    ((TESTS_WARNING++))
    echo ""
fi

# ===============================
# KẾT QUẢ TEST
# ===============================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}📊 KẾT QUẢ TEST:${NC}"
echo -e "  ${GREEN}✅ Passed: $TESTS_PASSED${NC}"
echo -e "  ${RED}❌ Failed: $TESTS_FAILED${NC}"
echo -e "  ${YELLOW}⚠️  Warning: $TESTS_WARNING${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 TẤT CẢ TEST QUAN TRỌNG ĐÃ PASS!${NC}"
    echo -e "${GREEN}User '$USERNAME' đã được cấu hình đúng với quyền read-only.${NC}\n"
else
    echo -e "\n${RED}⚠️  CÓ $TESTS_FAILED TEST BỊ FAIL!${NC}"
    echo -e "${RED}Vui lòng kiểm tra lại cấu hình.${NC}\n"
fi

# ===============================
# HƯỚNG DẪN SỬ DỤNG
# ===============================
echo -e "${GREEN}✅ Hoàn tất cài đặt!${NC}"
echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  HƯỚNG DẪN SỬ DỤNG                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}1. Đăng nhập vào user monitor:${NC}"
echo "   su - $USERNAME"
echo ""
echo -e "${YELLOW}2. Các lệnh giám sát hữu ích:${NC}"
echo "   # Xem process"
echo "   ps aux"
echo "   top"
echo ""
echo "   # Xem log (nếu có)"
echo "   journalctl -f"
echo "   tail -f /var/log/syslog"
echo ""
echo "   # Xem system resources"
echo "   df -h          # Disk usage"
echo "   free -h        # Memory"
echo "   uptime         # System uptime"
echo ""
echo "   # Xem network"
echo "   ss -tulpn      # Network connections"
echo "   netstat -tulpn"
echo ""
echo "   # Xem system info"
echo "   cat /proc/cpuinfo"
echo "   cat /proc/meminfo"
echo "   uname -a"
echo ""
echo -e "${YELLOW}3. Test thủ công:${NC}"
echo "   # Thử ghi file (phải fail)"
echo "   touch /etc/test"
echo ""
echo "   # Thử sudo (phải fail)"
echo "   sudo ls"
echo ""
echo -e "${RED}⚠️  BẢO MẬT:${NC}"
echo "  • Password hiện tại: TestPass123 (nếu test mode)"
echo "  • Đổi password: passwd (trong monitor user)"
echo "  • Kiểm tra quyền: groups $USERNAME"
echo "  • Xóa user: userdel -r $USERNAME"
echo ""

# Hiển thị command để test nhanh
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  QUICK TEST COMMANDS                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
echo "# Copy và chạy các lệnh sau để test:"
echo ""
echo "su - $USERNAME -c 'whoami && pwd'"
echo "su - $USERNAME -c 'ps aux | head'"
echo "su - $USERNAME -c 'df -h'"
echo "su - $USERNAME -c 'cat /etc/passwd | head'"
echo "su - $USERNAME -c 'touch /etc/test 2>&1 | grep denied'"
echo "su - $USERNAME -c 'sudo ls 2>&1 | grep sudoers'"
echo ""

exit 0

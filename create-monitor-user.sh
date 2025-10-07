#!/bin/bash

# Script: Tạo user giám sát read-only cho Linux Server
# Author: Linux Master Server
# Usage: sudo bash create-monitor-user.sh

# KHÔNG dùng set -e để script không dừng khi có lỗi test
# set -e

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

# Phát hiện OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    echo -e "${BLUE}ℹ️  Phát hiện OS: $PRETTY_NAME${NC}\n"
else
    OS="unknown"
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
    if command -v adduser &> /dev/null && [[ "$OS" != "alpine" ]]; then
        adduser --disabled-password --gecos "" $USERNAME 2>/dev/null || \
        useradd -m -s /bin/bash $USERNAME 2>/dev/null || \
        useradd -m -s /bin/sh $USERNAME
    else
        # Alpine hoặc hệ thống chỉ có useradd
        useradd -m -s /bin/sh $USERNAME 2>/dev/null || \
        useradd -m $USERNAME
    fi
    
    if [ "$TEST_MODE" = false ]; then
        echo -e "\n${YELLOW}Đặt password cho user '$USERNAME':${NC}"
        passwd $USERNAME
    else
        echo "TestPass123" | chpasswd 2>/dev/null || \
        echo "$USERNAME:TestPass123" | chpasswd 2>/dev/null || \
        echo -e "TestPass123\nTestPass123" | passwd $USERNAME 2>/dev/null
        echo "  Test mode: Password đã set thành 'TestPass123'"
    fi
    echo "  ✓ User đã được tạo"
else
    echo -e "${GREEN}[1/6]${NC} User đã tồn tại, bỏ qua việc tạo mới."
fi

# Xóa user khỏi nhóm sudo (nếu có)
echo -e "\n${GREEN}[2/6]${NC} Đảm bảo user KHÔNG có quyền sudo..."
REMOVED_SUDO=false
if groups $USERNAME 2>/dev/null | grep -qE 'sudo|wheel|root'; then
    deluser $USERNAME sudo 2>/dev/null && REMOVED_SUDO=true
    gpasswd -d $USERNAME sudo 2>/dev/null && REMOVED_SUDO=true
    gpasswd -d $USERNAME wheel 2>/dev/null && REMOVED_SUDO=true
    deluser $USERNAME wheel 2>/dev/null && REMOVED_SUDO=true
    if [ "$REMOVED_SUDO" = true ]; then
        echo "  ✓ Đã xóa khỏi nhóm sudo/wheel"
    fi
else
    echo "  ✓ User không có trong nhóm sudo/wheel/root"
fi

# Thêm vào nhóm adm để đọc log (nếu có)
echo -e "\n${GREEN}[3/6]${NC} Thêm user vào nhóm 'adm' (đọc log)..."
if getent group adm > /dev/null 2>&1; then
    if command -v usermod &> /dev/null; then
        usermod -aG adm $USERNAME 2>/dev/null && echo "  ✓ Đã thêm vào nhóm adm" || \
        (gpasswd -a $USERNAME adm 2>/dev/null && echo "  ✓ Đã thêm vào nhóm adm")
    else
        addgroup $USERNAME adm 2>/dev/null && echo "  ✓ Đã thêm vào nhóm adm" || \
        echo "  ⚠️  Không thể thêm vào nhóm adm"
    fi
else
    echo -e "  ${YELLOW}⚠️  Nhóm 'adm' không tồn tại${NC}"
    # Tạo nhóm log reading cho Alpine
    if [[ "$OS" == "alpine" ]]; then
        echo "  ℹ️  Alpine Linux: Sử dụng quyền mặc định"
    fi
fi

# Thêm vào nhóm systemd-journal (nếu có systemd)
echo -e "\n${GREEN}[4/6]${NC} Thêm user vào nhóm 'systemd-journal' (đọc journal)..."
if getent group systemd-journal > /dev/null 2>&1; then
    if command -v usermod &> /dev/null; then
        usermod -aG systemd-journal $USERNAME 2>/dev/null && echo "  ✓ Đã thêm vào nhóm systemd-journal"
    else
        addgroup $USERNAME systemd-journal 2>/dev/null && echo "  ✓ Đã thêm vào nhóm systemd-journal"
    fi
else
    echo -e "  ${YELLOW}⚠️  Nhóm 'systemd-journal' không tồn tại (có thể không dùng systemd)${NC}"
fi

# Kiểm tra kết quả
echo -e "\n${GREEN}[5/6]${NC} Kiểm tra cấu hình..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}User ID:${NC}"
id $USERNAME

echo -e "\n${YELLOW}Groups:${NC}"
groups $USERNAME

echo -e "\n${YELLOW}Sudo permissions:${NC}"
SUDO_CHECK=$(sudo -l -U $USERNAME 2>&1)
if echo "$SUDO_CHECK" | grep -qE "not allowed|unknown user|may not run"; then
    echo -e "${GREEN}✓ User KHÔNG có quyền sudo (ĐÚNG)${NC}"
    HAS_SUDO=false
elif groups $USERNAME | grep -qE 'sudo|wheel'; then
    echo -e "${RED}✗ User có quyền sudo thông qua group (SAI!)${NC}"
    HAS_SUDO=true
else
    echo -e "${GREEN}✓ User KHÔNG có quyền sudo (ĐÚNG)${NC}"
    HAS_SUDO=false
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
    
    # Chạy command và capture exit code
    eval "$test_command" >/dev/null 2>&1
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
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
}

# TEST 1: User tồn tại
run_test "User '$USERNAME' phải tồn tại" \
    "id $USERNAME" \
    "pass"

# TEST 2: User KHÔNG có sudo
run_test "User KHÔNG được có quyền sudo/wheel" \
    "! groups $USERNAME | grep -qE 'sudo|wheel'" \
    "pass"

# TEST 3: User có thể đọc /etc/passwd
run_test "User có thể đọc file /etc/passwd" \
    "su - $USERNAME -c 'cat /etc/passwd >/dev/null'" \
    "pass"

# TEST 4: User KHÔNG thể ghi vào /etc
run_test "User KHÔNG thể ghi file vào /etc" \
    "su - $USERNAME -c 'touch /etc/test-write-file'" \
    "fail"

# TEST 5: User KHÔNG thể chạy sudo
run_test "User KHÔNG thể chạy lệnh sudo" \
    "su - $USERNAME -c 'sudo ls'" \
    "fail"

# TEST 6: User có thể xem process
run_test "User có thể xem danh sách process" \
    "su - $USERNAME -c 'ps aux >/dev/null || ps -ef >/dev/null'" \
    "pass"

# TEST 7: User có thể xem disk usage
run_test "User có thể xem disk usage" \
    "su - $USERNAME -c 'df -h >/dev/null'" \
    "pass"

# TEST 8: User có thể xem memory
run_test "User có thể xem memory info" \
    "su - $USERNAME -c 'free -h >/dev/null 2>&1 || cat /proc/meminfo >/dev/null'" \
    "pass"

# TEST 9: User có thể đọc /proc
run_test "User có thể đọc /proc/cpuinfo" \
    "su - $USERNAME -c 'cat /proc/cpuinfo >/dev/null'" \
    "pass"

# TEST 10: User KHÔNG thể thay đổi password của user khác
run_test "User KHÔNG thể thay đổi password user khác" \
    "su - $USERNAME -c 'passwd root >/dev/null 2>&1'" \
    "fail"

# TEST 11: User có thể login shell
run_test "User có thể login vào shell" \
    "su - $USERNAME -c 'whoami | grep -q $USERNAME'" \
    "pass"

# TEST 12: User có thể xem uptime
run_test "User có thể xem system uptime" \
    "su - $USERNAME -c 'uptime >/dev/null'" \
    "pass"

# TEST 13: User KHÔNG thể kill process PID 1
run_test "User KHÔNG thể kill process init (PID 1)" \
    "su - $USERNAME -c 'kill -9 1'" \
    "fail"

# TEST 14: User có thể đọc /proc/meminfo
run_test "User có thể đọc /proc/meminfo" \
    "su - $USERNAME -c 'cat /proc/meminfo >/dev/null'" \
    "pass"

# TEST 15: User KHÔNG thể tạo user mới
run_test "User KHÔNG thể tạo user mới" \
    "su - $USERNAME -c 'useradd testuser123'" \
    "fail"

# TEST BONUS: Các warning tests
echo ""
echo -e "${BLUE}[BONUS TESTS - Warning nếu fail]${NC}"
echo ""

# Bonus 1: Network
echo -e "${YELLOW}[TEST]${NC} User có thể xem network connections"
if su - $USERNAME -c 'ss -tulpn >/dev/null 2>&1' || su - $USERNAME -c 'netstat -tulpn >/dev/null 2>&1'; then
    echo -e "  ${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "  ${YELLOW}⚠️  WARNING${NC} (có thể cần root để xem full info, nhưng OK)"
    ((TESTS_WARNING++))
fi

# Bonus 2: Journal logs
if command -v journalctl &> /dev/null; then
    echo -e "${YELLOW}[TEST]${NC} User có thể đọc journal logs"
    if su - $USERNAME -c 'journalctl -n 1 --no-pager >/dev/null 2>&1'; then
        echo -e "  ${GREEN}✅ PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "  ${YELLOW}⚠️  WARNING${NC} (không có systemd hoặc journal, nhưng OK)"
        ((TESTS_WARNING++))
    fi
else
    echo -e "${YELLOW}[INFO]${NC} Hệ thống không có journalctl (không dùng systemd)"
    ((TESTS_WARNING++))
fi

# Bonus 3: /var/log
if [ -d "/var/log" ] && [ "$(ls -A /var/log 2>/dev/null)" ]; then
    echo -e "${YELLOW}[TEST]${NC} User có thể list /var/log"
    if su - $USERNAME -c 'ls /var/log >/dev/null 2>&1'; then
        echo -e "  ${GREEN}✅ PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "  ${YELLOW}⚠️  WARNING${NC} (không thể list /var/log, có thể do permissions)"
        ((TESTS_WARNING++))
    fi
    
    echo -e "${YELLOW}[TEST]${NC} User KHÔNG thể ghi vào /var/log"
    if su - $USERNAME -c 'touch /var/log/testfile123 >/dev/null 2>&1'; then
        echo -e "  ${RED}❌ FAIL${NC} (có thể ghi được - không tốt!)"
        ((TESTS_FAILED++))
    else
        echo -e "  ${GREEN}✅ PASS${NC} (không thể ghi - đúng)"
        ((TESTS_PASSED++))
    fi
fi

# ===============================
# KẾT QUẢ TEST
# ===============================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}📊 KẾT QUẢ TEST:${NC}"
echo -e "  ${GREEN}✅ Passed: $TESTS_PASSED${NC}"
echo -e "  ${RED}❌ Failed: $TESTS_FAILED${NC}"
echo -e "  ${YELLOW}⚠️  Warning: $TESTS_WARNING${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 TẤT CẢ TEST QUAN TRỌNG ĐÃ PASS!${NC}"
    echo -e "${GREEN}User '$USERNAME' đã được cấu hình đúng với quyền read-only.${NC}\n"
    EXIT_CODE=0
else
    echo -e "\n${RED}⚠️  CÓ $TESTS_FAILED TEST BỊ FAIL!${NC}"
    echo -e "${RED}Vui lòng kiểm tra lại cấu hình.${NC}\n"
    EXIT_CODE=1
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
echo "   ps aux         # Hoặc: ps -ef"
echo "   top            # Press 'q' để thoát"
echo ""
echo "   # Xem system resources"
echo "   df -h          # Disk usage"
echo "   free -h        # Memory (hoặc: cat /proc/meminfo)"
echo "   uptime         # System uptime"
echo ""
echo "   # Xem system info"
echo "   cat /proc/cpuinfo"
echo "   cat /proc/meminfo"
echo "   uname -a"
echo ""
echo "   # Xem network (một số có thể cần root)"
echo "   netstat -tulpn"
echo "   ss -tulpn"
echo ""
if command -v journalctl &> /dev/null; then
echo "   # Xem log"
echo "   journalctl -f"
echo "   journalctl -n 50"
echo ""
fi
echo -e "${YELLOW}3. Test thủ công:${NC}"
echo "   # Thử ghi file (phải fail)"
echo "   touch /etc/test"
echo ""
echo "   # Thử sudo (phải fail)"
echo "   sudo ls"
echo ""
echo -e "${YELLOW}4. Quick test commands:${NC}"
echo "   su - $USERNAME -c 'whoami && pwd'"
echo "   su - $USERNAME -c 'ps aux | head -10'"
echo "   su - $USERNAME -c 'df -h'"
echo "   su - $USERNAME -c 'free -h'"
echo ""
echo -e "${RED}⚠️  BẢO MẬT:${NC}"
if [ "$TEST_MODE" = true ]; then
    echo "  • Password test: TestPass123"
    echo "  • Đổi ngay: su - $USERNAME, rồi chạy: passwd"
fi
echo "  • Kiểm tra quyền: groups $USERNAME"
echo "  • Xóa user: userdel -r $USERNAME"
echo ""

exit $EXIT_CODE

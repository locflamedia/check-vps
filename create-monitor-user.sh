#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# Script: Tạo User Giám Sát Read-Only cho Linux Server
# Version: 2.0 (Production Ready)
# Author: Linux Master Server
# GitHub: github.com/locflamedia/check-vps
# ═══════════════════════════════════════════════════════════════
# Usage: 
#   sudo bash create-monitor-user.sh              # Interactive mode
#   sudo bash create-monitor-user.sh --test       # Auto test mode
#   sudo bash create-monitor-user.sh --username myuser --test
# ═══════════════════════════════════════════════════════════════

# KHÔNG dùng set -e để script không dừng khi test fail
# set -e

# ═══════════════════════════════════════════════════════════════
# COLORS & VARIABLES
# ═══════════════════════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

USERNAME="monitor"
TEST_MODE=false
VERBOSE=false
VERSION="2.0"

# ═══════════════════════════════════════════════════════════════
# ARGUMENT PARSING
# ═══════════════════════════════════════════════════════════════
show_help() {
    cat << EOF
${BOLD}${GREEN}Monitor User Creator v${VERSION}${NC}

${BOLD}USAGE:${NC}
    sudo bash $0 [OPTIONS]

${BOLD}OPTIONS:${NC}
    --test              Auto mode với password mặc định (TestPass123)
    --username NAME     Đặt tên user khác (mặc định: monitor)
    --verbose           Hiển thị chi tiết debug
    --help              Hiển thị help này
    --version           Hiển thị phiên bản

${BOLD}EXAMPLES:${NC}
    sudo bash $0
    sudo bash $0 --test
    sudo bash $0 --username readonly --test
    sudo bash $0 --test --verbose

${BOLD}DESCRIPTION:${NC}
    Script tự động tạo user với quyền read-only để giám sát server.
    User chỉ có thể xem log, process, system info nhưng KHÔNG thể
    chỉnh sửa, xóa, hoặc thay đổi cấu hình hệ thống.

${BOLD}TEST SUITE:${NC}
    - 18 test cases tự động
    - Verify quyền read-only
    - Đảm bảo KHÔNG có sudo
    - Kiểm tra security boundaries

EOF
    exit 0
}

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
        --verbose)
            VERBOSE=true
            shift
            ;;
        --version)
            echo "Monitor User Creator v${VERSION}"
            exit 0
            ;;
        --help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ═══════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════
log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# ═══════════════════════════════════════════════════════════════
# HEADER
# ═══════════════════════════════════════════════════════════════
clear
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║      █▀▄▀█ █▀█ █▄░█ █ ▀█▀ █▀█ █▀█   █░█ █▀ █▀▀ █▀█         ║
║      █░▀░█ █▄█ █░▀█ █ ░█░ █▄█ █▀▄   █▄█ ▄█ ██▄ █▀▄         ║
║                                                               ║
║           🔐 Read-Only User Creator v2.0 🔐                   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo ""

# ═══════════════════════════════════════════════════════════════
# ROOT CHECK
# ═══════════════════════════════════════════════════════════════
if [[ $EUID -ne 0 ]]; then
   log_error "Script này cần chạy với quyền root!"
   echo "Sử dụng: sudo bash $0"
   exit 1
fi

# ═══════════════════════════════════════════════════════════════
# DETECT OS
# ═══════════════════════════════════════════════════════════════
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
    OS_PRETTY=$PRETTY_NAME
    log_info "OS: ${BOLD}$OS_PRETTY${NC}"
else
    OS="unknown"
    log_warning "Không thể phát hiện OS"
fi

if [ "$TEST_MODE" = true ]; then
    log_info "Mode: ${BOLD}${YELLOW}TEST (Auto)${NC}"
else
    log_info "Mode: ${BOLD}${GREEN}INTERACTIVE${NC}"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 1: CREATE USER
# ═══════════════════════════════════════════════════════════════
echo -e "${GREEN}${BOLD}[1/6] TẠO USER${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if id "$USERNAME" &>/dev/null; then
    log_warning "User '$USERNAME' đã tồn tại!"
    if [ "$TEST_MODE" = false ]; then
        read -p "Bạn có muốn cấu hình lại quyền? (y/n): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Đã hủy"
            exit 1
        fi
    else
        log_info "Test mode: Tiếp tục với user hiện tại"
    fi
    USER_EXISTS=true
else
    USER_EXISTS=false
fi

if [ "$USER_EXISTS" = false ]; then
    log_verbose "Tạo user '$USERNAME'..."
    
    # Detect available commands
    if command -v adduser &> /dev/null && [[ "$OS" != "alpine" ]]; then
        adduser --disabled-password --gecos "" $USERNAME 2>/dev/null || \
        useradd -m -s /bin/bash $USERNAME 2>/dev/null || \
        useradd -m -s /bin/sh $USERNAME
    else
        useradd -m -s /bin/sh $USERNAME 2>/dev/null || \
        useradd -m $USERNAME
    fi
    
    # Set password
    if [ "$TEST_MODE" = false ]; then
        echo ""
        log_info "Đặt password cho user '$USERNAME':"
        passwd $USERNAME
    else
        echo "$USERNAME:TestPass123" | chpasswd 2>/dev/null || \
        echo -e "TestPass123\nTestPass123" | passwd $USERNAME 2>/dev/null
        log_success "Password: ${BOLD}TestPass123${NC}"
    fi
    
    log_success "User '$USERNAME' đã được tạo"
else
    log_info "Sử dụng user hiện có"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 2: REMOVE SUDO PRIVILEGES
# ═══════════════════════════════════════════════════════════════
echo -e "${GREEN}${BOLD}[2/6] XÓA QUYỀN SUDO${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

REMOVED_SUDO=false
if groups $USERNAME 2>/dev/null | grep -qE 'sudo|wheel|root'; then
    log_warning "User có quyền sudo, đang xóa..."
    deluser $USERNAME sudo 2>/dev/null && REMOVED_SUDO=true
    gpasswd -d $USERNAME sudo 2>/dev/null && REMOVED_SUDO=true
    gpasswd -d $USERNAME wheel 2>/dev/null && REMOVED_SUDO=true
    deluser $USERNAME wheel 2>/dev/null && REMOVED_SUDO=true
    if [ "$REMOVED_SUDO" = true ]; then
        log_success "Đã xóa quyền sudo"
    fi
else
    log_success "User không có quyền sudo"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 3: ADD TO LOG READING GROUPS
# ═══════════════════════════════════════════════════════════════
echo -e "${GREEN}${BOLD}[3/6] CẤU HÌNH QUYỀN ĐỌC LOG${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Add to adm group
if getent group adm > /dev/null 2>&1; then
    if command -v usermod &> /dev/null; then
        usermod -aG adm $USERNAME 2>/dev/null && log_success "Đã thêm vào nhóm 'adm'" || \
        (gpasswd -a $USERNAME adm 2>/dev/null && log_success "Đã thêm vào nhóm 'adm'")
    else
        addgroup $USERNAME adm 2>/dev/null && log_success "Đã thêm vào nhóm 'adm'" || \
        log_warning "Không thể thêm vào nhóm 'adm'"
    fi
else
    log_info "Nhóm 'adm' không tồn tại"
    if [[ "$OS" == "alpine" ]]; then
        log_info "Alpine Linux: Sử dụng quyền mặc định"
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 4: ADD TO SYSTEMD-JOURNAL GROUP
# ═══════════════════════════════════════════════════════════════
echo -e "${GREEN}${BOLD}[4/6] CẤU HÌNH SYSTEMD JOURNAL${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if getent group systemd-journal > /dev/null 2>&1; then
    if command -v usermod &> /dev/null; then
        usermod -aG systemd-journal $USERNAME 2>/dev/null && log_success "Đã thêm vào nhóm 'systemd-journal'"
    else
        addgroup $USERNAME systemd-journal 2>/dev/null && log_success "Đã thêm vào nhóm 'systemd-journal'"
    fi
else
    log_info "Nhóm 'systemd-journal' không tồn tại (không dùng systemd)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 5: VERIFY CONFIGURATION
# ═══════════════════════════════════════════════════════════════
echo -e "${GREEN}${BOLD}[5/6] XÁC MINH CẤU HÌNH${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "${CYAN}User ID:${NC}"
id $USERNAME

echo -e "\n${CYAN}Groups:${NC}"
groups $USERNAME

echo -e "\n${CYAN}Sudo Check:${NC}"
SUDO_CHECK=$(sudo -l -U $USERNAME 2>&1)
if echo "$SUDO_CHECK" | grep -qE "not allowed|unknown user|may not run"; then
    log_success "User KHÔNG có quyền sudo"
    HAS_SUDO=false
elif groups $USERNAME | grep -qE 'sudo|wheel'; then
    log_error "User CÓ quyền sudo (SAI!)"
    HAS_SUDO=true
else
    log_success "User KHÔNG có quyền sudo"
    HAS_SUDO=false
fi

echo -e "\n${CYAN}Home Directory:${NC}"
ls -ld /home/$USERNAME 2>/dev/null || log_info "Không có home directory"

echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 6: AUTOMATED TEST SUITE
# ═══════════════════════════════════════════════════════════════
echo -e "${BLUE}${BOLD}"
cat << "EOF"
╔════════════════════════════════════════════════════════════════╗
║                    [6/6] TEST SUITE                            ║
║              Running Automated Security Tests...               ║
╚════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0
TESTS_TOTAL=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    local test_number=$((TESTS_TOTAL + 1))
    
    ((TESTS_TOTAL++))
    
    printf "${YELLOW}[TEST %02d]${NC} %-50s " "$test_number" "$test_name"
    
    # Run test và capture exit code
    eval "$test_command" >/dev/null 2>&1
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        if [ "$expected_result" = "pass" ]; then
            echo -e "${GREEN}✅ PASS${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}❌ FAIL${NC}"
            ((TESTS_FAILED++))
            log_verbose "Expected fail but passed: $test_command"
        fi
    else
        if [ "$expected_result" = "fail" ]; then
            echo -e "${GREEN}✅ PASS${NC} ${CYAN}(blocked)${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}❌ FAIL${NC}"
            ((TESTS_FAILED++))
            log_verbose "Expected pass but failed: $test_command"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# CORE TESTS - Must Pass
# ═══════════════════════════════════════════════════════════════
echo -e "${MAGENTA}┌─ CORE SECURITY TESTS${NC}"

run_test "User exists" \
    "id $USERNAME" \
    "pass"

run_test "No sudo/wheel privileges" \
    "! groups $USERNAME | grep -qE 'sudo|wheel'" \
    "pass"

run_test "Can read /etc/passwd" \
    "su - $USERNAME -c 'cat /etc/passwd >/dev/null'" \
    "pass"

run_test "CANNOT write to /etc" \
    "su - $USERNAME -c 'touch /etc/test-write-file'" \
    "fail"

run_test "CANNOT run sudo commands" \
    "su - $USERNAME -c 'sudo ls 2>/dev/null'" \
    "fail"

run_test "Can login to shell" \
    "su - $USERNAME -c 'whoami | grep -q $USERNAME'" \
    "pass"

echo -e "${MAGENTA}└─ Core tests completed${NC}\n"

# ═══════════════════════════════════════════════════════════════
# SYSTEM MONITORING TESTS
# ═══════════════════════════════════════════════════════════════
echo -e "${MAGENTA}┌─ MONITORING CAPABILITIES${NC}"

run_test "Can view processes" \
    "su - $USERNAME -c 'ps aux >/dev/null || ps -ef >/dev/null'" \
    "pass"

run_test "Can view disk usage" \
    "su - $USERNAME -c 'df -h >/dev/null'" \
    "pass"

run_test "Can view memory info" \
    "su - $USERNAME -c 'cat /proc/meminfo >/dev/null'" \
    "pass"

run_test "Can read /proc/cpuinfo" \
    "su - $USERNAME -c 'cat /proc/cpuinfo >/dev/null'" \
    "pass"

run_test "Can check system uptime" \
    "su - $USERNAME -c 'uptime >/dev/null'" \
    "pass"

echo -e "${MAGENTA}└─ Monitoring tests completed${NC}\n"

# ═══════════════════════════════════════════════════════════════
# PRIVILEGE ESCALATION TESTS
# ═══════════════════════════════════════════════════════════════
echo -e "${MAGENTA}┌─ PRIVILEGE ESCALATION PREVENTION${NC}"

run_test "CANNOT change other user password" \
    "su - $USERNAME -c 'passwd root >/dev/null 2>&1'" \
    "fail"

run_test "CANNOT kill init process (PID 1)" \
    "su - $USERNAME -c 'kill -9 1 2>/dev/null'" \
    "fail"

run_test "CANNOT create new users" \
    "su - $USERNAME -c 'useradd testuser123 2>/dev/null'" \
    "fail"

run_test "CANNOT modify /var/log files" \
    "su - $USERNAME -c 'touch /var/log/testfile123 2>/dev/null'" \
    "fail"

echo -e "${MAGENTA}└─ Security tests completed${NC}\n"

# ═══════════════════════════════════════════════════════════════
# OPTIONAL TESTS - Warnings OK
# ═══════════════════════════════════════════════════════════════
echo -e "${MAGENTA}┌─ OPTIONAL CAPABILITIES${NC}"

# Network viewing
printf "${YELLOW}[TEST %02d]${NC} %-50s " "$((TESTS_TOTAL + 1))" "Can view network connections"
((TESTS_TOTAL++))
if su - $USERNAME -c 'ss -tulpn >/dev/null 2>&1' || su - $USERNAME -c 'netstat -tulpn >/dev/null 2>&1'; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠️  WARN${NC} ${CYAN}(limited info)${NC}"
    ((TESTS_WARNING++))
fi

# Journal logs
if command -v journalctl &> /dev/null; then
    printf "${YELLOW}[TEST %02d]${NC} %-50s " "$((TESTS_TOTAL + 1))" "Can read journal logs"
    ((TESTS_TOTAL++))
    if su - $USERNAME -c 'journalctl -n 1 --no-pager >/dev/null 2>&1'; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⚠️  WARN${NC} ${CYAN}(no systemd/journal)${NC}"
        ((TESTS_WARNING++))
    fi
fi

# /var/log access
if [ -d "/var/log" ] && [ "$(ls -A /var/log 2>/dev/null)" ]; then
    printf "${YELLOW}[TEST %02d]${NC} %-50s " "$((TESTS_TOTAL + 1))" "Can list /var/log directory"
    ((TESTS_TOTAL++))
    if su - $USERNAME -c 'ls /var/log >/dev/null 2>&1'; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⚠️  WARN${NC} ${CYAN}(permission issue)${NC}"
        ((TESTS_WARNING++))
    fi
fi

echo -e "${MAGENTA}└─ Optional tests completed${NC}\n"

# ═══════════════════════════════════════════════════════════════
# TEST RESULTS SUMMARY
# ═══════════════════════════════════════════════════════════════
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                       TEST RESULTS                             ║"
echo "╟────────────────────────────────────────────────────────────────╢"
printf "║  ${GREEN}✅ Passed:  %3d${NC}                                              ║\n" "$TESTS_PASSED"
printf "║  ${RED}❌ Failed:  %3d${NC}                                              ║\n" "$TESTS_FAILED"
printf "║  ${YELLOW}⚠️  Warning: %3d${NC}                                              ║\n" "$TESTS_WARNING"
printf "║  ${CYAN}📊 Total:   %3d${NC}                                              ║\n" "$TESTS_TOTAL"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Calculate success rate
SUCCESS_RATE=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}${BOLD}🎉 ALL CRITICAL TESTS PASSED! (${SUCCESS_RATE}%)${NC}"
    echo -e "${GREEN}User '$USERNAME' đã được cấu hình đúng với quyền read-only.${NC}\n"
    EXIT_CODE=0
else
    echo -e "${RED}${BOLD}⚠️  ${TESTS_FAILED} TESTS FAILED!${NC}"
    echo -e "${RED}Vui lòng kiểm tra lại cấu hình.${NC}\n"
    EXIT_CODE=1
fi

# ═══════════════════════════════════════════════════════════════
# USAGE GUIDE
# ═══════════════════════════════════════════════════════════════
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                       HƯỚNG DẪN SỬ DỤNG                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

echo -e "${CYAN}${BOLD}1. Đăng nhập vào user monitor:${NC}"
echo "   su - $USERNAME"
if [ "$TEST_MODE" = true ]; then
    echo -e "   ${YELLOW}Password: TestPass123${NC}"
fi
echo ""

echo -e "${CYAN}${BOLD}2. Các lệnh giám sát hữu ích:${NC}"
cat << EOF
   ${GREEN}# Xem process${NC}
   ps aux | head -20
   top -n 1
   
   ${GREEN}# Xem system resources${NC}
   df -h                # Disk usage
   free -h              # Memory
   uptime               # System uptime
   
   ${GREEN}# Xem system info${NC}
   cat /proc/cpuinfo
   cat /proc/meminfo
   uname -a
   
   ${GREEN}# Xem network (một số thông tin có thể giới hạn)${NC}
   ss -tulpn
   netstat -tulpn
EOF

if command -v journalctl &> /dev/null; then
echo ""
echo "   ${GREEN}# Xem log (nếu có systemd)${NC}"
echo "   journalctl -n 50"
echo "   journalctl -f"
fi

echo ""
echo -e "${CYAN}${BOLD}3. Test thủ công nhanh:${NC}"
cat << EOF
   su - $USERNAME -c 'whoami && pwd'
   su - $USERNAME -c 'ps aux | head -10'
   su - $USERNAME -c 'df -h'
   su - $USERNAME -c 'touch /etc/test'  # Phải fail
   su - $USERNAME -c 'sudo ls'          # Phải fail
EOF

echo ""
echo -e "${RED}${BOLD}⚠️  BẢO MẬT:${NC}"
if [ "$TEST_MODE" = true ]; then
    echo -e "  ${YELLOW}•${NC} Password mặc định: TestPass123"
    echo -e "  ${YELLOW}•${NC} Đổi password ngay: ${CYAN}su - $USERNAME${NC}, sau đó chạy ${CYAN}passwd${NC}"
fi
echo -e "  ${YELLOW}•${NC} Kiểm tra quyền: ${CYAN}groups $USERNAME${NC}"
echo -e "  ${YELLOW}•${NC} Xóa user: ${CYAN}userdel -r $USERNAME${NC}"
echo -e "  ${YELLOW}•${NC} Kiểm tra lại: ${CYAN}sudo bash $0 --test${NC}"
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    SETUP COMPLETED                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

exit $EXIT_CODE

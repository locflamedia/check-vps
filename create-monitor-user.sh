#!/bin/bash

# Script: Tạo user giám sát read-only cho Linux Server
# Author: Linux Master Server
# Usage: sudo bash create-monitor-user.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

USERNAME="monitor"

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
    read -p "Bạn có muốn cấu hình lại quyền cho user này? (y/n): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    USER_EXISTS=true
else
    USER_EXISTS=false
fi

# Tạo user mới nếu chưa tồn tại
if [ "$USER_EXISTS" = false ]; then
    echo -e "${GREEN}[1/5]${NC} Tạo user '$USERNAME'..."
    adduser --disabled-password --gecos "" $USERNAME
    
    echo -e "\n${YELLOW}Đặt password cho user '$USERNAME':${NC}"
    passwd $USERNAME
else
    echo -e "${GREEN}[1/5]${NC} User đã tồn tại, bỏ qua việc tạo mới."
fi

# Xóa user khỏi nhóm sudo (nếu có)
echo -e "\n${GREEN}[2/5]${NC} Đảm bảo user KHÔNG có quyền sudo..."
if groups $USERNAME | grep -q sudo; then
    deluser $USERNAME sudo 2>/dev/null || true
    gpasswd -d $USERNAME sudo 2>/dev/null || true
    echo "  ✓ Đã xóa khỏi nhóm sudo"
else
    echo "  ✓ User không có trong nhóm sudo"
fi

if groups $USERNAME | grep -q wheel; then
    gpasswd -d $USERNAME wheel 2>/dev/null || true
    echo "  ✓ Đã xóa khỏi nhóm wheel"
fi

# Thêm vào nhóm adm để đọc log
echo -e "\n${GREEN}[3/5]${NC} Thêm user vào nhóm 'adm' (đọc log)..."
if getent group adm > /dev/null; then
    usermod -aG adm $USERNAME
    echo "  ✓ Đã thêm vào nhóm adm"
else
    echo -e "  ${YELLOW}⚠️  Nhóm 'adm' không tồn tại (có thể là CentOS/RHEL)${NC}"
fi

# Thêm vào nhóm systemd-journal
echo -e "\n${GREEN}[4/5]${NC} Thêm user vào nhóm 'systemd-journal' (đọc journal)..."
if getent group systemd-journal > /dev/null; then
    usermod -aG systemd-journal $USERNAME
    echo "  ✓ Đã thêm vào nhóm systemd-journal"
else
    echo -e "  ${YELLOW}⚠️  Nhóm 'systemd-journal' không tồn tại${NC}"
fi

# Kiểm tra kết quả
echo -e "\n${GREEN}[5/5]${NC} Kiểm tra cấu hình..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}User ID:${NC}"
id $USERNAME

echo -e "\n${YELLOW}Groups:${NC}"
groups $USERNAME

echo -e "\n${YELLOW}Sudo permissions:${NC}"
if sudo -l -U $USERNAME 2>&1 | grep -q "not allowed"; then
    echo -e "${GREEN}✓ User KHÔNG có quyền sudo (ĐÚNG)${NC}"
else
    echo -e "${RED}✗ User có quyền sudo (SAI - cần kiểm tra lại!)${NC}"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test quyền đọc
echo -e "\n${GREEN}=== Test quyền đọc ===${NC}"
echo "Thử đọc log với user '$USERNAME':"
su - $USERNAME -c "journalctl -n 5 --no-pager" 2>&1 | head -n 10

echo -e "\n${GREEN}✅ Hoàn tất!${NC}"
echo -e "\nCác lệnh hữu ích cho user '$USERNAME':"
echo "  - Xem log: journalctl -f"
echo "  - Xem syslog: tail -f /var/log/syslog"
echo "  - Kiểm tra services: systemctl status <service>"
echo "  - Xem process: ps aux hoặc top"
echo "  - Kiểm tra disk: df -h"
echo ""
echo -e "${YELLOW}Đăng nhập bằng:${NC} su - $USERNAME"
echo -e "${YELLOW}Hoặc SSH:${NC} ssh $USERNAME@<server-ip>"
echo ""
echo -e "${RED}⚠️  LƯU Ý BẢO MẬT:${NC}"
echo "  1. Đảm bảo đặt password mạnh"
echo "  2. Cân nhắc sử dụng SSH key thay vì password"
echo "  3. Định kỳ kiểm tra quyền: groups $USERNAME"
echo ""
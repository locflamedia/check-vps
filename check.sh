#!/bin/bash
# Script thu thập thông tin server Laravel + PM2

echo "================================"
echo "SERVER DIAGNOSTIC REPORT"
echo "Generated: $(date)"
echo "================================"

# 1. THÔNG TIN HỆ THỐNG
echo -e "\n[1] SYSTEM INFORMATION"
echo "Hostname: $(hostname)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME)"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"

# 2. CPU & MEMORY
echo -e "\n[2] CPU & MEMORY USAGE"
echo "--- CPU Info ---"
lscpu | grep -E "Model name|CPU\(s\)|Thread|Core"
echo -e "\n--- CPU Usage ---"
top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "CPU Usage: " 100 - $1"%"}'
echo -e "\n--- Memory Usage ---"
free -h
echo -e "\n--- Top 10 Memory Processes ---"
ps aux --sort=-%mem | head -11

# 3. DISK USAGE
echo -e "\n[3] DISK USAGE"
df -h
echo -e "\n--- Inodes Usage ---"
df -i

# 4. NETWORK
echo -e "\n[4] NETWORK INFORMATION"
echo "--- Active Connections ---"
ss -tunap | grep ESTABLISHED | wc -l
echo "Total Established Connections: $(ss -tunap | grep ESTABLISHED | wc -l)"
echo -e "\n--- Listening Ports ---"
ss -tulpn | grep LISTEN

# 5. PHP & LARAVEL
echo -e "\n[5] PHP & LARAVEL STATUS"
echo "PHP Version: $(php -v | head -1)"
echo "--- PHP-FPM Status ---"
systemctl status php*-fpm --no-pager | grep -E "Active|Main PID"
echo -e "\n--- PHP-FPM Pool Status ---"
ps aux | grep php-fpm | grep -v grep | wc -l
echo "Active PHP-FPM processes: $(ps aux | grep php-fpm | grep -v grep | wc -l)"
echo -e "\n--- PHP Configuration ---"
php -i | grep -E "memory_limit|max_execution_time|upload_max_filesize|post_max_size"

# 6. PM2 STATUS
echo -e "\n[6] PM2 PROCESSES"
pm2 list
echo -e "\n--- PM2 Detailed Info ---"
pm2 info all
echo -e "\n--- PM2 Resource Usage ---"
pm2 monit --no-daemon 2>&1 | head -20

# 7. NGINX/APACHE
echo -e "\n[7] WEB SERVER STATUS"
if systemctl is-active --quiet nginx; then
    echo "--- Nginx Status ---"
    systemctl status nginx --no-pager | grep -E "Active|Main PID"
    echo "Nginx Connections: $(ss -tan | grep :80 | wc -l)"
    nginx -t 2>&1
elif systemctl is-active --quiet apache2; then
    echo "--- Apache Status ---"
    systemctl status apache2 --no-pager | grep -E "Active|Main PID"
fi

# 8. DATABASE
echo -e "\n[8] DATABASE STATUS"
if systemctl is-active --quiet mysql; then
    echo "--- MySQL Status ---"
    systemctl status mysql --no-pager | grep -E "Active|Main PID"
    mysql -V
    echo "MySQL Connections: $(mysqladmin -u root processlist 2>/dev/null | wc -l)"
elif systemctl is-active --quiet postgresql; then
    echo "--- PostgreSQL Status ---"
    systemctl status postgresql --no-pager | grep -E "Active|Main PID"
fi

# 9. REDIS/QUEUE
echo -e "\n[9] CACHE & QUEUE STATUS"
if systemctl is-active --quiet redis; then
    echo "--- Redis Status ---"
    systemctl status redis --no-pager | grep -E "Active|Main PID"
    redis-cli info stats 2>/dev/null | grep -E "total_connections|connected_clients"
fi

# 10. LARAVEL LOGS
echo -e "\n[10] LARAVEL ERROR LOGS (Last 50 lines)"
if [ -f storage/logs/laravel.log ]; then
    tail -50 storage/logs/laravel.log
else
    echo "Laravel log file not found"
fi

# 11. PM2 LOGS
echo -e "\n[11] PM2 LOGS (Last 50 lines)"
pm2 logs --lines 50 --nostream

# 12. SYSTEM ERRORS
echo -e "\n[12] SYSTEM ERROR LOGS"
echo "--- Recent System Errors ---"
journalctl -p err -n 50 --no-pager

# 13. LOAD AVERAGE
echo -e "\n[13] LOAD AVERAGE & I/O"
echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
echo -e "\n--- I/O Stats ---"
iostat -x 1 3 2>/dev/null || echo "iostat not available"

echo -e "\n================================"
echo "REPORT COMPLETED"
echo "================================"
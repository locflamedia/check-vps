```
curl -s https://raw.githubusercontent.com/locflamedia/check-vps/main/check.sh | bash > server_diagnostic_$(date +%Y%m%d_%H%M%S).log 2>&1
```
```
curl -o create-monitor-user.sh https://raw.githubusercontent.com/locflamedia/check-vps/main/create-monitor-user.sh
chmod +x create-monitor-user.sh
sudo bash create-monitor-user.sh
```

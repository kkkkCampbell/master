mkdir -p /root/malw_parser && tee /root/malw_parser/malw_parser.sh > /dev/null <<'EOF'
#!/bin/sh

HOSTSFILE="/root/malw_parser/malwhosts.txt"

# Скачиваем hosts-файл и извлекаем только домены
wget -qO- "https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/master/hosts" \
  | awk '!/^#/ && NF >= 2 { for (i = 2; i <= NF; i++) if ($i ~ /[a-zA-Z]/) print $i }' \
  > ${HOSTSFILE}
EOF
chmod +x /root/malw_parser/malw_parser.sh
/root/malw_parser/malw_parser.sh

grep -qF '/root/malw_parser/malw_parser.sh' /etc/crontabs/root 2>/dev/null || \
    echo '0 4 * * * /root/malw_parser/malw_parser.sh' >> /etc/crontabs/root

/etc/init.d/cron restart
echo "Файл с доменами расположен в ${HOSTSFILE}"
echo "=== КОНЕЦ! ==="
echo ""

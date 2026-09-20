if [ "$1" != "noclear" ]; then clear; fi
echo ""
echo "Устанавливается парсер hosts-файла dns.malw.link"
echo ""

mkdir -p /root/malw_parser && tee /root/malw_parser/malw_parser.sh > /dev/null <<'EOF'
#!/bin/sh

HOSTSFILE="/root/malw_parser/malwhosts.txt"

# Скачиваем hosts-файл и извлекаем только домены
wget -qO- "https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/master/hosts" \
  | awk '!/^#/ && !/^0\.0\.0\.0[[:space:]]/ && NF >= 2 {
        for (i = 2; i <= NF; i++)
            if ($i ~ /[a-zA-Z]/) print $i
    }' \
  > "$HOSTSFILE"
  
if [ -t 1 ]; then
    printf 'Файл с доменами расположен в \033[33m%s\033[0m\n' "$HOSTSFILE"
else
    printf 'Файл с доменами расположен в %s\n' "$HOSTSFILE"
fi
EOF
chmod +x /root/malw_parser/malw_parser.sh
/root/malw_parser/malw_parser.sh

grep -qF '/root/malw_parser/malw_parser.sh' /etc/crontabs/root 2>/dev/null || \
    echo '0 4 * * * /root/malw_parser/malw_parser.sh' >> /etc/crontabs/root

/etc/init.d/cron restart
echo "=== КОНЕЦ! ==="
echo ""

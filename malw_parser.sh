#!/bin/sh

if [ ! -d /root/malw_parser ]; then
    mkdir -p /root/malw_parser
fi

# Скачиваем hosts-файл и извлекаем только домены
wget -qO- "https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/master/hosts" \
  | awk '!/^#/ && NF >= 2 { for (i = 2; i <= NF; i++) if ($i ~ /[a-zA-Z]/) print $i }' \
  > /root/malw_parser/malwhosts.txt	

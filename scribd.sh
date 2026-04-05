#!/bin/sh
# analyzer.sh

IFACE="awg10"
. /etc/os-release
FIRST_IN="0"
VER="0.0.65"


ifdown "$IFACE" >/dev/null 2>&1
/etc/init.d/opera-proxy restart >/dev/null 2>&1
ifup "$IFACE" >/dev/null 2>&1

# mkdir -p /opt/zapret2/scriptarchive
# if [ -d "/sys/class/net/$IFACE" ]; then
    # mv -f /opt/zapret2/init.d/openwrt/custom.d/50-quic4all.sh /opt/zapret2/scriptarchive/50-quic4all.sh >/dev/null 2>&1
# fi

clear
echo "${VER}"
echo "Перезапускаем интерфейсы"
sleep 8

# --- ЦВЕТА ---
CLR_OFF="\033[0m"; RED_BRIGHT="\033[1;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; BLUE="\033[0;34m"; CYAN="\033[0;36m"
printf "${CLR_OFF}"

# Функция для печати цветного текста без переноса строки
# cprint "ЦВЕТ" "ТЕКСТ"
cprint() {
    printf "${1}%s${CLR_OFF}" "$2"
}

# --- PODKOP GLOBAL CHECK STRINGS ---
p_check_include='Router DNS is NOT routed through sing-box|Sing-box does NOT work with FakeIP|❌ Bootstrap DNS:|❌ Main DNS:|❌ DNS on router'

# --- СПИСКИ ДЛЯ АЛЕРТОВ ---
SAME_AS_LIST="youtube russia_inside googlevideo"
WARNING_LISTS="russia_inside russia_outside cloudflare cdn_cloudflare"

# --- ЕДИНЫЙ СПИСОК СЕРВИСОВ ---
RAW_SERVICES="opera-proxy zeroblock podkop sing-box sing-box-tiny zapret zapret2 youtubeUnblock ruantiblock"

# --- СПИСОК УСТАНОВЛЕННЫХ СЕРВИСОВ/ПРОГРАММ ---
for pkg in $RAW_SERVICES; do
    if opkg list-installed | grep -q "^${pkg} - "; then
        if [ "${pkg}" = "sing-box-tiny" ]; then
            CHECKING_SERVICES="$CHECKING_SERVICES sing-box"
            continue
        fi
        CHECKING_SERVICES="$CHECKING_SERVICES ${pkg}"
    fi
done

# --- НАСТРОЙКА ЛОГИРОВАНИЯ ---
LOG_FILE="/root/analyzer.log"
rm -f "$LOG_FILE"

# --- ПРОВЕРКА ВЕРСИЙ ПОДКОП ---
PK_VER_OBSOLETE="0.5"
PK_VER_MIN="0.7"

clear
for i in $(seq 1 4); do echo ""; done

exec > >(tee -a "$LOG_FILE") 2>&1

echo "Анализ запущен: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "Лог сохраняется в: ${YELLOW}$LOG_FILE${CLR_OFF}"
echo "--------------------------------------------------------------"

# --- УСТАНОВКА ЗАВИСИМОСТЕЙ ---

_i=1
_retries=2
_opkg_timeout=3
_tmp_conf="/tmp/opkg_safe.conf"
_update_log="/tmp/opkg_update_log"

# --- ПОДГОТОВКА КОНФИГА OPKG ---
cat /etc/opkg.conf > "$_tmp_conf"
sed -i '/http_timeout/d' "$_tmp_conf"
echo "option http_timeout $_opkg_timeout" >> "$_tmp_conf"

# --- УСТАНОВКА ---
WGET_INSTALLED=0
CURL_INSTALLED=0

opkg list-installed | grep -q '^wget-ssl' && WGET_INSTALLED=1
opkg list-installed | grep -q '^curl' && CURL_INSTALLED=1

if [ $WGET_INSTALLED -eq 0 ] || [ $CURL_INSTALLED -eq 0 ]; then
    while [ "$_i" -le "$_retries" ]; do
        echo -e "${YELLOW}Попытка обновления списка пакетов:${CLR_OFF} ($_i/$_retries)"

        # Обновляем списки с перенаправлением в лог
        # Используем временный конфиг
        if opkg -f "$_tmp_conf" update > "$_update_log" 2>&1; then
            # Проверяем лог на наличие сетевых ошибок и ошибок opkg
            if grep -qiE "failed|error|unable|not found|returned [1-9]|bad address|refused|timeout" "$_update_log"; then
                echo -e "${RED_BRIGHT}В логе найдены ошибки скачивания, повтор...${CLR_OFF}"
            else
                echo -e "${GREEN}Списки обновлены успешно${CLR_OFF}"
                # Устанавливаем через тот же конфиг с таймаутом
                opkg -f "$_tmp_conf" install wget-ssl curl
                OPKG_UPDATED=1
                break
            fi
        fi

        if [ "$_i" -eq "$_retries" ]; then
            echo -e "${RED}Ошибка: не удалось обновить списки после $_retries попыток.${CLR_OFF}"
            echo "=== АНАЛИЗ ЛОГА (ошибки выделены) ==="
            awk 'tolower($0) ~ /failed|error|unable|not found|bad address|wget returned/ {
                print "\033[38;5;208m" $0 "\033[0m"
                next
            } {print}' "$_update_log"

            rm -f "$_tmp_conf"
            echo
            echo -e "${RED_BRIGHT}!!!_некоторые проверки будут некорректными_!!!${CLR_OFF}"
            sleep 3
        fi

        sleep 2
        _i=$((_i + 1))
    done
fi

# =====================
# ФУНКЦИИ
# =====================




# --- ФУНКЦИЯ ОЧИСТКИ СТРОКИ ОТ ЛИШНИХ ПРОБЕЛОВ, КАВЫЧЕК, НЕПЕЧАТАЕМЫХ СИМВОЛОВ И КОММЕНТАРИЕВ ---
clean_uci_str() {
    printf '%s' "$1" | tr -d '\r' | tr '\n\t' ' ' | sed \
        -e 's/[[:space:]]*[#\/].*$//' \
        -e "s/['\"]//g" \
        -e 's/[^[:print:][:space:]]//g' \
        -e 's/[[:space:]]\+/ /g' \
        -e 's/^[[:space:]]*//' \
        -e 's/[[:space:]]*$//'
}

# --- ФУНКЦИЯ ПРОВЕРКИ СОСТОЯНИЯ ИНТЕРФЕЙСОВ ---

# checkIFACE_DIAG() {
    # local iface="$1"
    
    # # 1. Тотальное отсутствие
    # if ! uci -q get network."$iface" >/dev/null; then
        # SYS_RUN="DELETED"; CONF_STAT="DELETED"; AUTO_STAT="DELETED"
        # S_CLR="${RED_BRIGHT}"; A_CLR="${RED_BRIGHT}"; C_CLR="${RED_BRIGHT}"
        # return
    # fi

    # local d_val=$(uci -q get network."$iface".disabled)
    # local a_val=$(uci -q get network."$iface".auto)

    # # 2. Логика Конфига (UCI)
    # if [ "$d_val" = "1" ]; then
        # CONF_STAT="DISABLED"; C_CLR="${RED_BRIGHT}"
    # else
        # CONF_STAT="ENABLED"; C_CLR="${CLR_OFF}"
    # fi

    # # 3. Логика Автостарта (Тот самый ахтунг)
    # if [ "$a_val" = "0" ]; then
        # AUTO_STAT="AutoStart: OFF"; A_CLR="${RED_BRIGHT}"  # КРАСНЫЙ, ибо нефиг выключать
    # else
        # # В OpenWrt отсутствие параметра = включен (1)
        # AUTO_STAT="AutoStart: ON"; A_CLR="${CLR_OFF}" 
    # fi

    # # 4. Логика Реальности (ifstatus)
    # if [ "$CONF_STAT" = "ENABLED" ]; then
        # if ifstatus "$iface" 2>/dev/null | grep -q '"up": true'; then
            # SYS_RUN="UP"; S_CLR="${GREEN}"
        # else
            # SYS_RUN="DOWN"; S_CLR="${RED_BRIGHT}"
        # fi
    # else
        # SYS_RUN="OFF"; S_CLR="${RED_BRIGHT}"
    # fi
# }



# --- ФУНКЦИЯ ПРОВЕРКИ СОСТОЯНИЯ ИНТЕРФЕЙСОВ ---
checkIFACE_DIAG() {
    local iface="$1"
    
    # Собираем базу из UCI и системы
    local d_val=$(uci -q get network."$iface".disabled || echo "0")
    local a_val=$(uci -q get network."$iface".auto || echo "1")
    local if_up=$(ifstatus "$iface" 2>/dev/null | grep -q '"up": true' && echo "up" || echo "down")

    local state_key="${d_val}:${a_val}:${if_up}"

    case "$state_key" in
        "0:1:up")
            # ИДЕАЛ: флаг ошибки в ноль, остальное можно не заполнять
            IF_ERROR=0
            SYS_RUN="UP" # На случай, если тебе всё же нужно это слово в коде
            ;;
        *)
            # ЛЮБОЙ КОСЯК: флаг в единицу и полный расклад
            IF_ERROR=1
            
            # Назначаем статусы
            [ "$d_val" = "1" ] && CONF_STAT="DISABLED" || CONF_STAT="ENABLED"
            [ "$a_val" = "0" ] && AUTO_STAT="AutoStart: OFF" || AUTO_STAT="AutoStart: ON"
            [ "$if_up" = "up" ] && SYS_RUN="UP" || SYS_RUN="DOWN"
            
            # Красим только проблемные места (пример для Auto: OFF)
            [ "$a_val" = "0" ] && A_CLR="${RED_BRIGHT}" || A_CLR="${GREEN}"
            [ "$d_val" = "1" ] && C_CLR="${RED_BRIGHT}" || C_CLR="${GREEN}"
            [ "$if_up" = "up" ] && S_CLR="${GREEN}"     || S_CLR="${RED_BRIGHT}"
            ;;
    esac
}




# --- ФУНКЦИЯ ПОИСКА ПЕРЕСЕЧЕНИЙ ПО ДОМЕНАМ В ЮЗЕРСПИСКАХ ВНУТРИ ОДНОЙ ПРОГРАММЫ ---
# $1 = имя программы. zeroblock, podkop etc.
check_userlists() {
    local pkg="${1}"
    local tmp_domains="/tmp/domains_$$.tmp"
    
    # Очищаем временный файл
    > "$tmp_domains"
    
    # Получаем список секций
    sections=$(uci -q show "$pkg" | awk -F'[.=]' '/=section$/ && $2!=""{print $2}')
    
    for section in $sections; do
        # Проверка условий
        if [ "$pkg" = "zeroblock" ]; then
            [ "$(uci -q get "$pkg.$section.enabled")" != "1" ] && continue
        fi
        [ "$(uci -q get "$pkg.$section.connection_type")" = "block" ] && continue
        
        for param in user_domains user_domains_text; do
            # Получаем значение параметра
            value=$(uci -q get "$pkg.$section.$param" 2>/dev/null)
            [ -z "$value" ] && continue
            
            # Очищаем строку через функцию clean_uci_str
            cleaned=$(clean_uci_str "$value")
            [ -z "$cleaned" ] && continue
            
            # Разбиваем по разделителям: запятая, точка с запятой, пробел, таб
            echo "$cleaned" | sed 's/[,; \t]\+/\n/g' | while IFS= read -r domain; do
                # Удаляем пробелы в начале и конце
                domain=$(echo "$domain" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                
                # Пропускаем пустые строки
                [ -z "$domain" ] && continue
                
                # Выводим домен и секцию
                echo "$domain $section"
            done
        done
    done > "$tmp_domains"
    
    # Проверяем, есть ли данные
    [ ! -s "$tmp_domains" ] && {
        rm -f "$tmp_domains"
        return
    }
    
    # Сортируем и обрабатываем
    sort "$tmp_domains" | awk -v pkg="$pkg" -v red="$RED_BRIGHT" -v clr="$CLR_OFF" '
    {
        # Собираем все секции для каждого домена
        if (!($1 in sec)) {
            sec[$1] = $2
            count[$1] = 1
        } else {
            # Добавляем секцию если её ещё нет
            if (index(" " sec[$1] " ", " " $2 " ") == 0) {
                sec[$1] = sec[$1] ", " $2
                count[$1]++
            }
        }
    }
    END {
        for (domain in sec) {
            # Выводим только если домен в 2+ секциях
            if (count[domain] > 1) {
                printf "  %s: !!!_%s%s%s > %s\n", pkg " юзерсписки", red, domain, clr, sec[domain]
            }
        }
    }'
    
    # Очистка
    rm -f "$tmp_domains"
}
# Чистим временный конфиг
[ -f "$_tmp_conf" ] && rm "$_tmp_conf"

echo ""






# --- НАКРУЧИВАЕМ СЧЁТЧИКИ AWG10 ---

TEST_URL="http://speedtest.tele2.net/10MB.zip"
ROUNDS=1
IF_IP4=$(ip -4 addr show "$IFACE" 2>/dev/null | grep -w inet | awk '{print $2}' | cut -d/ -f1 | tr -d '\r\n')
for i in $(seq 1 "$ROUNDS"); do
    curl -4 -L -A 'Mozilla/5.0' -s --no-progress-meter --interface "$IFACE" --max-time 20 --connect-timeout 10 --retry 0 --insecure --tlsv1.2 "$TEST_URL" >/dev/null 2>&1 || true
    sleep 1
done

LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | sed 's/ //g')
MEM_T=$(free | grep Mem | awk '{print $2}'); MEM_U=$(free | grep Mem | awk '{print $3}')
MEM_P=$((MEM_U * 100 / MEM_T))
LAN_IP=$(ip addr show br-lan 2>/dev/null | grep -w inet | awk '{print $2}' | cut -d/ -f1)
[ -z "$LAN_IP" ] && LAN_IP=$(uci -q get "network.lan.ipaddr")
NAND_PART=$(df | grep -q "/overlay" && echo "/overlay" || echo "/"); NAND_PCT=$(df -h "$NAND_PART" | awk 'NR==2 {print $5}'); NAND_FREE=$(df -h "$NAND_PART" | awk 'NR==2 {print $4}')






# --- БЛОК 1: ПРОВЕРКА DNS ---
echo "= ПРОВЕРКА DNS  (Прошивка: ${VERSION}):"
DNS_SRV=$(nslookup ya.ru 2>/dev/null | grep "Address:" | head -1 | awk '{print $2}')
DNS_REDIR=$(uci -q get "dhcp.@dnsmasq[0].server" 2>/dev/null)
if [ -z "$DNS_REDIR" ]; then
    DNS_REDIR="${RED_BRIGHT}!!!_ПЕРЕНАПРАВЛЕНИЯ ОТСУТСТВУЮТ${CLR_OFF}"
fi

printf "  DNS Server:   %s" "${DNS_SRV:-UNKNOWN} |"
printf " DNS Redirect: $DNS_REDIR\n"
# FB_IP=$(nslookup facebook.com 127.0.0.1 2>/dev/null | grep -A 1 "Name:" | grep "Address" | awk '{print $2}' | head -1)
# YT_IP=$(nslookup www.youtube.com 127.0.0.1 2>/dev/null | grep -A 1 "Name:" | grep "Address" | awk '{print $2}' | head -1)

FB_IP=$(nslookup facebook.com 2>/dev/null | grep -A 1 "Name:" | grep "Address" | awk '{print $2}' | head -1)
YT_IP=$(nslookup www.youtube.com 2>/dev/null | grep -A 1 "Name:" | grep "Address" | awk '{print $2}' | head -1)
printf "  Facebook IP:  ${YELLOW}%s${CLR_OFF}" "${FB_IP:-UNKNOWN}"
printf " | YouTube IP:  ${YELLOW}%s${CLR_OFF}\n" "${YT_IP:-UNKNOWN}"











# --- СОБИРАЕМ СПИСОК ЗАПУЩЕННЫХ СЕРВИСОВ ---
runned=""
for s in $CHECKING_SERVICES; do
    # init.d status check
	[ ! -f /etc/init.d/${s} ] && continue
    status=$(/etc/init.d/$s status 2>/dev/null | head -1)
    case "$status" in
        *running)
            runned="$runned $s"
            continue
            ;;
        *not\ running*)
            runned="$runned $s"
            continue
            ;;
        *inactive*)
            continue
            ;;
    esac
    
    # fallback checks if init.d status gave no clear result
    if pidof "$s" >/dev/null 2>&1 || \
       pgrep -f "$s" >/dev/null 2>&1 || \
       ubus call service list 2>/dev/null | grep -q "\"$s\""; then
        runned="$runned $s"
    fi
done
runned="${runned# }"
# echo "$runned"







# --- ОПРЕДЕЛЯЕМ СОСТОЯНИЕ СЕРВИСОВ И ОСТАНАВЛИВАЕМ МЕШАЮЩИЕ ---
# В $CHECKING_SERVICES содержатся имена установленных сервисов обхода
active=""

# Останавливаем сервисы (даже если они не запущены)
for pkg in $CHECKING_SERVICES; do
	[ -f /etc/init.d/${pkg} ] && /etc/init.d/${pkg} stop >/dev/null 2>&1
done
[ -f /etc/init.d/opera-proxy ] && /etc/init.d/opera-proxy start # Запускаем opera-proxy (так проще :))




# Проверяем сервисы в автозапуске. Все с автозапуском вносим в $active
# вне зависимости от их состояния. Необходимо получить информацию о том
# что запущено на роутере после его перезагрузки
for pkg in $CHECKING_SERVICES; do
	if ls /etc/rc.d/S??${pkg} 1>/dev/null 2>&1; then
		active="$active ${pkg}"
	fi
done





# --- БЛОК 2: ИНТЕРФЕЙС awg10 (ДЕТАЛИ) ---
NEED_RESOLVE_TEST=0
if [ -d "/sys/class/net/$IFACE" ]; then
    echo ""
    echo "= ИНТЕРФЕЙС awg10 (ДЕТАЛИ):"

	checkIFACE_DIAG "$IFACE"

	# 1. Если есть отклонение — вываливаем подробности
	if [ "$IF_ERROR" -eq 1 ]; then
		printf "  %-7s : [ %b%s%b ] | %b%s%b | %b%s%b\n" \
			"$IFACE" "$S_CLR" "$SYS_RUN" "$CLR_OFF" \
			"$C_CLR" "$CONF_STAT" "$CLR_OFF" \
			"$A_CLR" "$AUTO_STAT" "$CLR_OFF"
	fi

    # 2. Получаем RX/TX
    PING_COUNT=10
    RX=$(ifconfig "$IFACE" | grep "RX bytes" | awk '{print $2}' | cut -d: -f2 | awk '{printf "%.2f MB", $1/1048576}')
    TX=$(ifconfig "$IFACE" | grep "TX bytes" | awk '{print $6}' | cut -d: -f2 | awk '{printf "%.2f MB", $1/1048576}')
	

    # 3. Цвет RX
    RX_COLOR_VAR=$(echo "$RX" | awk '{if ($1 < 1) print "RED"; else if ($1 < 10) print "YELLOW"; else print "GREEN"}')
    case "$RX_COLOR_VAR" in
        RED)    RX_COLOR="$RED_BRIGHT" ;;
        YELLOW) RX_COLOR="$YELLOW" ;;
        GREEN)  RX_COLOR="$GREEN" ;;
        *)      RX_COLOR="$GREEN" ;;
    esac

    # 4. Выводим строку статуса
    printf "  ${S_CLR}${SYS_RUN}${CLR_OFF}${A_CLR}${AUTO_STAT}${CLR_OFF}"
    printf "[${RX_COLOR}↓${RX}${CLR_OFF}/${RX_COLOR}↑${TX}${CLR_OFF}]"

    # Запускаем пинг, собираем вывод без промежуточных сообщений
    PING_RAW=$(ping -I "$IFACE" -c $PING_COUNT ya.ru 2>&1)
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        P_MIN=$(echo "$PING_RAW" | tail -1 | awk -F'/' '{print $4}' | awk '{print $NF}')
        P_MAX=$(echo "$PING_RAW" | tail -1 | awk -F'/' '{print $5}')
        P_LOSS_PCT=$(echo "$PING_RAW" | grep "packet loss" | awk -F'%' '{print $1}' | awk '{print $NF}')
        P_LOST_NUM=$(( (PING_COUNT * P_LOSS_PCT) / 100 ))

        MIN_CLR="${GREEN}";[ "$(echo "$P_MIN" | cut -d. -f1)" -ge 150 ] && MIN_CLR="${YELLOW}"; [ "$(echo "$P_MIN" | cut -d. -f1)" -ge 250 ] && MIN_CLR="${RED_BRIGHT}"
        MAX_CLR="${GREEN}";[ "$(echo "$P_MAX" | cut -d. -f1)" -ge 150 ] && MAX_CLR="${YELLOW}"; [ "$(echo "$P_MAX" | cut -d. -f1)" -ge 250 ] && MAX_CLR="${RED_BRIGHT}"
        LOST_CLR="${GREEN}"; [ "$P_LOST_NUM" -gt 0 ] && LOST_CLR="${YELLOW}"; [ "$P_LOST_NUM" -gt 2 ] && LOST_CLR="${RED_BRIGHT}"

        # Допечатываем статистику пинга в ту же строку
        printf "[${MIN_CLR}%s${CLR_OFF}/${MAX_CLR}%s${CLR_OFF}(${LOST_CLR}%d из %d${CLR_OFF})" \
               "$P_MIN" "$P_MAX" "$P_LOST_NUM" "$PING_COUNT" 
		printf "]\n"
    else
        _P_ERR=$(echo "$PING_RAW" | head -n 1 | sed "s/ping: //")
        printf "[${RED_BRIGHT}ERROR: ${CLR_OFF} ${YELLOW}%s${CLR_OFF}" "$_P_ERR"
		printf "]\n"
    fi
else 
	sleep 3 # если пропускаем проверку авг10, то даём 3 секунды опере на взлёт
fi





echo ""





# # --- БЛОК 3: ПРОВЕРКА ДОСТУПОВ ---



# # --- ПРОВЕРКА ДОСТУПА ЧЕРЕЗ WAN-ИНТЕРФЕЙС ---

# # 1. Определяем шлюз и интерфейс
# WAN_INFO=$(ip route | grep "^default" | head -n 1)
# WAN_IFACE=$(echo "$WAN_INFO" | awk '{print $5}')

# printf "= СОСТОЯНИЕ КАНАЛА (WAN):\n"

# if [ -z "$WAN_IFACE" ]; then
    # printf "  Статус: ${RED_BRIGHT}ОФЛАЙН (Маршрут по умолчанию отсутствует)${CLR_OFF}\n"
    # WAN_READY=0
# else
    # # 2. Быстрая проверка "физики" (пингуем шлюз провайдера 1 раз)
    # WAN_GW=$(echo "$WAN_INFO" | awk '{print $3}')
    # if ping -c 1 -W 2 "$WAN_GW" >/dev/null 2>&1; then
        # # 3. Проверка реального инета (пингуем 8.8.8.8)
        # if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            # printf "${GREEN}  Статус: ОНЛАЙН (%s через %s)${CLR_OFF}\n" "$WAN_IFACE" "$WAN_GW"
            # WAN_READY=1
        # else
            # printf "  Статус: ${YELLOW}ЛОКАЛ (Шлюз %s доступен, инета нет)${CLR_OFF}\n" "$WAN_GW"
            # WAN_READY=0
        # fi
    # else
        # printf "  Статус: ${RED_BRIGHT}ОФЛАЙН (Шлюз %s не отвечает)${CLR_OFF}\n" "$WAN_GW"
        # WAN_READY=0
    # fi
# fi

# # --- 1. ПРОВЕРКА OPERA ---


# TEST_URL="https://www.youtube.com"
# CLEAN_URL="${TEST_URL#*://}"
# CLEAN_URL=$(echo "$CLEAN_URL" | tr 'a-z' 'A-Z')
# echo "= ПРОВЕРКА ДОСТУПОВ (${CLEAN_URL}):"

# PROXY_URL="http://127.0.0.1:18080"
# NEED_RESOLVE_TEST=0

# # 1. Проверка OPERA
# if opkg list-installed | grep -q "^opera-proxy"; then

    # RAW_OUT=$(curl -v -4 -I --no-progress-meter --connect-timeout 10 -x "${PROXY_URL}" "${TEST_URL}" 2>&1)
    
    # # Забираем финальный статус
    # P_CODE=$(echo "$RAW_OUT" | grep "HTTP/" | tail -n 1 | tr -d '\r\n')

    # # Если 200 или 204 — это ОНЛАЙН
    # if echo "$P_CODE" | grep -qE " 200| 204"; then
        # # Формируем человекочитаемую строку с OK и красим ВСЁ в зеленый
        # P_STATUS=$(echo "$P_CODE" | sed -E 's/(200|204)[ ]*$/\1 OK/')
        # printf "  OPERA (Proxy):${GREEN} ОНЛАЙН (%s)${CLR_OFF}\n" "$P_STATUS"
    # else
        # # ОФЛАЙН — красим только статус, подробности оставляем обычными для читаемости
        # printf "  OPERA (Proxy): ${RED_BRIGHT}ОФЛАЙН [%s]${CLR_OFF}\n" "${P_CODE:-Error}"
        
        # # Фильтруем мясо: CONNECT и ответы сервера
        # DETAILS=$(echo "$RAW_OUT" | grep -E "CONNECT|^< HTTP/" | grep -v -E "^[><][[:space:]]*$")

        # if [ -n "$DETAILS" ]; then
            # echo "$DETAILS" | sed 's/^/                 /'
        # else
            # # Вывод системной ошибки curl, если до протокола не дошло
            # echo "$RAW_OUT" | grep "curl: (" | head -n 1 | sed 's/^/                 /'
        # fi
        
        # NEED_RESOLVE_TEST=1
    # fi
# fi






# # --- 2. ПРОВЕРКА ИНТЕРФЕЙСА AWG10 ---


# if [ -d "/sys/class/net/$IFACE" ]; then
    # IF_IP4=$(ip -4 addr show "$IFACE" 2>/dev/null | grep -w inet | awk '{print $2}' | cut -d/ -f1 | tr -d '\r\n')
    # IF_IP6=$(ip -6 addr show "$IFACE" 2>/dev/null | grep -w inet6 | grep -v "fe80" | awk '{print $2}' | cut -d/ -f1 | head -n 1 | tr -d '\r\n')
	
# # --- IPv4 с подсчётом попыток ---
	# if [ -n "$IF_IP4" ]; then
    # MAX_RETRIES=2
    # TRY=0
    # SUCCESS=0
    # FINAL_W_CODE=""
    # FINAL_TLS=""
    # FINAL_FULL_OUT=""

    # # Сначала пробуем TLSv1.3
    # for tls_ver in tlsv1.3 tlsv1.2; do
        # for attempt in $(seq 1 $MAX_RETRIES); do
            # TRY=$((TRY + 1))
            # FULL_OUT=$(curl -4 -I -A -s --no-progress-meter --user-agent 'Mozilla/5.0' \
                # --interface "$IFACE" --max-time 20 --connect-timeout 9 \
                # --insecure --$tls_ver "$TEST_URL" 2>&1)
            # W_CODE=$(echo "$FULL_OUT" | awk '/HTTP\// {print; exit}')
            # if [ -n "$W_CODE" ]; then
                # SUCCESS=1
                # FINAL_W_CODE="$W_CODE"
                # FINAL_TLS="$tls_ver"
                # FINAL_FULL_OUT="$FULL_OUT"
                # break 2   # выходим из двух циклов
            # fi
            # # если не успех, продолжаем
        # done
    # done

    # if [ $SUCCESS -eq 1 ]; then
        # # Убираем лишние пробелы и перевод строк
        # W_CODE_CLEAN=$(echo "$FINAL_W_CODE" | tr -d '\r' | sed 's/[[:space:]]*$//')
        # printf "  %-14s %b (%s) [%s] [try: %d]\n" \
            # "$IFACE (IPv4) :" "${GREEN}ОНЛАЙН${CLR_OFF}" \
            # "$W_CODE_CLEAN OK" "$FINAL_TLS" "$TRY"
    # else
        # # Ошибка: последняя непустая строка из последнего FULL_OUT
        # LAST_ERR=$(echo "$FULL_OUT" | grep -v '^[[:space:]]*$' | tail -n 1)
        # printf "  %-14s ${RED_BRIGHT}ОФЛАЙН${CLR_OFF}\n" "$IFACE (IPv4) :"
        # echo "------------------------------------------------------"
        # echo "$LAST_ERR" | sed 's/^/  / '
        # echo "------------------------------------------------------"
        # NEED_RESOLVE_TEST=1
    # fi
# fi

    # # --- IPv6 ---
    # if [ -n "$IF_IP6" ]; then
		# W_OUT6=$(wget --spider --server-response --no-check-certificate --secure-protocol=TLSv1_3 -6 --timeout=4 --tries=1 --bind-address="$IF_IP6" "$TEST_URL" 2>&1)
		# W_CODE6=$(echo "$W_OUT6" | grep "HTTP/" | head -n 1 | sed 's/^[[:space:]]*//')
		# TLS_VER6="TLSv1.3"

		# if [ -z "$W_CODE6" ]; then
			# W_OUT6=$(wget --spider --server-response --no-check-certificate --secure-protocol=TLSv1_2 -6 --timeout=4 --tries=1 --bind-address="$IF_IP6" "$TEST_URL" 2>&1)
			# W_CODE6=$(echo "$W_OUT6" | grep "HTTP/" | head -n 1 | sed 's/^[[:space:]]*//')
			# TLS_VER6="TLSv1.2"
		# fi

		# if [ -n "$W_CODE6" ]; then
			# printf "  %-14s %b (%s) [%s]\n" "$IFACE (IPv6) :" "${GREEN}ОНЛЛАЙН${CLR_OFF}" "$W_CODE6" "$TLS_VER6"
		# fi
		# # else ничего не выводим (офлайн — тишина)
	# fi
# fi


# --- БЛОК 3: ПРОВЕРКА ДОСТУПОВ ---
ERR_CHECK=0
TEST_URL="https://www.youtube.com"
CLEAN_URL=$(echo "${TEST_URL#*://}" | tr 'a-z' 'A-Z')
PROXY_URL="http://127.0.0.1:18080"
NEED_RESOLVE_TEST=0

echo "= ПРОВЕРКА ДОСТУПОВ ($CLEAN_URL):"

# --- 1. ПРОВЕРКА OPERA ---
if opkg list-installed | grep -q "^opera-proxy" && /etc/init.d/opera-proxy status 2>/dev/null | grep -q "running"; then
    RAW_OUT=$(curl -v -4 -I --no-progress-meter --connect-timeout 10 -x "${PROXY_URL}" "${TEST_URL}" 2>&1)
    P_CODE=$(echo "$RAW_OUT" | grep "HTTP/" | tail -n 1 | tr -d '\r\n')
    
    if echo "$P_CODE" | grep -qE " 200| 204"; then
        P_STATUS=$(echo "$P_CODE" | sed -E 's/(200|204)[ ]*$/\1 OK/')
        printf "  ${GREEN}OPERA (Proxy): ОНЛАЙН (%s)${CLR_OFF}\n" "$P_STATUS"
    else
        printf "  ${RED_BRIGHT}OPERA (Proxy): ОФЛАЙН [%s]${CLR_OFF}\n" "${P_CODE:-Error}"
        
        # ВОТ ОНА, ПОТЕРЯШКА:
        ERR_CHECK=$((ERR_CHECK + 1))
        
        DETAILS=$(echo "$RAW_OUT" | grep -E "^[<>][[:space:]]*(CONNECT|HTTP/)" | sed 's/^//')
        if [ -n "$DETAILS" ]; then
            echo "$DETAILS" | sed 's/^/                  /'
        else
            echo "$RAW_OUT" | grep "curl: (" | head -n 1 | sed 's/^/                  /'
        fi
        NEED_RESOLVE_TEST=1
    fi
else
    # Если прокси не установлен/не запущен — тоже считаем ошибку
    ERR_CHECK=$((ERR_CHECK + 1))
fi



# --- 2. ПРОВЕРКА ИНТЕРФЕЙСА AWG10 ---
checkIFACE_DIAG "$IFACE"

if [ "$SYS_RUN" = "UP" ]; then
	# --- IPv4 с подсчётом попыток ---
		if [ -n "$IF_IP4" ]; then
		MAX_RETRIES=3
		TRY=0
		SUCCESS=0
		FINAL_W_CODE=""
		FINAL_TLS=""
		FINAL_FULL_OUT=""

		# Сначала пробуем TLSv1.3
		for tls_ver in tlsv1.3 tlsv1.2; do
			for attempt in $(seq 1 $MAX_RETRIES); do
				TRY=$((TRY + 1))
				FULL_OUT=$(curl -4 -I -A -s --no-progress-meter --user-agent 'Mozilla/5.0' \
					--interface "$IFACE" --max-time 22 --connect-timeout 7 \
					--insecure --$tls_ver "$TEST_URL" 2>&1)
				W_CODE=$(echo "$FULL_OUT" | awk '/HTTP\// {print; exit}')
				if [ -n "$W_CODE" ]; then
					SUCCESS=1
					FINAL_W_CODE="$W_CODE"
					FINAL_TLS="$tls_ver"
					FINAL_FULL_OUT="$FULL_OUT"
					break 2   # выходим из двух циклов
				fi
				# если не успех, продолжаем
			done
		done

		if [ $SUCCESS -eq 1 ]; then
			# Убираем лишние пробелы и перевод строк
			W_CODE_CLEAN=$(echo "$FINAL_W_CODE" | tr -d '\r' | sed 's/[[:space:]]*$//')

			# Проверяем количество попыток для выбора цвета
			if [ "$TRY" -gt 3 ]; then
				TRY_CLR="${YELLOW}"
			else
				TRY_CLR="${GREEN}" # Оставляем зеленым, если попыток мало
			fi

			# Собираем "сэндвич": Зеленый -> Желтый (для Try) -> Зеленый -> Сброс
			printf "${GREEN}  %-14s %s (%s OK) [%s] [try: %b%d${GREEN}]${CLR_OFF}\n" \
				"$IFACE (IPv4) :" \
				"ОНЛАЙН" \
				"$W_CODE_CLEAN" \
				"$FINAL_TLS" \
				"$TRY_CLR" \
				"$TRY"
		else
			# Ошибка: последняя непустая строка из последнего FULL_OUT
			LAST_ERR=$(echo "$FULL_OUT" | grep -v '^[[:space:]]*$' | tail -n 1)
			printf "  %-14s ${RED_BRIGHT}ОФЛАЙН${CLR_OFF}\n" "$IFACE (IPv4) :"
			echo "------------------------------------------------------"
			echo "$LAST_ERR" | sed 's/^/  / '
			echo "------------------------------------------------------"
			ERR_CHECK=$((ERR_CHECK + 1))
			NEED_RESOLVE_TEST=1
		fi
	fi
fi

if [ ! "$SYS_RUN" = "UP" ]; then
    # # Только если UP, мучаем его курлом
	# if curl -4 -I -s --interface "$IFACE" --max-time 21 --connect-timeout 10 "$TEST_URL" >/dev/null 2>&1; then
		# # Красим ВСЮ строку в зеленый
		# printf "${GREEN}  %-14s ОНЛАЙН (200 OK)${CLR_OFF}\n" "$IFACE (IPv4) :"
	# else
		# # Красим ВСЮ строку в ярко-красный
		# printf "${RED_BRIGHT}  %-14s ОФЛАЙН${CLR_OFF}\n" "$IFACE (IPv4) :"
		
		# ERR_CHECK=$((ERR_CHECK + 1))
		# NEED_RESOLVE_TEST=1
	# fi
# else

# S_CLR — Цвет для реальности (SYS_RUN).

# A_CLR — Цвет для автостарта (AUTO_STAT). Красный, если OFF, потому что «нельзя».

# C_CLR — Цвет для конфига (CONF_STAT). Можно оставить белым или серым, так как DISABLED и так подсветится через SYS_RUN="OFF".
	
	# Во всех остальных случаях (OFF, STOPPED, DELETED) — просто выводим статус
	printf "  %b : [ %b %b %b ]\n" \
		"${S_CLR}${IFACE}${CLR_OFF}" \
		"${S_CLR}${SYS_RUN}${CLR_OFF}" \
		"${C_CLR}${CONF_STAT}${CLR_OFF}" \
		"${A_CLR}${AUTO_STAT}${CLR_OFF}"

    # Считаем ошибкой, если он по идее должен работать (ENABLED + AUTO: ON)
    if [ "$CONF_STAT" = "ENABLED" ] && [[ "$AUTO_STAT" == *"ON"* ]]; then
         ERR_CHECK=$((ERR_CHECK + 1))
    fi
fi

# --- 3. ПРОВЕРКА ВАНЬКИ (WAN) ---
# Срабатывает только если оба предыдущих способа не дали результата
if [ "$ERR_CHECK" -ge 2 ]; then
#    printf "\n${YELLOW}! ВСЕ ОБХОДЫ ЛЕЖАТ. ПРОВЕРЯЕМ ПРЯМОЙ КАНАЛ:${CLR_OFF}\n"
    WAN_INFO=$(ip route | grep "^default" | head -n 1)
    WAN_IFACE=$(echo "$WAN_INFO" | awk '{print $5}')

    if [ -z "$WAN_IFACE" ]; then
        printf "  Статус WAN: ${RED_BRIGHT}ПОЛНЫЙ ОФЛАЙН (Нет маршрута)${CLR_OFF}\n"
    else
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            printf "  Статус WAN: ${GREEN}ОНЛАЙН (Прямой доступ есть, обходы сломаны)${CLR_OFF}\n"
        else
            printf "  Статус WAN: ${RED_BRIGHT}ОФЛАЙН (Интернета нет совсем)${CLR_OFF}\n"
        fi
    fi
fi





# --- ЗАПУСКАЕМ РАНЕЕ ОСТАНОВЛЕННЫЕ СЕРВИСЫ
# Запускаем все сервисы из автозапуска, имена которых 
# есть в переменной $active и тем самым
# приводим роутер к состоянию 'после перезагрузки'
# printf "  ${YELLOW}Запускаем остановленные службы, ожидайте...${CLR_OFF}\n"
printf "  ${YELLOW}Программы в автозапуске:$active${CLR_OFF}\n"
#for pkg in $active; do
for pkg in $runned; do
  if [ "${pkg}" == "sing-box" ]; then continue; fi
  /etc/init.d/${pkg} start 1>/dev/null 2>&1
done

for i in $(seq 1 10); do
    if /etc/init.d/sing-box status 2>/dev/null | grep -q "running"; then
        break
    fi
    sleep 1
done



[ $NEED_RESOLVE_TEST -eq 1 ] && sleep 5

# 3. Скрытый тест на резолв
if [ $NEED_RESOLVE_TEST -eq 1 ]; then
    echo "--------------------------------------------------------------"
    printf "  ! Диагностика DNS (${TEST_URL}):\n"
    nslookup ${TEST_URL} 2>&1 | \
        grep -v "Non-authoritative answer" | \
        grep -vE "^[[:space:]]*$" | \
        sed 's/^/    /' | \
        awk '
            /    Server:/ { next }
            /    Address:.*:[0-9]+$/ { sub(/Address/, "Server"); print; next }
            /    Name:/ { name = $0; next }
            /    Address:/ && name != "" { print name "    " $0; name = ""; next }
            { print }
        '
    echo "--------------------------------------------------------------"
fi

# if [ $NEED_RESOLVE_TEST -eq 1 ]; then
    # echo "--------------------------------------------------------------"
    # printf "  ! Диагностика DNS (youtube.com):\n"
    # nslookup youtube.com 2>&1 | \
        # grep -v "Non-authoritative answer" | \
        # grep -vE "^[[:space:]]*$" | \
        # sed 's/^/    /'
    # echo "--------------------------------------------------------------"
# fi







# --- БЛОК 4: СТАТУС СЛУЖБ ---
echo ""
echo "= СТАТУС СЛУЖБ (НЕ УСТАНОВЛЕННЫЕ НЕ ОТОБРАЖАЮТСЯ):"
# echo "=============================================================="
ZB_RUN=0; zeroblock status 2>/dev/null | grep -q "Overall: RUNNING" && ZB_RUN=1
# Если есть таблица "PodkopTable", значит подкоп запущен
PK_RUN=0; nft list tables 2>/dev/null | grep -q "PodkopTable" && PK_RUN=1

PK_INST=0; [ -f "/etc/init.d/podkop" ] && PK_INST=1
PK_AUTOSTART=0; echo $active | grep -q "podkop" && PK_AUTOSTART=1
ZB_AUTOSTART=0; echo $active | grep -q "zeroblock" && ZB_AUTOSTART=1
CHAOS=0; [ $ZB_AUTOSTART -eq 1 ] && [ $PK_AUTOSTART -eq 1 ] && CHAOS=1

for s in $CHECKING_SERVICES; do
    [ -f "/etc/init.d/$s" ] || continue

    # Сброс переменных для каждой итерации
    ST_T=""; ST_C="${RED_BRIGHT}"; S_C=""; M_T=""; M_C=""

    if [ "$s" = "sing-box" ]; then
        # Честная проверка процесса без порта-насруллы
        if [ -n "$(pidof sing-box)" ]; then
            SB_ALIVE=1; ST_T="RUNNING"; ST_C="${GREEN}"
        else
            SB_ALIVE=0; ST_T="STOPPED"; ST_C="${RED_BRIGHT}"
        fi

        # Добавляем оркестратора в хвост
        if [ $CHAOS -eq 1 ]; then
            ST_T="$ST_T (MANAGED BY CHAOS!)"; ST_C="${RED_BRIGHT}"; S_C="${RED_BRIGHT}"
        elif [ $ZB_RUN -eq 0 ] && [ $PK_INST -eq 1 ]; then
            ST_T="$ST_T (MANAGED BY PODKOP)"
        elif [ $ZB_RUN -eq 1 ]; then
            ST_T="$ST_T (MANAGED BY ZB)"
        fi

        # Статус подкопа, запущен/нет
        if [ "$s" = "podkop" ]; then
            if [ "$PK_RUN" == "1" ]; then
                ST_T="RUNNING"; ST_C="${GREEN}"
            fi
        fi
    else
        # Стандартные службы
        /etc/init.d/$s status 2>/dev/null | grep -q "running" && { ST_T="RUNNING"; ST_C="${GREEN}"; } || ST_T="STOPPED"

        # Для запрет2 отдельная проверка
        if [ "$s" = "zapret2" ]; then
            /etc/init.d/zapret2 status 2>/dev/null | grep -q "not running" && { ST_T="STOPPED"; ST_C="${RED_BRIGHT}"; }
        fi
    fi

    # СТАТУС АВТОЗАПУСКА
    /etc/init.d/$s enabled 2>/dev/null && { au_t="РАЗРЕШЁН"; au_c="${GREEN}"; } || { au_t="ОТКЛ"; au_c="${RED_BRIGHT}"; }

    # ВЫВОД СТРОКИ (Жесткое выравнивание 30 символов)
    printf "  %b%-15s${CLR_OFF} | " "$S_C" "$s"
    printf "${ST_C}%-30s${CLR_OFF} | " "$(echo "$ST_T" | tr 'a-z' 'A-Z')"
    printf "${au_c}%s${CLR_OFF}\n" "$au_t"
done










# ==============================================================
# БЛОК 5: ПЕРЕСЕЧЕНИЯ ДОМЕНОВ И АНАЛИЗ КОНФИГУРАЦИИ
# ==============================================================

# --- СЕКЦИЯ Б5.1: ПОДГОТОВКА И ФИЛЬТРАЦИЯ ЖИВЫХ СЕРВИСОВ ---
echo ""
echo "= ПЕРЕСЕЧЕНИЯ ДОМЕНОВ И АНАЛИЗ КОНФИГУРАЦИИ:"
tmp_dir="/tmp/analyzer_parts"; mkdir -p "$tmp_dir"; rm -f "$tmp_dir"/*
ACTIVE_PKGS=""

ZB_ERR=0

for pkg in $CHECKING_SERVICES; do

    # # Проверка на существование
    # [ -f "/etc/rc.d/S??$pkg" ] || continue
    # [ -f "/etc/config/$pkg" ] || continue

    # Нет сервиса или он STOPPED + DISABLED — не тестируем
    # исключение для ZB
    IS_RUNNING=0; /etc/init.d/$pkg status 2>/dev/null | grep -q "running" && IS_RUNNING=1
    IS_ENABLED=0; /etc/init.d/$pkg enabled 2>/dev/null && IS_ENABLED=1

    # выводим лог с возможной причиной незапуска ЗероБлок
    if [ "$pkg" = "zeroblock" ] && [ "$IS_RUNNING" = "0" ]; then
	logread | grep -n 'Starting ZeroBlock' | tail -1 | cut -d: -f1 | while read n; do logread | tail -n +$n | head -5 | sed -e 's/ daemon\.err zeroblock\[[0-9]*\]: / /' -e 's/\[config_builder\] //' -e 's/\[zeroblock\] //' -e 's/^/  /'; done
        ZB_ERR=1
    fi

    [ $IS_RUNNING -eq 0 ] && [ $IS_ENABLED -eq 0 ] && continue

    ACTIVE_PKGS="$ACTIVE_PKGS $pkg"
    tmp_p="$tmp_dir/$pkg.tmp"

    # --- СЕКЦИЯ Б5.2: ПАРСИНГ ZAPRET (СПЕЦИФИЧНЫЙ) ---
    if [ "$pkg" = "zapret" ]; then
        # Получаем стратегию
        Z_OPTS=$(uci -q get "$pkg.config.NFQWS_OPT" | tr -d "'\"")

        # Построчно читаем и обрабатываем стратегию
        echo "$Z_OPTS" | sed 's/--new/\n/g' | while read -r section; do
            # Пропускаем пустые строки
            [ -z "$section" ] && continue
            # Получаем протокол, используемый в секции
            F_KEY=$(echo "$section" | grep -oE "\-\-filter-(l3|tcp|udp|l7|ssid)=[^ ]+" | sort | tr '\n' ' ' | sed 's/ $//')
            # Если протокол не определён, обрабатываем секции с протоколом "any" если такие есть
            [ -z "$F_KEY" ] && F_KEY="any"

            # Ищем в строке конфига "--hostlist=" и в $fr вносим имя файла со списком доменов
            echo "$section" | grep -oE "\-\-hostlist=[^ '\" ]+" | cut -d= -f2 | while read -r fp; do
                # Если файл со списком доменов пуст, выводим предупреждение
                if ! grep -q '[[:alnum:][:punct:]]' "$fp"; then
                    printf "  ${RED_BRIGHT}Файл $(basename "$fp") пустой! ${CLR_OFF}\n"
                    # Автофикс...
                    # echo "example.com" >"$fp"; /etc/init.d/zapret restart >/dev/null 2>&1
                    # echo -e "${GREEN}Выполнено! ${CLR_OFF}"
                fi

                [ -z "$fp" ] && continue
                RP=""; [ -f "$fp" ] && RP="$fp"
                [ -z "$RP" ] && [ -f "/etc/zapret/$fp" ] && RP="/etc/zapret/$fp"
                [ -z "$RP" ] && [ -f "/opt/zapret/ipset/$fp" ] && RP="/opt/zapret/ipset/$fp"

                if [ -n "$RP" ]; then
                    fname=$(basename "$RP")
                    while read -r d; do
                        case "$d" in ""|\#*) continue ;; esac
                        dom=$(echo "$d" | awk '{print $1}')
                        if echo "$dom" | grep -qE "^[^[:space:]]+\.[^[:space:]]+$"; then
                            echo "$dom|$fname|$F_KEY" >> "$tmp_p"
                        fi
                    done < "$RP"
                fi
            done
        done
        [ -f "$tmp_p" ] && cut -d'|' -f1 "$tmp_p" | sort -u > "$tmp_dir/$pkg.doms"
        continue
    fi

    # --- СЕКЦИЯ Б5.3: ОБЩИЙ ПАРСИНГ (ZEROBLOCK, PODKOP И ДР.) ---

    SEARCH_STR="community_lists|sni_domains|user_domains_text|user_subnets_text|user_domain_lists"
    uci -q show "$pkg" | grep -Ei "${SEARCH_STR}" | while read -r line; do
        opt_path="${line%%=*}" # получаем полное наименование uci.параметра
        s_name=$(echo "$line" | cut -d. -f2) # получаем имя секции в конфиге

		# Проверка на server_community_lists
		echo "$opt_path" | grep -q "server_community_lists" && continue

        # При проверке ютубанблока формат записи конфига в uci иной
        if [ "$pkg" = "youtubeUnblock" ]; then
            s_name=$(uci -q get "$pkg.$s_name.name")
        fi

        # echo "$s_name $pkg"

        # s_name=$(uci -q get "$pkg.$s_id.name" 2>/dev/null || echo "$s_id")
        # s_content=$(uci -q show "$pkg" | grep -Ei "$pkg.s_name.$line")

        # проверяем активность секции зероблок
        if [ "${pkg}" = "zeroblock" ]; then
			s_en=$(uci -q get "$pkg.$s_name.enabled")
			[ "$s_en" != "1" ] && continue
        fi

        msg="default"
		
		# Собираем и обрабатываем домены
        val_str=$(uci -q get "$opt_path")
		
		# Удаляем комментарии, кавычки, непечатаемые символы и лишние пробелы
		result=$(clean_uci_str "$val_str")
		val_str="$result"
		
		for v in $val_str; do
            dom=$(echo "$v" | awk '{print $1}')
            [ -z "$dom" ] && continue

            IS_M=0
            # for pattern in $SAME_AS_LIST; do
            # [ "$dom" = "$pattern" ] && { IS_M=1; break; }
            # done

            pattern="${SAME_AS_LIST// /|}"
            if echo "$dom" | grep -qE "^($pattern)$"; then IS_M=1; fi
            if [ $IS_M -eq 1 ] || echo "$dom" | grep -qE "^[^[:space:]]+\.[^[:space:]]+$"; then
                echo "$dom|$s_name|default" >> "$tmp_p"

                # Резолвим виртуальные группы в реальные домены для поиска пересечений
                if echo "$dom" | grep -qE "^($pattern)$"; then
                    echo "youtube.com|$s_name|${msg}" >> "$tmp_p"
                    echo "googlevideo.com|$s_name|${msg}" >> "$tmp_p"
                fi
            fi
        done
    done

    # Парсинг внешних файлов хостлистов (если есть)
    # echo "Парсинг внешних файлов хостлистов $pkg"
    uci -q show "$pkg" | grep -Ei "\-\-hostlist=" | while read -r line; do
        # echo "$pkg $line"
        s_id=$(echo "$line" | cut -d. -f2); s_name=$(uci -q get "$pkg.$s_id.name" 2>/dev/null || echo "$s_id")
        paths=$(echo "$line" | cut -d'=' -f2 | tr -d "'\""); for fp in $paths; do
            [ -f "$fp" ] && while read -r d; do
                case "$d" in ""|\#*) continue ;; esac
                dom=$(echo "$d" | awk '{print $1}')
                if echo "$dom" | grep -qE "^[^[:space:]]+\.[^[:space:]]+$"; then
                    echo "$dom|$s_name:$(basename "$fp")|default" >> "$tmp_p"
                fi
            done < "$fp"
        done
    done
    [ -f "$tmp_p" ] && cut -d'|' -f1 "$tmp_p" | sort -u > "$tmp_dir/$pkg.doms"
done

# --- СЕКЦИЯ Б5.5: ВНУТРЕННИЕ ПЕРЕСЕЧЕНИЯ ---

for pkg in $ACTIVE_PKGS; do
    # Zapret пропускаем (его проверяет Б5.7 "Колымага")
    [ "$pkg" = "zapret" ] && continue

    tmp_p="$tmp_dir/$pkg.tmp"; [ -s "$tmp_p" ] || continue
    bad_list=$(sort "$tmp_p" | uniq -d | cut -d'|' -f1 | sort -u)

    if [ -n "$bad_list" ]; then
        printf "  !!!_${RED_BRIGHT}КРИТ:${CLR_OFF} Внутреннее пересечение в ${YELLOW}%s${CLR_OFF}:\n" "$pkg"
        echo "$bad_list" | while read -r d; do
            grep "^$d|" "$tmp_p" | cut -d'|' -f2,3 | sort -u | while read -r line; do
                loc=$(echo "$line" | cut -d'|' -f1); cond=$(echo "$line" | cut -d'|' -f2)
                printf "    %-25s : %s (Условия: %s)\n" "$pkg" "$loc" "$cond"
            done
        done
        printf "    ${CYAN}Домены:${CLR_OFF} %s\n\n" "$(echo $bad_list | tr '\n' ' ')"
    fi
done

# --- СЕКЦИЯ Б5.6: ВНЕШНИЕ ПЕРЕСЕЧЕНИЯ (МЕЖДУ СЕРВИСАМИ) ---

set -- $ACTIVE_PKGS
while [ $# -gt 1 ]; do
    P1=$1; shift; tmp1_doms="$tmp_dir/$P1.doms"; [ -f "$tmp1_doms" ] || continue
    for P2 in "$@"; do
        tmp2_doms="$tmp_dir/$P2.doms"; [ -f "$tmp2_doms" ] || continue
        all_matches=$(grep -Fxf "$tmp1_doms" "$tmp2_doms")
        if [ -n "$all_matches" ]; then
            printf "  !!!_${RED_BRIGHT}КРИТ:${CLR_OFF} Пересечение между ${YELLOW}%s${CLR_OFF} и ${YELLOW}%s${CLR_OFF}:\n" "$P1" "$P2"
            # Показываем, откуда ноги растут (первый попавшийся дубль для примера)
            echo "$all_matches" | head -n 1 | while read -r m; do
                grep "^$m|" "$tmp_dir/$P1.tmp" | cut -d'|' -f2 | sort -u | while read -r s; do printf "    %-25s : %s\n" "$P1" "$s"; done
                grep "^$m|" "$tmp_dir/$P2.tmp" | cut -d'|' -f2 | sort -u | while read -r s; do printf "    %-25s : %s\n" "$P2" "$s"; done
            done
            printf "    ${CYAN}Домены:${CLR_OFF} %s\n\n" "$(echo $all_matches | tr '\n' ' ')"
        fi
    done
done

# --- СЕКЦИЯ Б5.7: КОЛЫМАГА (ОТДЕЛЬНЫЙ АНАЛИЗ ПЕРЕСЕЧЕНИЙ В КОНФИГЕ ZAPRET) ---

CONF_Z="/etc/config/zapret"
if [ -f "$CONF_Z" ]; then
    F_TYPES="l3 tcp udp l7 ssid"
    for ft in $F_TYPES; do
        F_FOUND=$(grep -oE "\-\-filter-$ft=[0-9,]+" "$CONF_Z" | sort -u)
        for full_f in $F_FOUND; do
            if [ $(grep -c -e "$full_f" "$CONF_Z") -gt 1 ]; then
                HLISTS=$(sed -n "/$full_f/,/--new/p" "$CONF_Z" | grep "\-\-hostlist=" | cut -d= -f2)
                if [ "$(echo "$HLISTS" | wc -l)" -gt "$(echo "$HLISTS" | sort -u | wc -l)" ]; then
                    printf "  !!! ${RED_BRIGHT}КРИТ:${CLR_OFF} В ZAPRET секция ${CYAN}%s${CLR_OFF} дублирует хостлисты.\n" "$full_f"
                fi
            fi
        done
    done
fi
rm -rf "$tmp_dir"

# --- БЛОК 6: ГОТОВИМ СПИСКИ ОБХОДОВ/ПЕРЕСЕЧЕНИЙ ---

ALL_ITEMS=""; CONFLICT_LISTS=""

# 1. СОБИРАЕМ КОНФЛИКТЫ (Живые сервисы из ACTIVE_PKGS)

# Проверяем только zeroblock и podkop
for pkg in $ACTIVE_PKGS; do
    [ "$pkg" != "zeroblock" ] && [ "$pkg" != "podkop" ] && continue

    # Получаем список имён секций в анализируемой программе
    SIDS=$(uci show "$pkg" 2>/dev/null | grep "=section$" | cut -d. -f2 | cut -d= -f1 | sort -u)

    for sid in $SIDS; do
        # Проверка активации/деактивации секций ZeroBlock!!!
        s_en=$(uci -q get "$pkg.$sid.enabled")
        if [ "${pkg}" = "zeroblock" ]; then
            [ -z "${s_en}" ] || [ $s_en -eq 0 ] && continue
        fi

        # Получаем названия списков сообщества
        RAW=$(uci -q get "$pkg.$sid.community_lists" | tr -d "'\"" | tr ' ,' '  ')

        # Проверка совпадения списков сообщества в несольких секциях
        for item in $RAW; do
            [ -z "$item" ] && continue

            IS_DUP=0
            # ПРОВЕРКА А: Физический дубль имени
            if echo " $ALL_ITEMS " | grep -q " $item "; then
                IS_DUP=1
            fi

            # ПРОВЕРКА Б: Синонимы (SAME_AS_LIST)
            case " $SAME_AS_LIST " in *" $item "*)
                for sibling in $SAME_AS_LIST; do
                    if [ "$item" != "$sibling" ] && echo " $ALL_ITEMS " | grep -q " $sibling "; then
                        IS_DUP=1
                        # Добавляем "брата", чтобы он тоже покраснел при выводе
                        case " $CONFLICT_LISTS " in *" $sibling "*) ;; *) CONFLICT_LISTS="$CONFLICT_LISTS $sibling" ;; esac
                    fi
                done
            ;; esac

            if [ $IS_DUP -eq 1 ]; then
                case " $CONFLICT_LISTS " in *" $item "*) ;; *) CONFLICT_LISTS="$CONFLICT_LISTS $item" ;; esac
            fi

            ALL_ITEMS="$ALL_ITEMS $item"
        done
    done
done










# 2. ВЫВОДИМ СПИСКИ ТОЛЬКО ДЛЯ ТЕХ, КТО В ACTIVE_PKGS

for pkg in $ACTIVE_PKGS; do
    [ "$pkg" != "zeroblock" ] && [ "$pkg" != "podkop" ] && continue

    SIDS=$(uci show "$pkg" 2>/dev/null | grep "=section$" | cut -d. -f2 | cut -d= -f1 | sort -u)

    for sid in $SIDS; do
        # Проверка активации/деактивации/родительского контроля секций ZeroBlock!!!
        s_en=$(uci -q get "$pkg.$sid.enabled")
		p_cont=$(uci -q get "$pkg.$sid.connection_type")
        if [ "${pkg}" = "zeroblock" ]; then
            [ -z "${s_en}" ] || [ $s_en -eq 0 ] && continue
			[ "$p_cont" = "block" ] && continue
        fi

        RAW=$(uci -q get "$pkg.$sid.community_lists" | tr -d "'\"" | tr ' ' ',' | sed 's/,,*/,/g' | tr ',' ' ')
        [ -z "$RAW" ] && continue

        # Получаем данные исходящего канала секции
        _conn_type=$(uci -q get "$pkg.$sid.connection_type")
        if [ "$_conn_type" = "proxy" ]; then
			_conn_type=""
			_conn_url=$(uci -q get "$pkg.$sid.proxy_config_type")
			[ -z "${_conn_url}" ] && _conn_url="ND!"
			_conn_type=$(echo "prx ${_conn_url}" | cut -c 1-7)


# # Получаем url vless итп, только в информационных целях
# _conn_type=""
# _conn_url=$(uci -q get "$pkg.$sid.proxy_string")
# _conn_type=$(echo "prx ${_conn_url}" | cut -c 1-7)
		fi

		# Выводим на экран "программа имя_списка (тип_соединения)"
		printf "  %-4s %25s " "$pkg" "${sid} (${_conn_type}):"
        # printf  "(${_conn_type}): "
        FIRST=1
        for item in $RAW; do
            [ $FIRST -eq 0 ] && printf "${CYAN},${CLR_OFF}"
            FIRST=0

            IS_CONFLICT=0; case " $CONFLICT_LISTS " in *" $item "*) IS_CONFLICT=1 ;; esac
            IS_WARN=0; for wl in $WARNING_LISTS; do [ "$item" = "$wl" ] && IS_WARN=1 && break; done

            if [ $IS_CONFLICT -eq 1 ]; then
                printf "!!!_${RED_BRIGHT}%s${CLR_OFF}" "$item"
            elif [ $IS_WARN -eq 1 ]; then
                printf "!_${YELLOW}%s${CLR_OFF}" "$item"
            else
                printf "${CYAN}%s${CLR_OFF}" "$item"
            fi
        done
        printf "\n"
    done
done







# --- БЛОК ПОИСКА СЕКЦИЙ РОДИТЕЛЬСКОГО КОНТРОЛЯ И СЕКЦИЙ БЛОКИРОВКИ ДОСТУПА В ZEROBLOCK---

PK_AUTOSTART=0
ZB_AUTOSTART=0
PK_RUNNED=0
ZB_RUNNED=0

echo "$active" | grep -q "podkop" && PK_AUTOSTART=1
echo "$active" | grep -q "zeroblock" && ZB_AUTOSTART=1
# echo "$runned" | grep -q "podkop" && PK_RUNNED=1
# echo "$runned" | grep -q "zeroblock" && ZB_RUNNED=1

if [ "${ZB_AUTOSTART}" = "1" ]; then
	pkg="zeroblock"
	_block_sections=""
	_p_cont_sections=""
	SIDS=$(uci show "$pkg" 2>/dev/null | grep "=section$" | cut -d. -f2 | cut -d= -f1 | sort -u)
	for sid in $SIDS; do
		s_en=$(uci -q get "$pkg.$sid.enabled")
			if [ "$s_en" = "1" ]; then
				conn_type=$(uci -q get "$pkg.$sid.connection_type")
				p_cont=$(uci -q get "$pkg.$sid.parental_control")
				if [ "$conn_type" = "block" ] && [ "$p_cont" != "1" ]; then _block_sections="${_block_sections} $sid"; fi
				if [ "$p_cont" = "1" ]; then _p_cont_sections="${_p_cont_sections} $sid"; fi
			fi
	done
	
	[ -n "${_block_sections}" ] && \
	printf "  %-4s %30s" "${pkg}" "режим BLOCK:" && echo -e "${RED_BRIGHT}${_block_sections}${CLR_OFF}"
	[ -n "${_p_cont_sections}" ] && \
	printf "  %-4s %30s" "${pkg}" "режим Parental_control:" && echo -e "${YELLOW}${_p_cont_sections}${CLR_OFF}"
fi





# --- БЛОК ДОПОЛНИТЕЛЬНОЙ ИНФОРМАЦИИ (ПЕРЕСЕЧЕНИЯ) ---


if [ $PK_INST -eq 1 ]; then
    # 1. Получаем DNS настройки
    PK_DNS=$(uci -q get "podkop.settings.dns_server")
    PK_B_DNS=$(uci -q get "podkop.settings.bootstrap_dns_server")

    # # 2. Получаем версию (вызываем напрямую)
    # PK_VER=$(podkop show_version 2>&1 /dev/null)

    # 2. Получаем версию подкопа
    PK_VER_RAW=$(podkop show_version 2>&1)
    PK_VER=""
    PK_OLD_FLAG=0

    # Проверка на "древность" по наличию start/stop в выводе
    if echo "$PK_VER_RAW" | grep -qE "start|stop"; then
        PK_OLD_FLAG=1
        # Попытка достать версию через opkg
        PK_VER=$(opkg list-installed podkop | awk '{print $3}')
    else
        PK_VER=$PK_VER_RAW
    fi

    # --- ПРОВЕРКА ВЕРСИЙ ПОДКОП ---

    # Очищаем версию: убираем 'v', отсекаем всё после дефиса, оставляем X.Y
    CLEAN_VER=$(echo "$PK_VER" | sed 's/^v//' | cut -d'-' -f1 | cut -d'.' -f1,2)

    # Логика определения цвета
    PK_COLOR=$GREEN  # По умолчанию зеленый
    if [ -n "$CLEAN_VER" ]; then
        # Передаем переменные внутрь awk через -v
        PK_STATUS=$(awk -v ver="$CLEAN_VER" -v obs="$PK_VER_OBSOLETE" -v min="$PK_VER_MIN" 'BEGIN {
            if (ver < obs) print "RED";
            else if (ver < min) print "YELLOW";
            else print "NORMAL";
        }')

        case "$PK_STATUS" in
            RED)    PK_COLOR=$RED_BRIGHT ;;
            YELLOW) PK_COLOR=$YELLOW ;;
        esac
    fi

    if [ $PK_AUTOSTART -eq 1 ]; then
        # Выводим DNS, только если там не пусто
        if [ -n "$PK_DNS" ] || [ -n "$PK_B_DNS" ]; then
			dns_type=""
			dns_type=$(uci -q get "podkop.settings.dns_type")
            [ -n "$PK_DNS" ] && printf "  podkop DNS/Bootstrap DNS: %b%s${CLR_OFF} " "${CYAN}" "(${dns_type}) ${PK_DNS}"
            [ -n "$PK_B_DNS" ] && printf "/ %b%s${CLR_OFF}\n" "${CYAN}" "$PK_B_DNS"
        fi
		podkop global_check | grep -E '^?|^??' | grep -E "$p_check_include" | while IFS= read -r line; do
			case $line in
				"❌"*) printf "  podkop "; printf '\033[1;31m%s\033[0m\n' "$line" ;;
				"⚠️"*) printf "  podkop "; printf '\033[0;33m%s\033[0m\n' "$line" ;;
				*) printf '%s\n' "$line" ;;
			esac
		done
    fi
fi












# --- БЛОК DNS ZEROBLOCK ---

# zeroblock.settings.dns_main_via_outbound='1'
# zeroblock.settings.dns_main_outbound='awg10'
# zeroblock.settings.dns_bootstrap_via_outbound='1'
# zeroblock.settings.dns_bootstrap_outbound='opera'

dns_main_outbound=""
dns_bootstrap_outbound=""
# [ $IS_ENABLED -eq 1 ] && [ $IS_RUNNING -eq 1 ]
if [ $ZB_AUTOSTART -eq 1 ] || [ $ZB_ERR -eq 1 ]; then
    ZB_DNS=$(uci -q get "zeroblock.settings.dns_server")
    ZB_B_DNS=$(uci -q get "zeroblock.settings.bootstrap_dns_server")
	ZB_TYPE_DNS=$(uci -q get "zeroblock.settings.dns_type")
	
	sid=""; conn_type=""
	
	# Проверяем и собираем outbounds для DNS и Bootstrap DNS
	# MAIN DNS
	if [ "$(uci -q get zeroblock.settings.dns_main_via_outbound)" = "1" ]; then
		sid="$(uci -q get zeroblock.settings.dns_main_outbound)" # секция main аутбаунд
		conn_type="$(uci -q get zeroblock.$sid.connection_type)" # тип соединения main аутбаунд
		if [ "${conn_type}" = "proxy" ]; then 
			conn_type="${conn_type} $(uci -q get zeroblock.$sid.proxy_config_type | cut -c1-4)"
			dns_main_outbound="(${conn_type} ${sid})" # тип соединения аутбаунд+имя интерфейса аутбаунд
		else
			dns_main_outbound="(${conn_type} $(uci -q get zeroblock.$sid.interface))" # тип соединения аутбаунд+имя интерфейса аутбаунд		
		fi
	fi
	
	sid=""; conn_type=""
	
	# Bootstrap DNS
	if [ "$(uci -q get zeroblock.settings.dns_bootstrap_via_outbound)" = "1" ]; then
		sid="$(uci -q get zeroblock.settings.dns_bootstrap_outbound)" # секция bootstrap аутбаунд
		conn_type="$(uci -q get zeroblock.$sid.connection_type)" # тип соединения bootstrap аутбаунд
		if [ "${conn_type}" = "proxy" ]; then 
			conn_type="${conn_type} $(uci -q get zeroblock.$sid.proxy_config_type | cut -c1-4)"
			dns_bootstrap_outbound="(${conn_type} ${sid})" # тип соединения bootstrap аутбаунд+имя интерфейса аутбаунд
		else
			dns_bootstrap_outbound="(${conn_type} $(uci -q get zeroblock.$sid.interface))" # тип соединения bootstrap аутбаунд+имя интерфейса аутбаунд		
		fi
	fi
	
    # Выводим DNS, только если там не пусто
    [ -n "$ZB_DNS" ] && printf "  %-4s%27s" "zeroblock" "DNS/Bootstrap DNS: " && \
	printf "%b%s${CLR_OFF}${CYAN}(${ZB_TYPE_DNS}) $ZB_DNS${dns_main_outbound}"
	[ -n "$ZB_B_DNS" ] && printf " / %b%s${CLR_OFF}\n" "${CYAN}" "$ZB_B_DNS${dns_bootstrap_outbound}"

    # --- Статус пользовательских скриптов zapret2 (1 - включено, 0 - выключено). Могут ломать awg10.
    if [ -f "/opt/zapret2/init.d/openwrt/custom.d/50-quic4all.sh" ]; then
        if opkg list-installed | grep -q "^zapret2"; then
            printf "  $(uci show zapret2 | grep 'custom_scripts')\n"
        fi
    fi
fi










# Ищем пересечения внутри одной программы в юзерсписках доменов (списки, созданные самостоятельно)
# ZeroBlock - отключенные секции не анализируются.
[ $PK_AUTOSTART -eq 1 ] && check_userlists "podkop"
[ $ZB_AUTOSTART -eq 1 ] && check_userlists "zeroblock"

# Печатаем допданные в конце вывода блока (надо же как-то скрипт обновлять...)
if [ $PK_AUTOSTART -eq 1 ]; then
    uci show podkop | grep -q "fully_routed_ips" && echo -e "  ${YELLOW}Полностью маршрутизированные IP-адреса включены!${CLR_OFF}"
    if [ -n "$PK_VER" ]; then
        printf "  Версия podkop: ${PK_COLOR}%s${CLR_OFF}\n" "$PK_VER"
    fi
fi

if [ $ZB_AUTOSTART -eq 1 ]; then
    _ZB_json="/tmp/zeroblock_status.json"
    # Ищем catch-all секции
    if [ -f "$_ZB_json" ]; then
        ZB_CATCH_ALL=$(grep -o '"\([^"]*\)":{"is_catch_all":true}' /tmp/zeroblock_status.json | cut -d'"' -f2)
        if [ -n "$ZB_CATCH_ALL" ]; then printf "  ${YELLOW}Секция в режиме catch-all: $ZB_CATCH_ALL${CLR_OFF}\n"; fi
    fi

    ZB_VER=$(zeroblock --version 2>/dev/null)
    uci show zeroblock | grep -q "fully_routed_ips" && echo -e "  ${YELLOW}Полностью маршрутизированные IP-адреса включены!${CLR_OFF}" && \
	printf "  " && uci show zeroblock | grep "fully_routed_ips"

    if [ -n "$ZB_VER" ]; then
        ZB_VER=$(echo "$ZB_VER" | sed 's/^ZeroBlock v//')
        printf "  Версия zeroblock: ${PK_COLOR}%s${CLR_OFF}\n" "$ZB_VER"
    fi
fi




# --- DNSMASQ SETTINGS CHECK ---


indices=$(uci show dhcp 2>/dev/null | grep -o 'dhcp\.@dnsmasq\[[0-9]*\]' | sed 's/.*\[\([0-9]*\)\]/\1/' | sort -nu)
count=$(echo "$indices" | wc -l)

if [ -z "$indices" ] || [ "$count" -eq 0 ]; then
    printf "\033[1;31m  Секции dnsmasq не найдены\033[0m\n"
fi

if [ "$count" -gt 1 ]; then
    printf "\033[1;31m  Обнаружено несколько секций dnsmasq (%d). Невозможно определить используемую.\033[0m\n" "$count"
else
	idx="$indices"
	strict=$(uci -q get "dhcp.@dnsmasq[$idx].strictorder")
	noresolv=$(uci -q get "dhcp.@dnsmasq[$idx].noresolv")

	if [ "$strict" = "1" ]; then
		printf "\033[1;31m  Ошибка: DNS и DHCP, Строгий порядок активен!\033[0m\n"
	fi

	if [ "$noresolv" != "1" ]; then
		printf "\033[1;31m  Ошибка: DNS и DHCP, Игнорировать файл resolv отключено! \033[0m\n" "${noresolv:-0}"
	fi
fi




# --- БЛОК 7: СИСТЕМНЫЕ РЕСУРСЫ ---

echo ""
echo "= СИСТЕМНЫЕ РЕСУРСЫ:"
printf "  LAN IP: %s\n" "$LAN_IP (Прошивка: ${VERSION})"
printf "  CPU: %s | RAM: %s%% | NAND: %s занято / %s доступно\n" "$LOAD" "$MEM_P" "$NAND_PCT" "$NAND_FREE"
# crontab -l | sed 's/^/  /'
crontab -l | sed -e '/^[[:space:]]*#/d' -e 's/^/  /'
if opkg list-installed | grep -q "wdoc"; then
    printf "  ${RED_BRIGHT}!!!_WatchDoc установлен${CLR_OFF}\n"
fi

# Блок 8: Очистка лога
if [ -f "$LOG_FILE" ]; then sed -i 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$LOG_FILE"; fi
echo ""

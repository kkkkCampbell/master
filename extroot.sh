#!/bin/sh
# ============================================================
#  usb-extroot.sh v0.0.1
#  Перенос overlay OpenWrt на USB-накопитель (extroot)
#  Лог: /root/usb-extroot.log
#  Бэкап: /tmp/.usb-extroot-x7k2m9q4p1w8/ (tmpfs, RAM)
# ============================================================
ver="v0.0.1"
LOG=/root/usb-extroot.log
if [ -z "$_LOGGED" ]; then
    export _LOGGED=1
    FIFO=/tmp/usb-extroot.fifo
    rm -f "$FIFO"
    mkfifo "$FIFO"
    tee -a "$LOG" < "$FIFO" &
    exec > "$FIFO" 2>&1
fi

TEST_MODE="${TEST_MODE:-0}"

PKG_REPAIR_ACTIVE=0
PKG_REPAIR_OLD_DNS=""
PKG_REPAIR_Z_STAT=""
PKG_REPAIR_Z2_STAT=""
PKG_REPAIR_Y_STAT=""
PKG_REPAIR_DNS_CHANGED=0
PKG_REPAIR_SVC_STOPPED=0

have() { command -v "$1" >/dev/null 2>&1; }

pkg_repair_finish() {
    [ "$PKG_REPAIR_ACTIVE" = "1" ] || return 0

    if [ "$PKG_REPAIR_DNS_CHANGED" = "1" ]; then
        uci -q del dhcp.@dnsmasq[0].noresolv
        if [ -n "$PKG_REPAIR_OLD_DNS" ]; then
            uci set dhcp.@dnsmasq[0].server="$PKG_REPAIR_OLD_DNS"
        else
            uci -q del dhcp.@dnsmasq[0].server
        fi
        uci commit dhcp 2>/dev/null
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
    fi

    if [ "$PKG_REPAIR_Z_STAT" = "running" ] && [ -x /etc/init.d/zapret ]; then
        /etc/init.d/zapret start >/dev/null 2>&1
    fi
    if [ "$PKG_REPAIR_Z2_STAT" = "running" ] && [ -x /etc/init.d/zapret2 ]; then
        /etc/init.d/zapret2 start >/dev/null 2>&1
    fi
    if [ "$PKG_REPAIR_Y_STAT" = "running" ] && [ -x /etc/init.d/youtubeUnblock ]; then
        /etc/init.d/youtubeUnblock start >/dev/null 2>&1
    fi

    PKG_REPAIR_ACTIVE=0
}

die() {
    pkg_repair_finish
    echo
    echo "############################################################"
    echo "#  ОШИБКА: $1"
    echo "############################################################"
    echo
    echo "$2"
    echo
    echo "############################################################"
    echo
    exit 1
}

fatal() {
    pkg_repair_finish
    FATAL_STAGE="$1"
    echo
    echo "############################################################"
    echo "#  СТОП: $1"
    echo "############################################################"
    echo
    echo "$2"
    echo
    shout_fatal
    exit 1
}

pkg_fail() {
    local stage="$1" pkg="$2" pm="$3"
    local extra=""
    if [ "$pm" = "apk" ]; then
        extra="Репозитории apk:
  /etc/apk/repositories
  /etc/apk/repositories.d/"
    else
        extra="Репозитории opkg:
  /etc/opkg.conf
  /etc/opkg/customfeeds.conf
  /etc/opkg/distfeeds.conf"
    fi
    die "$stage" "Не удалось установить пакет: $pkg
Менеджер пакетов: $pm

Скорее всего:
  - нет доступа к репозиториям, или
  - пакет заблокирован / отсутствует в фиде

Проверь вручную:
  $pm update
  $pm add $pkg

$extra

Если ставится — запусти скрипт заново.
Если нет — поставь пакеты сам и вернись."
}

detect_pm() {
    if command -v apk  >/dev/null 2>&1; then echo apk
    elif command -v opkg >/dev/null 2>&1; then echo opkg
    else echo none
    fi
}

pkg_install() {
    local pkg="$1" pm="$2"
    case "$pm" in
        apk)  apk add "$pkg" ;;
        opkg) opkg update && opkg install "$pkg" ;;
        *)    return 1 ;;
    esac
}

pkg_present() {
    local pkg="$1" pm="$2"
    case "$pkg" in
        block-mount)  have block && return 0 ;;
        kmod-fs-ext4) grep -q ext4 /proc/filesystems 2>/dev/null && return 0 ;;
        e2fsprogs)    have mkfs.ext4 && return 0 ;;
    esac
    case "$pm" in
        apk)  apk info -e "$pkg" >/dev/null 2>&1 ;;
        opkg) opkg list-installed 2>/dev/null | grep -q "^$pkg " ;;
        *)    return 1 ;;
    esac
}

parent_dev() {
    echo "$1" | sed 's|\(/dev/[a-z]*\)[0-9_]*$|\1|'
}

is_usb() {
    local b=$(basename "$1")
    case "$b" in
        sd[a-z][0-9]*|mmcblk[0-9]*p[0-9]*|nvme[0-9]*n[0-9]*p[0-9]*)
            b=$(basename "$(parent_dev "/dev/$b")")
            ;;
    esac
    case "$(readlink -f /sys/block/$b 2>/dev/null)" in *"/usb"*) return 0;; esac
    case "$(grep -h DRIVER /sys/block/$b/device/uevent 2>/dev/null)" in
        *uas*|*usb-storage*) return 0;;
    esac
    return 1
}

is_internal_dev() {
    case "$1" in
        /dev/ubi*|/dev/mtdblock*|/dev/root) return 0;;
    esac
    return 1
}

describe() {
    local dev="$1" b=$(basename "$1")
    local vendor=$(cat /sys/block/$b/device/vendor 2>/dev/null | tr -d '\n')
    local model=$(cat /sys/block/$b/device/model  2>/dev/null | tr -d '\n')
    local blocks=$(cat /sys/block/$b/size 2>/dev/null)
    local size=$(awk -v x="$blocks" 'BEGIN{printf "%.1fG", x*512/1024/1024/1024}')
    local name=$(echo "${vendor} ${model}" | sed 's/  */ /g; s/^ //; s/ $//')
    echo "$dev $size $name"
}

get_router_ip() {
    local ip
    ip=$(uci -q get network.lan.ipaddr 2>/dev/null)
    if [ -n "$ip" ]; then echo "$ip"; return; fi
    ip=$(ip -4 addr show br-lan 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    if [ -n "$ip" ]; then echo "$ip"; return; fi
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
    if [ -n "$ip" ]; then echo "$ip"; return; fi
    echo "<ip-роутера>"
}

shout_fatal() {
    local rip=$(get_router_ip)
    echo "------------------------------------------------------------"
    echo " Этап: ${FATAL_STAGE:-<неизвестен>}"
    echo
    echo " Бэкап overlay (если создан):"
    echo "   ${BACKUP_DIR:-/tmp/.usb-extroot-x7k2m9q4p1w8}/"
    echo "   (в ОЗУ — исчезнет при ребуте, скопируй сейчас, если нужен)"
    echo
    echo " НЕ ПЕРЕЗАГРУЖАЙ РОУТЕР, пока не убедишься, что:"
    echo "   - /overlay смонтирован и доступен"
    echo "   - fstab.rwm указывает на ${ORIG_DEV:-<внутренний overlay>}"
    echo "   - из бэкапа можно вернуть данные"
    echo
    echo " Шара для доступа с другой машины:"
    echo "   \\\\$rip\\overlaybackup"
    echo "   пользователь: 12345"
    echo "   пароль:       12345"
    echo "------------------------------------------------------------"
    echo
}

pkg_repair_start() {
    have uci || return 1

    PKG_REPAIR_OLD_DNS=""
    PKG_REPAIR_Z_STAT=""
    PKG_REPAIR_Z2_STAT=""
    PKG_REPAIR_Y_STAT=""
    PKG_REPAIR_DNS_CHANGED=0
    PKG_REPAIR_SVC_STOPPED=0

    if [ -x /etc/init.d/zapret ]; then
        PKG_REPAIR_Z_STAT=$(/etc/init.d/zapret status 2>/dev/null)
    fi
    if [ -x /etc/init.d/zapret2 ]; then
        PKG_REPAIR_Z2_STAT=$(/etc/init.d/zapret2 status 2>/dev/null)
    fi
    if [ -x /etc/init.d/youtubeUnblock ]; then
        PKG_REPAIR_Y_STAT=$(/etc/init.d/youtubeUnblock status 2>/dev/null)
    fi

    if [ "$PKG_REPAIR_Z_STAT" = "running" ]; then
        echo "        останавливаю zapret"
        /etc/init.d/zapret stop >/dev/null 2>&1
        PKG_REPAIR_SVC_STOPPED=1
    fi
    if [ "$PKG_REPAIR_Z2_STAT" = "running" ]; then
        echo "        останавливаю zapret2"
        /etc/init.d/zapret2 stop >/dev/null 2>&1
        PKG_REPAIR_SVC_STOPPED=1
    fi
    if [ "$PKG_REPAIR_Y_STAT" = "running" ]; then
        echo "        останавливаю youtubeUnblock"
        /etc/init.d/youtubeUnblock stop >/dev/null 2>&1
        PKG_REPAIR_SVC_STOPPED=1
    fi

    PKG_REPAIR_OLD_DNS=$(uci -q get dhcp.@dnsmasq[0].server)
    uci set dhcp.@dnsmasq[0].noresolv='1'
    uci -q del dhcp.@dnsmasq[0].server
    uci add_list dhcp.@dnsmasq[0].server='9.9.9.11'
    if uci commit dhcp 2>/dev/null; then
        PKG_REPAIR_DNS_CHANGED=1
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
    fi

    local DOMAINS="openwrt.org downloads.openwrt.org packages.routerich.ru routerich.ru github.com raw.githubusercontent.com"
    if have nslookup; then
        for d in $DOMAINS; do
            nslookup "$d" >/dev/null 2>&1
        done
    fi
    sleep 3

    local pm
    pm=$(detect_pm)
    case "$pm" in
        apk)
            echo
            echo "        apk update"
            apk update >/dev/null 2>&1
            ;;
        opkg)
            echo
            echo "        opkg update"
            opkg update >/dev/null 2>&1
            ;;
        *)
            echo
            echo "        нет apk/opkg — индексы не обновляю"
            ;;
    esac

    PKG_REPAIR_ACTIVE=1

    if [ "$PKG_REPAIR_DNS_CHANGED" = "1" ] || [ "$PKG_REPAIR_SVC_STOPPED" = "1" ]; then
        return 0
    fi
    return 1
}

clear
cat <<'BANNER'
============================================================
 usb-extroot.sh ${ver}
 Перенос overlay OpenWrt на USB-накопитель (extroot)
------------------------------------------------------------
 До ввода YES — только чтение.
 После YES — необратимо; при ошибке — стоп и инструкции.
 Лог: /root/usb-extroot.log
============================================================
BANNER

# ============================================================
#  ШАГ 0. Зависимости
# ============================================================
echo
STAGE0="[0/9] зависимости"
echo "$STAGE0 ..."
PM=$(detect_pm)
echo "      менеджер пакетов: $PM"

MISSING_PKGS=""
for cmd in awk sed grep mount umount df du basename dirname readlink block mkfs.ext4 uci; do
    if ! have "$cmd"; then
        case "$cmd" in
            block)     pkg=block-mount ;;
            mkfs.ext4) pkg=e2fsprogs ;;
            uci)       pkg=uci ;;
            *)         pkg=busybox ;;
        esac
        MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
done

TARBIN=""
for cand in tar /usr/bin/tar /usr/libexec/tar-gnu /bin/tar; do
    if [ -x "$cand" ] || have "$cand"; then
        if $cand --version 2>&1 | grep -qi 'GNU tar'; then
            TARBIN="$cand"; break
        fi
    fi
done
if [ -z "$TARBIN" ]; then
    MISSING_PKGS="$MISSING_PKGS tar"
fi

MISSING_PKGS=$(echo "$MISSING_PKGS" | tr ' ' '\n' | sort -u | tr '\n' ' ')
MISSING_PKGS=$(echo "$MISSING_PKGS" | sed 's/^ *//; s/ *$//')

if [ -n "$MISSING_PKGS" ]; then
    echo "      не хватает пакетов: $MISSING_PKGS"

    if [ "$PM" = "none" ]; then
        die "$STAGE0" "Нет ни apk, ни opkg — установить зависимости нельзя.

Не хватает: $MISSING_PKGS

Поставь пакеты вручную и запусти скрипт заново."
    fi

    echo
    echo "      подготовка сети (DNS, блокировщики)..."
    pkg_repair_start || echo "      сеть не тронута (нечего чинить)"

    for pkg in $MISSING_PKGS; do
        echo
        echo "      устанавливаю $pkg..."
        if ! pkg_install "$pkg" "$PM"; then
            pkg_fail "$STAGE0" "$pkg" "$PM"
        fi
    done

    echo
    echo "      восстанавливаю сеть..."
    pkg_repair_finish
else
    echo "      все пакеты на месте"
fi

echo
echo "      повторная проверка..."
TARBIN=""
for cand in tar /usr/bin/tar /usr/libexec/tar-gnu /bin/tar; do
    if [ -x "$cand" ] || have "$cand"; then
        if $cand --version 2>&1 | grep -qi 'GNU tar'; then
            TARBIN="$cand"; break
        fi
    fi
done
if [ -z "$TARBIN" ]; then
    die "$STAGE0" "GNU tar не найден и не установился.

  command -v tar  -> $(command -v tar 2>/dev/null || echo 'нет')
  tar --version   -> $(tar --version 2>&1 | head -1)
  ls -la /usr/bin/tar /usr/libexec/tar-gnu /bin/tar
$(ls -la /usr/bin/tar /usr/libexec/tar-gnu /bin/tar 2>&1)

Проверь PATH: echo \$PATH
Поставь GNU tar вручную и запусти скрипт заново."
fi
echo "      GNU tar: $TARBIN"

for cmd in awk sed grep mount umount df du basename dirname readlink block mkfs.ext4 uci; do
    if ! have "$cmd"; then
        die "$STAGE0" "После установки нет команды: $cmd"
    fi
done
echo "      все обязательные команды на месте"

# ============================================================
#  ШАГ 1. Текущий overlay
# ============================================================
echo
STAGE1="[1/9] текущий overlay"
echo "$STAGE1 ..."
CUR_OVERLAY_MP=$(awk '/ \/overlay /{print $2; exit}' /proc/mounts)
[ -z "$CUR_OVERLAY_MP" ] && CUR_OVERLAY_MP=/overlay
CUR_OVERLAY_DEV=$(awk -v m="$CUR_OVERLAY_MP" '$2==m {print $1; exit}' /proc/mounts)
if [ -z "$CUR_OVERLAY_DEV" ]; then
    die "$STAGE1" "Не нашёл устройство /overlay.

Проверь вручную:
  mount | grep overlay
  cat /proc/mounts | grep overlay"
fi
echo "      /overlay: $CUR_OVERLAY_DEV на $CUR_OVERLAY_MP"

RWM_DEV=$(uci -q get fstab.rwm.device)

if is_usb "$CUR_OVERLAY_DEV"; then
    REINSTALL=1
    echo
    echo "  /overlay УЖЕ на USB: $CUR_OVERLAY_DEV"
    echo "  Это повторный перенос."
    echo

    if [ -z "$RWM_DEV" ]; then
        die "$STAGE1" "Нет fstab.rwm.device — нижний слой неизвестен.
Откат при ошибке будет невозможен.

Проверь вручную:
  uci show fstab"
    fi
    if ! is_internal_dev "$RWM_DEV"; then
        die "$STAGE1" "fstab.rwm.device=$RWM_DEV — не внутреннее устройство.
Откат невозможен, продолжать опасно.

Проверь вручную:
  uci show fstab"
    fi

    echo "  нижний слой (fstab.rwm): $RWM_DEV"
    echo "  новый перенос перезапишет fstab.extroot."
    echo
    printf "  Введи YES для продолжения: "
    read A
    if [ "$A" != "YES" ]; then
        echo "Отменено."
        exit 0
    fi

    ORIG_DEV="$RWM_DEV"
else
    REINSTALL=0
    if ! is_internal_dev "$CUR_OVERLAY_DEV"; then
        die "$STAGE1" "/overlay не на внутреннем устройстве: $CUR_OVERLAY_DEV
Скрипт работает только с внутренним overlay (ubi/mtdblock/root)."
    fi
    ORIG_DEV="$CUR_OVERLAY_DEV"
    echo "      ок, внутренний: $ORIG_DEV"
fi
echo "      нижний слой для fstab.rwm: $ORIG_DEV"

# ============================================================
#  ШАГ 2. Поиск USB
# ============================================================
echo
STAGE2="[2/9] поиск USB"
echo "$STAGE2 ..."
ALL=""
for d in /dev/sd? /dev/mmcblk? /dev/nvme?n?; do
    [ -b "$d" ] && ALL="$ALL $d"
done
USB=""
for d in $ALL; do
    is_usb "$d" || continue
    [ "$d" = "$CUR_OVERLAY_DEV" ] && continue
    USB="$USB $d"
done
if [ -z "$USB" ]; then
    die "$STAGE2" "USB-накопителей не найдено.

Подключи флешку и запусти скрипт заново.
Проверь вручную:
  ls -la /dev/sd*
  dmesg | tail -20"
fi

DISKS=""
for d in $USB; do
    case "$(basename $d)" in
        sd[a-z]) DISKS="$DISKS $d";;
    esac
done
if [ -z "$DISKS" ]; then
    die "$STAGE2" "USB-дисков (sd*) не найдено.

Найдены устройства, но ни одно не определяется как USB-диск.
Проверь вручную:
  ls -la /dev/sd*
  dmesg | tail -20"
fi
set -- $DISKS

if [ $# -eq 1 ]; then
    TARGET="$1"
else
    echo "Найдено несколько USB-накопителей:"
    for d in $DISKS; do echo "  $(describe $d)"; done
    printf "Укажите целевой (например /dev/sda): "
    read TARGET
    ok=0
    for d in $DISKS; do
        [ "$d" = "$TARGET" ] && ok=1
    done
    if [ "$ok" != "1" ]; then
        die "$STAGE2" "Выбранный диск не из списка: $TARGET

Доступные:
$(for d in $DISKS; do echo "  $d"; done)"
    fi
fi

DESC=$(describe "$TARGET")
echo "      найден: $DESC"

PARTS=""
for p in ${TARGET}*; do
    [ -b "$p" ] || continue
    case "$(basename $p)" in
        $(basename $TARGET)) continue;;
    esac
    PARTS="$PARTS $p"
done
[ -z "$PARTS" ] && PARTS="$TARGET"
PART=$(echo $PARTS | awk '{print $1}')

echo
block info "$PART" >/dev/null 2>&1
FS=$(block info "$PART" 2>/dev/null | grep -o 'TYPE="[^"]*"' | cut -d'"' -f2)

echo
echo "ЦЕЛЬ: $DESC"
for p in $PARTS; do
    f=$(block info "$p" 2>/dev/null | grep -o 'TYPE="[^"]*"' | cut -d'"' -f2)
    m=$(block info "$p" 2>/dev/null | grep -o 'MOUNT="[^"]*"' | cut -d'"' -f2)
    echo "      $p FS=${f:--} ${m:+смонтирован $m}"
done

# ============================================================
#  ШАГ 3. Проверки ДО деструктива
# ============================================================
echo
STAGE3="[3/9] проверки безопасности"
echo "$STAGE3 ..."

SRC_SIZE_KB=$(du -sk "$CUR_OVERLAY_MP" 2>/dev/null | awk '{print $1}')
TMP_AVAIL_KB=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}')

echo "      overlay: ${SRC_SIZE_KB}K, /tmp свободно: ${TMP_AVAIL_KB}K"

if [ -z "$SRC_SIZE_KB" ] || [ -z "$TMP_AVAIL_KB" ]; then
    die "$STAGE3" "Не смог определить размер overlay или /tmp.
overlay: ${SRC_SIZE_KB:-?}K
/tmp:    ${TMP_AVAIL_KB:-?}K

Проверь вручную:
  du -sk $CUR_OVERLAY_MP
  df -h /tmp"
fi

NEED_TMP_KB=$(( SRC_SIZE_KB + SRC_SIZE_KB / 10 ))
if [ "$TMP_AVAIL_KB" -lt "$NEED_TMP_KB" ]; then
    die "$STAGE3" "Мало места в /tmp для бэкапа.
Нужно: ${NEED_TMP_KB}K, свободно: ${TMP_AVAIL_KB}K.

Освободи ОЗУ или перезагрузись."
fi
echo "      ок, в /tmp места хватает"

SRC_PARENT=$(parent_dev "$CUR_OVERLAY_DEV")
DST_PARENT=$(parent_dev "$PART")
echo "      физ.диски: overlay=$SRC_PARENT usb=$DST_PARENT"

SAME_DISK=0
if [ "$SRC_PARENT" = "$DST_PARENT" ]; then
    if [ "$REINSTALL" != "1" ]; then
        die "$STAGE3" "overlay и $PART на одном диске ($SRC_PARENT).

Переформат/очистка возможны только при повторном переносе
(overlay уже на USB, есть fstab.rwm на внутреннем).

Сейчас overlay на внутреннем — перенос на тот же диск невозможен."
    fi
    SAME_DISK=1
fi

if [ "$PART" = "$CUR_OVERLAY_DEV" ] && [ "$SAME_DISK" != "1" ]; then
    die "$STAGE3" "$PART совпадает с текущим /overlay."
fi

# ============================================================
#  ШАГ 4. Меню
# ============================================================
echo
STAGE4="[4/9] меню"
echo "Действие:"
echo "  1) форматировать и перенести overlay на USB-носитель"
if [ "$FS" = "ext4" ]; then
    echo "  2) перенести без форматирования (очистить ФС и развернуть overlay)"
else
    echo "  2) перенести без форматирования  [недоступно: FS=${FS:--}, нужна ext4]"
    echo "     рекомендую форматирование в ext4 (п.1), но решение за вами."
fi
echo "  0) выход"
printf "Выбор: "
read CHOICE

case "$CHOICE" in
    1) MODE=format ;;
    2) if [ "$FS" != "ext4" ]; then
           die "$STAGE4" "Пункт 2 недоступен: FS=${FS:--}.

Нужна существующая ФС ext4 на $PART.
Проверь вручную:
  block info $PART"
       fi
       MODE=noformat ;;
    0|"") echo "Выход."; exit 0 ;;
    *) die "$STAGE4" "Неизвестный выбор: '$CHOICE'

Допустимо: 1, 2, 0" ;;
esac

echo
if [ "$MODE" = format ]; then
    echo "Все данные на $DESC будут уничтожены (mkfs.ext4 $PART)."
else
    echo "Содержимое $PART будет ОЧИЩЕНО, затем развёрнут overlay."
fi

if [ "$SAME_DISK" = "1" ]; then
    echo
    echo "  !!! ТА ЖЕ ФЛЕШКА !!!"
    echo "  overlay сейчас на $CUR_OVERLAY_DEV ($SRC_PARENT)."
    if [ "$MODE" = format ]; then
        echo "  Будет: umount -l + mkfs.ext4 -F $PART."
        CONFIRM_WORD=FORMAT
    else
        echo "  Будет: umount -l + очистка содержимого $PART."
        CONFIRM_WORD=CLEAN
    fi
    echo "  До ребута система будет НЕРАБОТОСПОСОБНА."
    echo "  Бэкап в /tmp (ОЗУ) — при сбое пропадёт."
    echo
    printf "Для подтверждения введите %s: " "$CONFIRM_WORD"
    read A
    if [ "$A" != "$CONFIRM_WORD" ]; then
        echo "Отменено."
        exit 0
    fi
else
    printf "Для подтверждения введите YES: "
    read A
    if [ "$A" != "YES" ]; then
        echo "Отменено."
        exit 0
    fi
fi
echo "Подтверждено: $TARGET ($MODE)."

# ============================================================
#  ШАГ 5. Пакеты
# ============================================================
echo
STAGE5="[5/9] пакеты"
echo "$STAGE5 ..."
for pkg in block-mount kmod-fs-ext4 e2fsprogs; do
    if pkg_present "$pkg" "$PM"; then
        echo "      $pkg: есть"
    else
        echo
        echo "      $pkg: нет — ставлю..."
        if ! pkg_install "$pkg" "$PM"; then
            pkg_fail "$STAGE5" "$pkg" "$PM"
        fi
    fi
done

# ============================================================
#  ШАГ 6. Бэкап
# ============================================================
echo
STAGE6="[6/9] бэкап overlay"
BACKUP_DIR="/tmp/.usb-extroot-x7k2m9q4p1w8"
echo "$STAGE6 в $BACKUP_DIR ..."

rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

TS=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_ARCHIVE="$BACKUP_DIR/overlay_backup_${TS}.tar.gz"

echo "      источник: $CUR_OVERLAY_MP"
echo "      архив:    $BACKUP_ARCHIVE"

echo
if ! $TARBIN -C "$CUR_OVERLAY_MP" --one-file-system -czf "$BACKUP_ARCHIVE" . 2>/tmp/tar_read.err; then
    echo "      tar errors:"
    head -20 /tmp/tar_read.err
    die "$STAGE6" "Не смог создать архив overlay.
Ничего не тронуто, overlay цел.

Проверь вручную:
  ls -la $CUR_OVERLAY_MP
  cat /tmp/tar_read.err"
fi

if ! $TARBIN -tzf "$BACKUP_ARCHIVE" >/dev/null 2>&1; then
    die "$STAGE6" "Архив повреждён: $BACKUP_ARCHIVE
Ничего не тронуто, overlay цел.

Проверь вручную:
  ls -la $BACKUP_ARCHIVE"
fi

ARCHIVE_SIZE_KB=$(du -k "$BACKUP_ARCHIVE" 2>/dev/null | awk '{print $1}')
echo "      архив: ${ARCHIVE_SIZE_KB}K"
if [ -z "$ARCHIVE_SIZE_KB" ] || [ "$ARCHIVE_SIZE_KB" -lt 1 ]; then
    die "$STAGE6" "Архив пустой.
Ничего не тронуто, overlay цел.

Проверь вручную:
  ls -la $BACKUP_ARCHIVE"
fi
echo "      ок: $BACKUP_ARCHIVE"

# ============================================================
#  ШАГ 7. Формат / очистка
# ============================================================
echo
STAGE7="[7/9] подготовка $PART"
MNT=/mnt/extroot_tmp
mkdir -p "$MNT"

echo "$STAGE7 ..."
for m in $(awk -v p="$PART" '$1==p {print $2}' /proc/mounts); do
    echo
    echo "      umount $m"
    umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true
done
umount "$PART" 2>/dev/null || umount -l "$PART" 2>/dev/null || true
umount "$TARGET" 2>/dev/null || umount -l "$TARGET" 2>/dev/null || true
umount "$MNT" 2>/dev/null || umount -l "$MNT" 2>/dev/null || true

if [ "$SAME_DISK" = "1" ]; then
    echo "      umount -l $CUR_OVERLAY_MP (тот же диск)"
    umount -l "$CUR_OVERLAY_MP" 2>/dev/null || true
    umount -l "$CUR_OVERLAY_DEV" 2>/dev/null || true
fi

if [ "$MODE" = format ]; then
    if [ "$TEST_MODE" = "1" ]; then
        echo
        echo "      [TEST] имитирую падение mkfs"
        false
        mkfs.ext4 -F -L extroot "$PART"
    else
        echo
        if ! mkfs.ext4 -F -L extroot "$PART"; then
            fatal "$STAGE7" "mkfs.ext4 на $PART упал.
Бэкап цел: $BACKUP_ARCHIVE"
        fi
    fi
    echo "      отформатировано: $PART (ext4, label=extroot)"
fi

echo
echo "      монтирую $PART -> $MNT"
mount "$PART" "$MNT"
if [ $? -ne 0 ]; then
    fatal "$STAGE7" "Не смог смонтировать $PART в $MNT.
Бэкап цел: $BACKUP_ARCHIVE"
fi

if [ "$MODE" = noformat ]; then
    echo
    echo "      очищаю содержимое $PART ..."
    for entry in "$MNT"/* "$MNT"/.[!.]* "$MNT"/..?*; do
        [ -e "$entry" ] || continue
        case "$(basename "$entry")" in
            lost+found) continue ;;
        esac
        echo "        rm -rf $entry"
        if ! rm -rf "$entry"; then
            umount "$MNT" 2>/dev/null || true
            fatal "$STAGE7" "Не смог удалить $entry.
Бэкап цел: $BACKUP_ARCHIVE"
        fi
    done
    sync
    echo "      очищено"
fi

# ============================================================
#  ШАГ 8. Распаковка
# ============================================================
echo
STAGE8="[8/9] распаковка на USB"
echo "$STAGE8 ..."
AVAIL_DST_KB=$(df -k "$MNT" 2>/dev/null | awk 'NR==2 {print $4}')
echo "      свободно: ${AVAIL_DST_KB}K, нужно ~${SRC_SIZE_KB}K"

if [ -z "$AVAIL_DST_KB" ]; then
    umount "$MNT" 2>/dev/null || true
    fatal "$STAGE8" "Не смог определить свободное место на $PART.
Бэкап цел: $BACKUP_ARCHIVE"
fi
if [ "$AVAIL_DST_KB" -lt $((SRC_SIZE_KB + SRC_SIZE_KB / 10)) ]; then
    umount "$MNT" 2>/dev/null || true
    fatal "$STAGE8" "Мало места на $PART (${AVAIL_DST_KB}K < ${SRC_SIZE_KB}K).
Бэкап цел: $BACKUP_ARCHIVE"
fi

echo
if ! $TARBIN -C "$MNT" -xzf "$BACKUP_ARCHIVE" 2>/tmp/tar_write.err; then
    echo "      tar errors:"
    head -20 /tmp/tar_write.err
    umount "$MNT" 2>/dev/null || true
    fatal "$STAGE8" "Распаковка на USB упала.
Бэкап цел: $BACKUP_ARCHIVE"
fi
sync

USB_SIZE_KB=$(du -sk "$MNT" 2>/dev/null | awk '{print $1}')
echo "      на USB: ${USB_SIZE_KB}K"
if [ -z "$USB_SIZE_KB" ] || [ "$USB_SIZE_KB" -lt $((SRC_SIZE_KB / 2)) ]; then
    umount "$MNT" 2>/dev/null || true
    fatal "$STAGE8" "На USB мало (${USB_SIZE_KB}K vs ${SRC_SIZE_KB}K).
Бэкап цел: $BACKUP_ARCHIVE"
fi

CFG="$MNT/upper/etc/config"
if [ ! -d "$CFG" ]; then
    umount "$MNT" 2>/dev/null || true
    fatal "$STAGE8" "Распакованный overlay неполный — нет $CFG.
Бэкап цел: $BACKUP_ARCHIVE

Проверь архив вручную:
  tar -tzf $BACKUP_ARCHIVE | grep upper/etc/config"
fi

# ============================================================
#  ШАГ 9. fstab — в живой + в USB
# ============================================================
echo
STAGE9="[9/9] fstab"
echo "$STAGE9 ..."

echo
UUID=$(block info "$PART" | grep -o 'UUID="[^"]*"' | cut -d'"' -f2)
if [ -z "$UUID" ]; then
    umount "$MNT" 2>/dev/null || true
    fatal "$STAGE9" "Не получил UUID для $PART.
Бэкап цел: $BACKUP_ARCHIVE

Проверь вручную:
  block info $PART"
fi

# ---------- живой fstab (ubi0_2) ----------
uci -q delete fstab.extroot
uci set fstab.extroot=mount
uci set fstab.extroot.uuid="$UUID"
uci set fstab.extroot.target="/overlay"
uci set fstab.extroot.enabled="1"

if [ "$REINSTALL" = "1" ]; then
    echo "      fstab.rwm (живой): оставляю как есть"
else
    uci -q delete fstab.rwm
    uci set fstab.rwm=mount
    uci set fstab.rwm.device="$ORIG_DEV"
    uci set fstab.rwm.target="/rwm"
    uci set fstab.rwm.enabled="1"
fi
uci commit fstab

# ---------- fstab на USB ($MNT/upper/etc/config) ----------
uci -c "$CFG" -q delete fstab.extroot
uci -c "$CFG" set fstab.extroot=mount
uci -c "$CFG" set fstab.extroot.uuid="$UUID"
uci -c "$CFG" set fstab.extroot.target="/overlay"
uci -c "$CFG" set fstab.extroot.enabled="1"

if [ "$REINSTALL" = "1" ]; then
    echo "      fstab.rwm (USB): оставляю как есть"
else
    uci -c "$CFG" -q delete fstab.rwm
    uci -c "$CFG" set fstab.rwm=mount
    uci -c "$CFG" set fstab.rwm.device="$ORIG_DEV"
    uci -c "$CFG" set fstab.rwm.target="/rwm"
    uci -c "$CFG" set fstab.rwm.enabled="1"
fi
uci -c "$CFG" commit fstab

echo "      extroot: UUID=$UUID -> /overlay"
echo "      rwm:     $ORIG_DEV -> /rwm"

echo
echo "Проверка живого fstab:"
uci show fstab 2>/dev/null | grep -E 'extroot|rwm' || echo "      (записи не найдены!)"

echo
echo "Проверка fstab на USB:"
grep -E 'extroot|rwm' "$CFG/fstab" || echo "      (записи не найдены!)"

umount "$MNT" 2>/dev/null || true

echo
echo "============================================================"
echo " Готово. Бэкап: $BACKUP_ARCHIVE"
echo "   1) перезагрузить сейчас"
echo "   2) выйти без перезагрузки"
echo "============================================================"
printf "Выбор: "
read R
case "$R" in
    1)
        echo
        echo "!!! ПЕРЕЗАГРУЗКА ЧЕРЕЗ 10 СЕКУНД !!!"
        echo "    Ctrl+C — отмена."
        i=10
        while [ $i -gt 0 ]; do
            printf "\r    осталось: %2d " "$i"
            sleep 1
            i=$((i-1))
        done
        printf "\r    осталось:  0 \n"
        echo "Перезагружаюсь..."
        sync
        reboot
        ;;
    *) echo "Ок, не перезагружаю." ;;
esac

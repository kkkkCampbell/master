#!/bin/sh
# rrws_installer.sh — установщик LuCI-приложения RR-WARP-Scanner
# Репозиторий: https://github.com/dedikar/RR-WARP-Scanner
# Запуск: sh rrws_installer.sh [noclear]

echo "ver_0006"
sleep 2

if [ "$1" != "noclear" ]; then clear; fi
set -e

REPO="dedikar/RR-WARP-Scanner"
GITHUB_API="https://api.github.com/repos/${REPO}/releases/latest"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

TMP_DIR="$(mktemp -d)"
TMP_JSON="${TMP_DIR}/release.json"
TMP_ERR="${TMP_DIR}/wget.err"
TMP_PKG=""   # выставим после определения расширения
trap 'rm -rf "$TMP_DIR"' EXIT

log()  { printf '%s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf 'ОШИБКА: %s\n' "$*" >&2; exit 1; }

# --- 0. Определяем пакетный менеджер и формат пакета ----------------------
detect_pkg_ext() {
    if command -v apk >/dev/null 2>&1; then
        echo ".apk"
    elif command -v opkg >/dev/null 2>&1; then
        echo ".ipk"
    else
        die "не найден ни apk, ни opkg — не понимаю, чем ставить пакет."
    fi
}

# --- 0a. Проверяем и при необходимости ставим wget-ssl -------------------
ensure_wget_ssl() {
    local pkg_mgr="$1"

    if [ "$pkg_mgr" = "apk" ]; then
        if apk info -e wget-ssl >/dev/null 2>&1; then
            log "wget-ssl уже установлен (apk)."
            return 0
        fi
    else
        if opkg list-installed 2>/dev/null | grep -q '^wget-ssl '; then
            log "wget-ssl уже установлен (opkg)."
            return 0
        fi
    fi

    log "wget-ssl не найден. Устанавливаю..."

    if [ "$pkg_mgr" = "apk" ]; then
        if apk info -e wget-nossl >/dev/null 2>&1; then
            warn "удаляю конфликтующий wget-nossl..."
            apk del wget-nossl >/dev/null 2>&1 || true
        fi
        apk update >/dev/null 2>&1 || true
        apk add wget-ssl ca-certificates || die "не удалось установить wget-ssl через apk."
    else
        if opkg list-installed 2>/dev/null | grep -q '^wget-nossl '; then
            warn "удаляю конфликтующий wget-nossl..."
            opkg remove wget-nossl >/dev/null 2>&1 || true
        fi
        opkg update >/dev/null 2>&1 || true
        opkg install wget-ssl ca-certificates || die "не удалось установить wget-ssl через opkg."
    fi

    log "wget-ssl установлен."
}

# --- 0b. Проверяем наличие jq -------------------------------------------
detect_jq() {
    if command -v jq >/dev/null 2>&1; then
        HAS_JQ=1
        log "jq найден — JSON разбираю через jq."
    else
        HAS_JQ=0
        log "jq не найден — JSON разбираю через grep/sed."
    fi
}

# --- 1. Скачиваем JSON релиза с внятной диагностикой ---------------------
fetch_release_json() {
    local http_code=""

    : > "$TMP_ERR"

    if [ -n "$GITHUB_TOKEN" ]; then
        wget -S -O "$TMP_JSON" \
            --header="Authorization: token ${GITHUB_TOKEN}" \
            "$GITHUB_API" 2>"$TMP_ERR" || true
    else
        wget -S -O "$TMP_JSON" \
            "$GITHUB_API" 2>"$TMP_ERR" || true
    fi

    http_code=$(awk '/HTTP\// {code=$2} END {print code}' "$TMP_ERR")

    if [ ! -s "$TMP_JSON" ]; then
        warn "wget не вернул данных. Трассировка:"
        sed 's/^/    /' "$TMP_ERR" >&2
        die "не удалось получить ответ от GitHub API."
    fi

    if grep -q '"message": *"API rate limit exceeded' "$TMP_JSON" \
       || { [ "$http_code" = "403" ] && grep -q 'rate limit' "$TMP_JSON"; }; then
        die "исчерпан лимит GitHub API (60 запросов/час на IP).
      Подождите ~час или задайте токен:
        export GITHUB_TOKEN=<ваш_токен>
      и запустите скрипт снова."
    fi

    if [ -n "$http_code" ] && [ "$http_code" != "200" ]; then
        local msg
        if [ "$HAS_JQ" = "1" ]; then
            msg=$(jq -r '.message // empty' "$TMP_JSON" 2>/dev/null || true)
        else
            msg=$(grep -o '"message": *"[^"]*"' "$TMP_JSON" | head -1 | cut -d'"' -f4)
        fi
        die "GitHub API вернул HTTP ${http_code}${msg:+ — $msg}."
    fi

    grep -q '"assets"' "$TMP_JSON" \
        || die "в ответе GitHub нет поля assets (релиз пустой?)."
}

# --- 2. Достаём URL ассета по расширению ---------------------------------
get_asset_url() {
    local ext="$1"
    if [ "$HAS_JQ" = "1" ]; then
        jq -r --arg ext "$ext" \
            '.assets[] | select(.name | endswith($ext)) | .browser_download_url' \
            "$TMP_JSON" 2>/dev/null | head -n1
    else
        sed 's/,/\n/g' "$TMP_JSON" \
            | grep -o '"browser_download_url": *"[^"]*"' \
            | sed 's/.*"\(https[^"]*\)"/\1/' \
            | grep -E "\\${ext}\$" \
            | head -n1
    fi
}

get_tag() {
    if [ "$HAS_JQ" = "1" ]; then
        jq -r '.tag_name // empty' "$TMP_JSON" 2>/dev/null
    else
        grep -o '"tag_name": *"[^"]*"' "$TMP_JSON" \
            | head -1 | cut -d'"' -f4
    fi
}

list_asset_names() {
    if [ "$HAS_JQ" = "1" ]; then
        jq -r '.assets[].name' "$TMP_JSON" 2>/dev/null
    else
        sed 's/,/\n/g' "$TMP_JSON" \
            | grep -o '"name": *"[^"]*"' \
            | cut -d'"' -f4
    fi
}

# --- 3. Основной сценарий ------------------------------------------------
PKG_EXT="$(detect_pkg_ext)"
log "Формат пакета: ${PKG_EXT}"

# Имя файла пакета ДОЛЖНО оканчиваться на .ipk / .apk,
# иначе opkg/apk не распознают формат.
TMP_PKG="${TMP_DIR}/package${PKG_EXT}"

if [ "$PKG_EXT" = ".apk" ]; then
    PKG_MGR="apk"
else
    PKG_MGR="opkg"
fi

detect_jq
ensure_wget_ssl "$PKG_MGR"

log "Запрашиваю последний релиз ${REPO}..."
fetch_release_json

TAG="$(get_tag)"
[ -n "$TAG" ] && log "Последний релиз: ${TAG}"

URL="$(get_asset_url "$PKG_EXT")"

if [ -z "$URL" ]; then
    warn "в релизе ${TAG:-<без тега>} нет файла с расширением ${PKG_EXT}."
    log  "Доступные ассеты:"
    list_asset_names | sed 's/^/    /'
    die "установка невозможна."
fi

log "Скачиваю: $URL"
# -q: без вываливания редиректов с JWT в консоль
if ! wget -q -O "$TMP_PKG" "$URL"; then
    die "не удалось скачать пакет с ${URL}"
fi

if [ ! -s "$TMP_PKG" ]; then
    die "скачанный файл пуст: ${TMP_PKG}"
fi

log "Устанавливаю ${PKG_EXT}-пакет..."
if [ "$PKG_EXT" = ".apk" ]; then
    apk add --allow-untrusted "$TMP_PKG"
else
    opkg install --force-reinstall "$TMP_PKG"
fi

log "Готово. Установлен ${TAG:-пакет}."

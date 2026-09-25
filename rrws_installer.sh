#!/bin/sh
# rrws_installer.sh — установщик LuCI-приложения RR-WARP-Scanner
# Репозиторий: https://github.com/dedikar/RR-WARP-Scanner
echo "ver_0003"
sleep2
set -e

REPO="dedikar/RR-WARP-Scanner"
GITHUB_API="https://api.github.com/repos/${REPO}/releases/latest"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

TMP_JSON="$(mktemp)"
TMP_ERR="$(mktemp)"
TMP_PKG="$(mktemp)"
trap 'rm -f "$TMP_JSON" "$TMP_ERR" "$TMP_PKG"' EXIT

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

    # Уже установлен?
    if [ "$pkg_mgr" = "apk" ]; then
        # apk list -I показывает ТОЛЬКО установленные пакеты
        if apk list -I wget-ssl 2>/dev/null | grep -q '^wget-ssl'; then
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

    # Убираем конфликтующий wget-nossl, если он есть
    if [ "$pkg_mgr" = "apk" ]; then
        if apk list -I wget-nossl 2>/dev/null | grep -q '^wget-nossl'; then
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

# --- 1. Скачиваем JSON релиза с внятной диагностикой ---------------------
fetch_release_json() {
    local http_code

    if [ -n "$GITHUB_TOKEN" ]; then
        http_code=$(wget -S -O "$TMP_JSON" \
            --header="Authorization: token ${GITHUB_TOKEN}" \
            "$GITHUB_API" 2>"$TMP_ERR" \
            | awk '/HTTP\// {code=$2} END {print code}')
    else
        http_code=$(wget -S -O "$TMP_JSON" \
            "$GITHUB_API" 2>"$TMP_ERR" \
            | awk '/HTTP\// {code=$2} END {print code}')
    fi

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
        msg=$(grep -o '"message": *"[^"]*"' "$TMP_JSON" | head -1 | cut -d'"' -f4)
        die "GitHub API вернул HTTP ${http_code}${msg:+ — $msg}."
    fi

    grep -q '"assets"' "$TMP_JSON" \
        || die "в ответе GitHub нет поля assets (релиз пустой?)."
}

# --- 2. Достаём URL ассета по расширению ---------------------------------
get_asset_url() {
    local ext="$1"
    sed 's/,/\n/g' "$TMP_JSON" \
        | grep -o '"browser_download_url": *"[^"]*"' \
        | sed 's/.*"\(https[^"]*\)"/\1/' \
        | grep -E "\\${ext}\$" \
        | head -n1
}

get_tag() {
    grep -o '"tag_name": *"[^"]*"' "$TMP_JSON" \
        | head -1 | cut -d'"' -f4
}

# --- 3. Основной сценарий ------------------------------------------------
PKG_EXT="$(detect_pkg_ext)"
log "Формат пакета: ${PKG_EXT}"

# Определяем пакетный менеджер по расширению
if [ "$PKG_EXT" = ".apk" ]; then
    PKG_MGR="apk"
else
    PKG_MGR="opkg"
fi

ensure_wget_ssl "$PKG_MGR"

log "Запрашиваю последний релиз ${REPO}..."
fetch_release_json

TAG="$(get_tag)"
[ -n "$TAG" ] && log "Последний релиз: ${TAG}"

URL="$(get_asset_url "$PKG_EXT")"

if [ -z "$URL" ]; then
    warn "в релизе ${TAG:-<без тега>} нет файла с расширением ${PKG_EXT}."
    log  "Доступные ассеты:"
    sed 's/,/\n/g' "$TMP_JSON" \
        | grep -o '"name": *"[^"]*"' \
        | cut -d'"' -f4 \
        | sed 's/^/    /'
    die "установка невозможна."
fi

log "Скачиваю: $URL"
if ! wget -O "$TMP_PKG" "$URL"; then
    die "не удалось скачать пакет с ${URL}"
fi

log "Устанавливаю ${PKG_EXT}-пакет..."
if [ "$PKG_EXT" = ".apk" ]; then
    apk add --allow-untrusted "$TMP_PKG"
else
    opkg install --force-reinstall "$TMP_PKG"
fi

log "Готово. Установлен ${TAG:-пакет}."

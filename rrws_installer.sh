#!/bin/sh
# Установщик последнего релиза luci-app-rrws из GitHub
# Репозиторий: dedikar/RR-WARP-Scanner

if [ "$1" != "noclear" ]; then clear; fi

# Определяем менеджер пакетов и формат пакета
PKG_MANAGER="opkg"
INSTALL_CMD="install"
PKG_EXT=".ipk"
EXTRA_ARGS=""

# Проверяем, используется ли apk (современные версии OpenWrt)
if [ -f "/usr/bin/apk" ]; then
  PKG_MANAGER="apk"
  INSTALL_CMD="add"
  PKG_EXT=".apk"
  EXTRA_ARGS="--allow-untrusted"
fi 

echo ""
echo "=== Устанавливаем RR WARP Scanner ==="
echo ""
REPO="dedikar/RR-WARP-Scanner"
# https://api.github.com/repos/dedikar/RR-WARP-Scanner/releases/latest
# echo "https://api.github.com/repos/$REPO/releases/latest"
API_URL="https://api.github.com/repos/$REPO/releases/latest"
TMP_DIR="/tmp"
PKG_NAME="luci-app-rrws"

echo "==> Получение информации о последнем релизе..."
RELEASE_JSON=$(wget -qO- --no-check-certificate "$API_URL" 2>/dev/null)
if [ -z "$RELEASE_JSON" ]; then
    echo "ОШИБКА: Не удалось получить данные от GitHub API. Проверьте интернет-соединение."
    exit 1
fi

# Ищем asset с нужным расширением (.ipk или .apk)
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jsonfilter -e "@.assets[?(@.name =~ /.*\\${PKG_EXT}\$/i)].browser_download_url" 2>/dev/null)

# Если jsonfilter не сработал, пробуем простой парсинг
if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    # Простой парсинг для поиска URL с нужным расширением
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url": "[^"]*'"$PKG_EXT"'"' | head -1 | cut -d'"' -f4)
fi

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo "ОШИБКА: В последнем релизе не найден файл пакета ($PKG_EXT)."
    echo "Проверьте страницу: https://github.com/$REPO/releases"
    exit 1
fi

FILENAME=$(basename "$DOWNLOAD_URL")
FILE_PATH="$TMP_DIR/$FILENAME"

echo "==> Найден пакет: $FILENAME"
echo "==> Скачивание во временный каталог..."
wget -q --no-check-certificate -O "$FILE_PATH" "$DOWNLOAD_URL"
if [ $? -ne 0 ] || [ ! -f "$FILE_PATH" ]; then
    echo "ОШИБКА: Не удалось скачать файл."
    exit 1
fi

echo "==> Установка через ${PKG_MANAGER}..."
if [ "$PKG_MANAGER" = "apk" ]; then
    # Для apk используем --force-overwrite вместо --force-reinstall
    $PKG_MANAGER $INSTALL_CMD $EXTRA_ARGS --force-overwrite "$FILE_PATH"
else
    # Для opkg используем --force-reinstall
    $PKG_MANAGER $INSTALL_CMD $EXTRA_ARGS --force-reinstall "$FILE_PATH"
fi
INSTALL_STATUS=$?

if [ $INSTALL_STATUS -eq 0 ]; then
    echo "==> Установка завершена успешно!"
    echo "Проверьте веб-интерфейс LuCI: раздел «Службы» → «RR WARP Scanner»."
    rm -f "$FILE_PATH"
else
    echo "ОШИБКА: ${PKG_MANAGER} завершился с кодом $INSTALL_STATUS."
    echo "Попробуйте установить вручную: ${PKG_MANAGER} ${INSTALL_CMD} $FILE_PATH"
    echo "Если проблема с зависимостями, установите их отдельно (например, kmod-amneziawg)."
    exit 1
fi

#!/bin/sh
# Установщик последнего релиза luci-app-rrws из GitHub
# Репозиторий: dedikar/RR-WARP-Scanner

if [ "$1" != "noclear" ]; then clear; fi

REPO="dedikar/RR-WARP-Scanner"
API_URL="https://api.github.com/repos/$REPO/releases/latest"
TMP_DIR="/tmp"
PKG_NAME="luci-app-rrws"

echo "==> Получение информации о последнем релизе..."
RELEASE_JSON=$(wget -qO- --no-check-certificate "$API_URL" 2>/dev/null)
if [ -z "$RELEASE_JSON" ]; then
    echo "ОШИБКА: Не удалось получить данные от GitHub API. Проверьте интернет-соединение."
    exit 1
fi

# Извлекаем URL первого asset (ожидается .ipk файл)
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jsonfilter -e '@.assets[0].browser_download_url' 2>/dev/null)
if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo "ОШИБКА: В последнем релизе не найден файл пакета (.ipk)."
    echo "Возможно, релиз ещё не собран. Проверьте страницу: https://github.com/$REPO/releases"
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

echo "==> Установка через opkg..."
# --force-reinstall позволяет переустановить пакет, если он уже установлен
opkg install --force-reinstall "$FILE_PATH"
INSTALL_STATUS=$?

if [ $INSTALL_STATUS -eq 0 ]; then
    echo "==> Установка завершена успешно!"
    echo "Проверьте веб-интерфейс LuCI: раздел «Службы» → «RR WARP Scanner»."
    rm -f "$FILE_PATH"  # удаляем временный файл
else
    echo "ОШИБКА: opkg завершился с кодом $INSTALL_STATUS."
    echo "Попробуйте установить вручную: opkg install $FILE_PATH"
    echo "Если проблема с зависимостями, установите их отдельно (например, kmod-amneziawg)."
    exit 1
fi

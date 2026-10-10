# ============================================================
# Резервная копия /overlay/upper + конфигурация через LuCI
# Демон-наблюдатель + флаг-запрос + опрос статуса
# ============================================================

# --- 0. Уборка прошлых экспериментов ---
/etc/init.d/backup-watcher stop 2>/dev/null
/etc/init.d/backup-watcher disable 2>/dev/null
kill $(pidof backup-watcher.sh) 2>/dev/null
kill $(pidof backup-daemon.*.sh) 2>/dev/null
rm -f /etc/init.d/backup-watcher /usr/bin/backup-watcher.sh
rm -f /tmp/backup.request /tmp/backup-config.request /tmp/backup.pid /tmp/backup-daemon.*.sh


# --- 1a. Скрипт полной архивации ---
tee /usr/bin/backup-manager.sh > /dev/null << 'SCRIPT_EOF'
#!/bin/sh
# ============================================================
# backup-manager.sh — полный архив /overlay/upper
# Пишет OK:/ERROR: в /tmp/backup.status
# ============================================================

SOURCE_DIR="/overlay/upper"
STATUS="/tmp/backup.status"

# Имя архива: hostname + версия прошивки + дата-время
HOSTNAME="$(uci -q get system.@system[0].hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown)"
HOSTNAME="$(echo "$HOSTNAME" | tr -c 'A-Za-z0-9._-' '_')"

. /etc/openwrt_release 2>/dev/null || true
DIST="${DISTRIB_ID:-OpenWrt}"
REL="${DISTRIB_RELEASE:-unknown}"
REV="${DISTRIB_REVISION%%-*}"
REV="${REV:-unknown}"

VERSION_STR="${DIST}_${REL}_${REV}"
VERSION_STR="$(echo "$VERSION_STR" | tr -c 'A-Za-z0-9._-' '_')"

TS="$(date +%F-%H%M)"
ARCHIVE="/tmp/backups/backup-full-${HOSTNAME}-${VERSION_STR}-${TS}.tar.gz"

rm -rf /tmp/backups
mkdir -p /tmp/backups

echo "RUNNING" > "$STATUS"

if tar --help 2>&1 | grep -qi busybox; then
    command -v apk >/dev/null 2>&1 && apk add tar >/dev/null 2>&1
    command -v opkg >/dev/null 2>&1 && opkg install tar >/dev/null 2>&1
fi

WHITEOUTS="$(mktemp)"
find "$SOURCE_DIR" -type c > "$WHITEOUTS" 2>/dev/null

umask 022
if ! tar czpf "$ARCHIVE" \
    -X "$WHITEOUTS" \
    --exclude="${SOURCE_DIR}/backups" \
    --exclude="${SOURCE_DIR}/run" \
    --exclude="${SOURCE_DIR}/etc/os-release" \
    --exclude="${SOURCE_DIR}/usr/lib/os-release" \
    --preserve-permissions \
    --same-owner \
    "$SOURCE_DIR" 2>/dev/null
then
    rm -f "$WHITEOUTS" "$ARCHIVE"
    echo "ERROR:сбой tar при создании архива" > "$STATUS"
    exit 2
fi

rm -f "$WHITEOUTS"
chmod 644 "$ARCHIVE"

if ! tar tzf "$ARCHIVE" >/dev/null 2>&1; then
    rm -f "$ARCHIVE"
    echo "ERROR:архив повреждён" > "$STATUS"
    exit 2
fi

echo "OK:$ARCHIVE" > "$STATUS"
SCRIPT_EOF

chmod +x /usr/bin/backup-manager.sh


# --- 1b. Скрипт сохранения только конфигурации ---
tee /usr/bin/backup-config.sh > /dev/null << 'CONF_EOF'
#!/bin/sh
# ============================================================
# backup-config.sh — только конфигурация через sysupgrade -b
# Пишет OK:/ERROR: в /tmp/backup.status
# ============================================================

STATUS="/tmp/backup.status"

# Имя архива: hostname + версия прошивки + дата-время
HOSTNAME="$(uci -q get system.@system[0].hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown)"
HOSTNAME="$(echo "$HOSTNAME" | tr -c 'A-Za-z0-9._-' '_')"

. /etc/openwrt_release 2>/dev/null || true
DIST="${DISTRIB_ID:-OpenWrt}"
REL="${DISTRIB_RELEASE:-unknown}"
REV="${DISTRIB_REVISION%%-*}"
REV="${REV:-unknown}"

VERSION_STR="${DIST}_${REL}_${REV}"
VERSION_STR="$(echo "$VERSION_STR" | tr -c 'A-Za-z0-9._-' '_')"

TS="$(date +%F-%H%M)"
ARCHIVE="/tmp/backups/backup-config-${HOSTNAME}-${VERSION_STR}-${TS}.tar.gz"

rm -rf /tmp/backups
mkdir -p /tmp/backups

echo "RUNNING" > "$STATUS"

umask 022
if ! sysupgrade -b "$ARCHIVE" >/dev/null 2>&1; then
    rm -f "$ARCHIVE"
    echo "ERROR:sysupgrade -b завершился с ошибкой" > "$STATUS"
    exit 2
fi

chmod 644 "$ARCHIVE"

if ! tar tzf "$ARCHIVE" >/dev/null 2>&1; then
    rm -f "$ARCHIVE"
    echo "ERROR:архив конфигурации повреждён" > "$STATUS"
    exit 2
fi

echo "OK:$ARCHIVE" > "$STATUS"
CONF_EOF

chmod +x /usr/bin/backup-config.sh


# --- 2. Демон-наблюдатель ---
tee /usr/bin/backup-watcher.sh > /dev/null << 'WATCH_EOF'
#!/bin/sh
# ============================================================
# backup-watcher.sh — ждёт флаги и запускает нужный скрипт
# ============================================================

REQ_FULL="/tmp/backup.request"
REQ_CONF="/tmp/backup-config.request"
STATUS="/tmp/backup.status"
PIDFILE="/tmp/backup.pid"

while true; do
    if [ -f "$REQ_FULL" ] || [ -f "$REQ_CONF" ]; then
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
            rm -f "$REQ_FULL" "$REQ_CONF"
            sleep 3
            continue
        fi

        if [ -f "$REQ_FULL" ]; then
            rm -f "$REQ_FULL"
			rm -rf /tmp/backups
			mkdir -p /tmp/backups
            echo "RUNNING" > "$STATUS"
            /usr/bin/backup-manager.sh &
            echo $! > "$PIDFILE"
            wait $! 2>/dev/null
            rm -f "$PIDFILE"
        elif [ -f "$REQ_CONF" ]; then
            rm -f "$REQ_CONF"
			rm -rf /tmp/backups
			mkdir -p /tmp/backups
            echo "RUNNING" > "$STATUS"
            /usr/bin/backup-config.sh &
            echo $! > "$PIDFILE"
            wait $! 2>/dev/null
            rm -f "$PIDFILE"
        fi
    fi
    sleep 2
done
WATCH_EOF

chmod +x /usr/bin/backup-watcher.sh


# --- 3. init-скрипт для демона ---
tee /etc/init.d/backup-watcher > /dev/null << 'INIT_EOF'
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/backup-watcher.sh
    procd_set_param respawn
    procd_close_instance
}
INIT_EOF

chmod +x /etc/init.d/backup-watcher
/etc/init.d/backup-watcher enable
/etc/init.d/backup-watcher start


# --- 4. Меню LuCI ---
tee /usr/share/luci/menu.d/luci-app-backup.json > /dev/null << 'MENU_EOF'
{
  "admin/services/backup-create": {
    "title": "Openwrt Full Backup 2",
    "order": 90,
    "action": {
      "type": "view",
      "path": "backup/backup-manager"
    },
    "depends": {
      "acl": [ "luci-app-backup" ]
    }
  }
}
MENU_EOF

chmod 644 /usr/share/luci/menu.d/luci-app-backup.json


# --- 5. ACL ---
tee /usr/share/rpcd/acl.d/luci-app-backup.json > /dev/null << 'ACL_EOF'
{
  "luci-app-backup": {
    "description": "Backup manager access",
    "read": {
      "file": {
        "/tmp/backup.status": [ "read" ],
        "/tmp/backups/*": [ "read" ]
      }
    },
    "write": {
      "file": {
        "/tmp/backup.request": [ "write" ],
        "/tmp/backup-config.request": [ "write" ]
      }
    }
  }
}
ACL_EOF

chmod 644 /usr/share/rpcd/acl.d/luci-app-backup.json


# --- 6. JS-страница ---
mkdir -p /www/luci-static/resources/view/backup

tee /www/luci-static/resources/view/backup/backup-manager.js > /dev/null << 'JS_EOF'
'use strict';
'require view';
'require fs';
'require ui';

return view.extend({
    pollTimer: null,
    pollCount: 0,
    maxPolls: 720,        // 720 * 3 сек = 36 минут
    busy: false,

    handleFull: function(ev) {
        return this.runBackup(ev, '/tmp/backup.request',
            'Создание полной резервной копии');
    },

    handleConfig: function(ev) {
        return this.runBackup(ev, '/tmp/backup-config.request',
            'Сохранение конфигурации');
    },

    runBackup: function(ev, flagPath, title) {
        var self = this;
        var btn = ev.currentTarget;

        if (this.busy) return;
        this.busy = true;
        btn.disabled = true;
        btn.classList.add('disabled');

        if (this.pollTimer) {
            clearTimeout(this.pollTimer);
            this.pollTimer = null;
        }
        this.pollCount = 0;

        ui.showModal(title, [
            E('p', { 'class': 'spinning' }, 'Отправка запроса...')
        ]);

        return fs.write(flagPath, '1').then(function() {
            ui.showModal(title, [
                E('p', { 'class': 'spinning' }, 'Выполняется в фоне...'),
                E('p', { 'id': 'backup-status-text' }, 'Ожидание демона...')
            ]);
            self.scheduleNextCheck(btn, title);
        }).catch(function(err) {
            ui.hideModal();
            ui.addNotification(null, E('p', {}, 'Ошибка: ' + err.message), 'error');
            self.finish(btn);
        });
    },

    finish: function(btn) {
        this.busy = false;
        if (btn) {
            btn.disabled = false;
            btn.classList.remove('disabled');
        }
    },

    scheduleNextCheck: function(btn, title) {
        var self = this;
        this.pollTimer = setTimeout(function() {
            self.checkStatus(btn, title);
        }, 3000);
    },

    checkStatus: function(btn, title) {
        var self = this;
        this.pollCount++;

        if (this.pollCount > this.maxPolls) {
            ui.hideModal();
            ui.addNotification(null, E('p', {}, 'Таймаут'), 'error');
            this.finish(btn);
            return;
        }

        fs.read('/tmp/backup.status').then(function(res) {
            var status = ((res && res.data) ? res.data : (res || '')).trim();
            var el = document.getElementById('backup-status-text');
            if (el) el.textContent = 'Статус: ' + status + ' (' + (self.pollCount * 3) + ' сек)';

            if (status.indexOf('OK:') === 0) {
                var path = status.substring(3).trim();
                self.downloadArchive(path, btn, title);
                return;
            }

            if (status.indexOf('ERROR:') === 0) {
                ui.hideModal();
                ui.addNotification(null, E('p', {}, status), 'error');
                self.finish(btn);
                return;
            }

            self.scheduleNextCheck(btn, title);
        }).catch(function() {
            self.scheduleNextCheck(btn, title);
        });
    },

    downloadArchive: function(path, btn, title) {
        var self = this;
        ui.showModal(title, [
            E('p', { 'class': 'spinning' }, 'Скачивание...')
        ]);

        return fs.read_direct(path, 'blob').then(function(blob) {
            var url = window.URL.createObjectURL(blob);
            var a = document.createElement('a');
            a.href = url;
            a.download = path.split('/').pop();
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            window.URL.revokeObjectURL(url);

            ui.hideModal();
            ui.addNotification(null,
                E('p', {}, 'Архив сохранён: ' + path.split('/').pop()), 'info');
            self.finish(btn);
        }).catch(function(err) {
            ui.hideModal();
            ui.addNotification(null, E('p', {}, 'Ошибка скачивания: ' + err.message), 'error');
            self.finish(btn);
        });
    },

    render: function() {
        return E('div', { 'class': 'cbi-map' }, [
            E('h2', {}, 'Резервная копия системы'),
            E('div', { 'class': 'cbi-map-descr' }, [
                'Полная резервная копия: весь /overlay/upper (система + данные).',
                E('br'),
                'Только конфигурация: штатный sysupgrade -b (настройки без системы).',
                E('br'),E('br'),
                'Восстановление через Система → Восстановление / Обновление.'
            ]),
            E('div', { 'class': 'cbi-section' }, [
                E('button', {
                    'class': 'btn cbi-button cbi-button-apply',
                    'click': ui.createHandlerFn(this, 'handleFull')
                }, 'Создать полную резервную копию'),
                ' ',
                E('button', {
                    'class': 'btn cbi-button cbi-button-action',
                    'click': ui.createHandlerFn(this, 'handleConfig')
                }, 'Сохранить только конфигурацию')
            ])
        ]);
    },

    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
JS_EOF

chmod 644 /www/luci-static/resources/view/backup/backup-manager.js


# --- 7. Перезапуск rpcd ---
/etc/init.d/rpcd restart

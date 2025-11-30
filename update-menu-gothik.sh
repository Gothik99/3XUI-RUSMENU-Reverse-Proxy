#!/bin/bash
#
# Скрипт обновления меню 3X-UI из репозитория Gothik99
# Репозиторий: https://github.com/Gothik99/3XUI-RUSMENU-Reverse-Proxy
# 
# Использование:
#   bash <(curl -Ls https://raw.githubusercontent.com/Gothik99/3XUI-RUSMENU-Reverse-Proxy/main/update-menu-gothik.sh)
#   или
#   wget https://raw.githubusercontent.com/Gothik99/3XUI-RUSMENU-Reverse-Proxy/main/update-menu-gothik.sh && chmod +x update-menu-gothik.sh && sudo ./update-menu-gothik.sh

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

# Функции логирования
function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}

# Проверка root
[[ $EUID -ne 0 ]] && LOGE "ОШИБКА: Вы должны быть root для запуска этого скрипта! \n" && exit 1

# Проверка наличия необходимых утилит
if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    LOGE "ОШИБКА: Не найдены утилиты curl или wget!"
    LOGE "Установите одну из них: apt-get install curl wget"
    exit 1
fi

echo -e "${green}====================================================${plain}"
echo -e "${green}   Обновление меню 3X-UI из репозитория Gothik99    ${plain}"
echo -e "${green}====================================================${plain}"
echo ""

# URL репозитория
MENU_URL="https://raw.githubusercontent.com/Gothik99/3XUI-RUSMENU-Reverse-Proxy/main/x-ui.sh"
BACKUP_DIR="/tmp/x-ui-backup-$(date +%Y%m%d-%H%M%S)"

# Создаем резервную копию текущего меню
LOGI "Создание резервной копии текущего меню..."
mkdir -p "$BACKUP_DIR"

if [ -f "/usr/bin/x-ui" ]; then
    cp /usr/bin/x-ui "$BACKUP_DIR/x-ui-backup.sh"
    LOGI "Резервная копия сохранена в: $BACKUP_DIR/x-ui-backup.sh"
fi

if [ -f "/usr/local/x-ui/x-ui.sh" ]; then
    cp /usr/local/x-ui/x-ui.sh "$BACKUP_DIR/x-ui.sh-backup"
    LOGI "Резервная копия сохранена в: $BACKUP_DIR/x-ui.sh-backup"
fi

# Скачиваем новое меню
LOGI "Загрузка обновленного меню из репозитория Gothik99..."
LOGI "URL: $MENU_URL"

# Проверяем доступность URL
if command -v curl &>/dev/null; then
    if ! curl -s --head --fail "$MENU_URL" > /dev/null 2>&1; then
        LOGE "Не удалось подключиться к репозиторию!"
        LOGE "Проверьте интернет-соединение и доступность GitHub."
        exit 1
    fi
elif command -v wget &>/dev/null; then
    if ! wget --spider "$MENU_URL" > /dev/null 2>&1; then
        LOGE "Не удалось подключиться к репозиторию!"
        LOGE "Проверьте интернет-соединение и доступность GitHub."
        exit 1
    fi
fi

# Скачиваем файл во временную директорию
TEMP_FILE="/tmp/x-ui-new-$(date +%s).sh"
if command -v wget &>/dev/null; then
    wget -O "$TEMP_FILE" "$MENU_URL" 2>&1 | grep -E "(saved|ERROR|failed)" || true
elif command -v curl &>/dev/null; then
    curl -sL "$MENU_URL" -o "$TEMP_FILE" 2>&1 || true
fi

if [ ! -f "$TEMP_FILE" ] || [ ! -s "$TEMP_FILE" ]; then
    LOGE "Не удалось загрузить файл меню!"
    rm -f "$TEMP_FILE"
    exit 1
fi

# Проверяем, что файл начинается с #!/bin/bash (базовая валидация)
if ! head -n 1 "$TEMP_FILE" | grep -q "#!/bin/bash"; then
    LOGE "Загруженный файл не является валидным bash скриптом!"
    rm -f "$TEMP_FILE"
    exit 1
fi

LOGI "Файл успешно загружен. Размер: $(du -h "$TEMP_FILE" | cut -f1)"

# Устанавливаем новое меню
LOGI "Установка обновленного меню..."

# Обновляем /usr/bin/x-ui
if cp "$TEMP_FILE" /usr/bin/x-ui; then
    chmod +x /usr/bin/x-ui
    LOGI "✓ /usr/bin/x-ui обновлен"
else
    LOGE "Не удалось обновить /usr/bin/x-ui"
    rm -f "$TEMP_FILE"
    exit 1
fi

# Обновляем /usr/local/x-ui/x-ui.sh (если существует)
if [ -d "/usr/local/x-ui" ]; then
    if cp "$TEMP_FILE" /usr/local/x-ui/x-ui.sh; then
        chmod +x /usr/local/x-ui/x-ui.sh
        LOGI "✓ /usr/local/x-ui/x-ui.sh обновлен"
    else
        LOGD "Не удалось обновить /usr/local/x-ui/x-ui.sh (возможно, директория не существует)"
    fi
fi

# Удаляем временный файл
rm -f "$TEMP_FILE"

echo ""
LOGI "════════════════════════════════════════════════"
LOGI "   Обновление завершено успешно!"
LOGI "════════════════════════════════════════════════"
echo ""
LOGI "Резервные копии сохранены в: $BACKUP_DIR"
echo ""
LOGI "Теперь вы можете запустить: ${green}x-ui${plain}"
echo ""


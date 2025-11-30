#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

# Функции логирования
LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}

LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

# Проверка root
[[ $EUID -ne 0 ]] && LOGE "ОШИБКА: Вы должны быть root для запуска этого скрипта!" && exit 1

echo -e "${green}====================================================${plain}"
echo -e "${green}   Обновление меню x-ui из репозитория Gothik99     ${plain}"
echo -e "${green}====================================================${plain}"
echo ""

# URL репозитория
REPO_URL="https://raw.githubusercontent.com/Gothik99/3XUI-RUSMENU-Reverse-Proxy/main/x-ui.sh"
BACKUP_DIR="/tmp/x-ui-backup-$(date +%Y%m%d-%H%M%S)"

# Проверка существования x-ui
if [ ! -f "/usr/bin/x-ui" ]; then
    LOGE "Файл /usr/bin/x-ui не найден!"
    echo -e "${yellow}Убедитесь, что x-ui установлен.${plain}"
    exit 1
fi

# Создание резервной копии
LOGI "Создание резервной копии текущего меню..."
mkdir -p "$BACKUP_DIR"
cp /usr/bin/x-ui "$BACKUP_DIR/x-ui.backup" 2>/dev/null
if [ $? -eq 0 ]; then
    LOGI "Резервная копия сохранена в: $BACKUP_DIR/x-ui.backup"
else
    LOGE "Не удалось создать резервную копию!"
    read -p "Продолжить без резервной копии? (y/n): " continue_backup
    if [[ "$continue_backup" != "y" && "$continue_backup" != "Y" ]]; then
        exit 1
    fi
fi

# Загрузка нового меню
LOGI "Загрузка обновленного меню из репозитория..."
LOGD "URL: $REPO_URL"

# Проверка доступности репозитория
if ! curl -s --head --fail "$REPO_URL" > /dev/null 2>&1; then
    LOGE "Не удалось подключиться к репозиторию!"
    LOGE "Проверьте интернет-соединение и доступность GitHub."
    exit 1
fi

# Загрузка файла во временную директорию
TEMP_FILE="/tmp/x-ui-new-$$.sh"
wget -O "$TEMP_FILE" "$REPO_URL" 2>/dev/null

if [ $? -ne 0 ]; then
    LOGE "Не удалось загрузить файл!"
    rm -f "$TEMP_FILE"
    exit 1
fi

# Проверка синтаксиса загруженного файла
LOGI "Проверка синтаксиса загруженного файла..."
if ! bash -n "$TEMP_FILE" 2>/dev/null; then
    LOGE "Обнаружены ошибки синтаксиса в загруженном файле!"
    LOGE "Обновление отменено для безопасности."
    rm -f "$TEMP_FILE"
    exit 1
fi

# Установка прав на выполнение
chmod +x "$TEMP_FILE"

# Установка нового меню
LOGI "Установка нового меню..."
cp "$TEMP_FILE" /usr/bin/x-ui
chmod +x /usr/bin/x-ui

# Также обновляем в /usr/local/x-ui/x-ui.sh если существует
if [ -f "/usr/local/x-ui/x-ui.sh" ]; then
    LOGI "Обновление /usr/local/x-ui/x-ui.sh..."
    cp "$TEMP_FILE" /usr/local/x-ui/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
fi

# Удаление временного файла
rm -f "$TEMP_FILE"

# Проверка успешности установки
if [ -f "/usr/bin/x-ui" ] && [ -x "/usr/bin/x-ui" ]; then
    LOGI "Обновление успешно завершено!"
    echo ""
    echo -e "${green}════════════════════════════════════════════════${plain}"
    echo -e "${green}   Меню x-ui успешно обновлено!${plain}"
    echo -e "${green}════════════════════════════════════════════════${plain}"
    echo ""
    echo -e "${blue}Резервная копия: $BACKUP_DIR/x-ui.backup${plain}"
    echo -e "${blue}Для отката выполните: cp $BACKUP_DIR/x-ui.backup /usr/bin/x-ui${plain}"
    echo ""
    echo -e "${yellow}Для применения изменений перезапустите скрипт: x-ui${plain}"
else
    LOGE "Ошибка при установке нового меню!"
    LOGE "Попытка восстановления из резервной копии..."
    if [ -f "$BACKUP_DIR/x-ui.backup" ]; then
        cp "$BACKUP_DIR/x-ui.backup" /usr/bin/x-ui
        chmod +x /usr/bin/x-ui
        LOGI "Восстановление из резервной копии выполнено."
    else
        LOGE "Резервная копия не найдена! Требуется ручное восстановление."
    fi
    exit 1
fi


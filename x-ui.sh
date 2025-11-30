#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

# Добавить некоторые базовые функции здесь
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

# Проверка ОС и установка переменной release
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Не удалось определить ОС системы, пожалуйста, свяжитесь с автором!" >&2
    exit 1
fi
echo "Версия ОС: $release"

os_version=""
os_version=$(grep "^VERSION_ID" /etc/os-release | cut -d '=' -f2 | tr -d '"' | tr -d '.')

# Объявление переменных
log_folder="${XUI_LOG_FOLDER:=/var/log}"
iplimit_log_path="${log_folder}/3xipl.log"
iplimit_banned_log_path="${log_folder}/3xipl-banned.log"

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [Default $2]: " temp
        if [[ "${temp}" == "" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ "${temp}" == "y" || "${temp}" == "Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Перезапустить панель, Внимание: Перезапуск панели также перезапустит xray" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Нажмите Enter для возврата в главное меню: ${plain}" && read -r temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "Эта функция обновит все компоненты x-ui до последней версии, данные не будут потеряны. Продолжить?" "y"
    if [[ $? != 0 ]]; then
        LOGE "Отменено"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/main/update.sh)
    if [[ $? == 0 ]]; then
        LOGI "Обновление завершено, панель автоматически перезапущена "
        before_show_menu
    fi
}

update_menu() {
    echo -e "${yellow}Обновление меню${plain}"
    confirm "Эта функция обновит меню до последних изменений." "y"
    if [[ $? != 0 ]]; then
        LOGE "Отменено"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi

    wget -O /usr/bin/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui

    if [[ $? == 0 ]]; then
        echo -e "${green}Обновление успешно. Панель автоматически перезапущена.${plain}"
        exit 0
    else
        echo -e "${red}Не удалось обновить меню.${plain}"
        return 1
    fi
}

legacy_version() {
    echo -n "Введите версию панели (например 2.4.0):"
    read -r tag_version

    if [ -z "$tag_version" ]; then
        echo "Версия панели не может быть пустой. Выход."
        exit 1
    fi
    # Использовать введенную версию панели в ссылке для загрузки
    install_command="bash <(curl -Ls "https://raw.githubusercontent.com/mhsanaei/3x-ui/v$tag_version/install.sh") v$tag_version"

    echo "Загрузка и установка панели версии $tag_version..."
    eval $install_command
}

# Функция для обработки удаления файла скрипта
delete_script() {
    rm "$0" # Удалить сам файл скрипта
    exit 1
}

uninstall() {
    confirm "Вы уверены, что хотите удалить панель? xray также будет удален!" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi

    if [[ $release == "alpine" ]]; then
        rc-service x-ui stop
        rc-update del x-ui
        rm /etc/init.d/x-ui -f
    else
        systemctl stop x-ui
        systemctl disable x-ui
        rm /etc/systemd/system/x-ui.service -f
        systemctl daemon-reload
        systemctl reset-failed
    fi

    rm /etc/x-ui/ -rf
    rm /usr/local/x-ui/ -rf

    echo ""
    echo -e "Удаление успешно завершено.\n"
    echo "Если вам нужно установить эту панель снова, используйте команду:"
    echo -e "${green}bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)${plain}"
    echo ""
    # Перехват сигнала SIGTERM
    trap delete_script SIGTERM
    delete_script
}

reset_user() {
    confirm "Вы уверены, что хотите сбросить имя пользователя и пароль панели?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    
    read -rp "Установите имя пользователя для входа [по умолчанию случайное имя]: " config_account
    [[ -z $config_account ]] && config_account=$(gen_random_string 10)
    read -rp "Установите пароль для входа [по умолчанию случайный пароль]: " config_password
    [[ -z $config_password ]] && config_password=$(gen_random_string 18)

    read -rp "Хотите отключить настроенную двухфакторную аутентификацию? (y/n): " twoFactorConfirm
    if [[ $twoFactorConfirm != "y" && $twoFactorConfirm != "Y" ]]; then
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password} -resetTwoFactor false >/dev/null 2>&1
    else
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password} -resetTwoFactor true >/dev/null 2>&1
        echo -e "Двухфакторная аутентификация отключена."
    fi
    
    echo -e "Имя пользователя для входа в панель сброшено на: ${green} ${config_account} ${plain}"
    echo -e "Пароль для входа в панель сброшен на: ${green} ${config_password} ${plain}"
    echo -e "${green} Пожалуйста, используйте новое имя пользователя и пароль для доступа к панели X-UI. Также запомните их! ${plain}"
    confirm_restart
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

reset_webbasepath() {
    echo -e "${yellow}Сброс базового пути веб-интерфейса${plain}"

    read -rp "Вы уверены, что хотите сбросить базовый путь веб-интерфейса? (y/n): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        echo -e "${yellow}Операция отменена.${plain}"
        return
    fi

    config_webBasePath=$(gen_random_string 18)

    # Применить новую настройку базового пути веб-интерфейса
    /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}" >/dev/null 2>&1

    echo -e "Базовый путь веб-интерфейса сброшен на: ${green}${config_webBasePath}${plain}"
    echo -e "${green}Пожалуйста, используйте новый базовый путь для доступа к панели.${plain}"
    restart
}

reset_config() {
    confirm "Вы уверены, что хотите сбросить все настройки панели? Данные аккаунтов не будут потеряны, имя пользователя и пароль не изменятся" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -reset
    echo -e "Все настройки панели сброшены на значения по умолчанию."
    restart
}

check_config() {
    local info=$(/usr/local/x-ui/x-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "Ошибка получения текущих настроек, пожалуйста, проверьте логи"
        show_menu
        return
    fi
    LOGI "${info}"

    local existing_webBasePath=$(echo "$info" | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(echo "$info" | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_cert=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
    local server_ip=$(curl -s --max-time 3 https://api.ipify.org)
    if [ -z "$server_ip" ]; then
        server_ip=$(curl -s --max-time 3 https://4.ident.me)
    fi

    if [[ -n "$existing_cert" ]]; then
        local domain=$(basename "$(dirname "$existing_cert")")

        if [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            echo -e "${green}URL доступа: https://${domain}:${existing_port}${existing_webBasePath}${plain}"
        else
            echo -e "${green}URL доступа: https://${server_ip}:${existing_port}${existing_webBasePath}${plain}"
        fi
    else
        echo -e "${green}URL доступа: http://${server_ip}:${existing_port}${existing_webBasePath}${plain}"
    fi
}

set_port() {
    echo -n "Введите номер порта[1-65535]: "
    read -r port
    if [[ -z "${port}" ]]; then
        LOGD "Отменено"
        before_show_menu
    else
        /usr/local/x-ui/x-ui setting -port ${port}
        echo -e "Порт установлен, пожалуйста, перезапустите панель сейчас и используйте новый порт ${green}${port}${plain} для доступа к веб-панели"
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        LOGI "Панель уже запущена, нет необходимости запускать снова. Если вам нужно перезапустить, выберите перезапуск"
    else
        if [[ $release == "alpine" ]]; then
            rc-service x-ui start
        else
            systemctl start x-ui
        fi
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "x-ui успешно запущена"
        else
            LOGE "Не удалось запустить панель, возможно, запуск занимает больше двух секунд, пожалуйста, проверьте информацию в логах позже"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "Панель остановлена, нет необходимости останавливать снова!"
    else
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop
        else
            systemctl stop x-ui
        fi
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "x-ui и xray успешно остановлены"
        else
            LOGE "Не удалось остановить панель, возможно, остановка занимает больше двух секунд, пожалуйста, проверьте информацию в логах позже"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    if [[ $release == "alpine" ]]; then
        rc-service x-ui restart
    else
        systemctl restart x-ui
    fi
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "x-ui и xray успешно перезапущены"
    else
        LOGE "Не удалось перезапустить панель, возможно, запуск занимает больше двух секунд, пожалуйста, проверьте информацию в логах позже"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    if [[ $release == "alpine" ]]; then
        rc-service x-ui status
    else
        systemctl status x-ui -l
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    if [[ $release == "alpine" ]]; then
        rc-update add x-ui
    else
        systemctl enable x-ui
    fi
    if [[ $? == 0 ]]; then
        LOGI "x-ui успешно настроена на автоматический запуск при загрузке системы"
    else
        LOGE "Не удалось настроить автозапуск x-ui"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    if [[ $release == "alpine" ]]; then
        rc-update del x-ui
    else
        systemctl disable x-ui
    fi
    if [[ $? == 0 ]]; then
        LOGI "Автозапуск x-ui успешно отменен"
    else
        LOGE "Не удалось отменить автозапуск x-ui"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    if [[ $release == "alpine" ]]; then
        echo -e "${green}\t1.${plain} Отладочный лог"
        echo -e "${green}\t0.${plain} Вернуться в главное меню"
        read -rp "Выберите опцию: " choice

        case "$choice" in
        0)
            show_menu
            ;;
        1)
            grep -F 'x-ui[' /var/log/messages
            if [[ $# == 0 ]]; then
                before_show_menu
            fi
            ;;
        *)
            echo -e "${red}Неверная опция. Пожалуйста, выберите правильный номер.${plain}\n"
            show_log
            ;;
        esac
    else
        echo -e "${green}\t1.${plain} Отладочный лог"
        echo -e "${green}\t2.${plain} Очистить все логи"
        echo -e "${green}\t0.${plain} Вернуться в главное меню"
        read -rp "Выберите опцию: " choice

        case "$choice" in
        0)
            show_menu
            ;;
        1)
            journalctl -u x-ui -e --no-pager -f -p debug
            if [[ $# == 0 ]]; then
                before_show_menu
            fi
            ;;
        2)
            sudo journalctl --rotate
            sudo journalctl --vacuum-time=1s
            echo "Все логи очищены."
            restart
            ;;
        *)
            echo -e "${red}Неверная опция. Пожалуйста, выберите правильный номер.${plain}\n"
            show_log
            ;;
        esac
    fi
}

bbr_menu() {
    echo -e "${green}\t1.${plain} Включить BBR"
    echo -e "${green}\t2.${plain} Отключить BBR"
    echo -e "${green}\t0.${plain} Вернуться в главное меню"
    read -rp "Выберите опцию: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        enable_bbr
        bbr_menu
        ;;
    2)
        disable_bbr
        bbr_menu
        ;;
    *)
        echo -e "${red}Неверная опция. Пожалуйста, выберите правильный номер.${plain}\n"
        bbr_menu
        ;;
    esac
}

disable_bbr() {

    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${yellow}BBR в настоящее время не включен.${plain}"
        before_show_menu
    fi

    # Заменить BBR на CUBIC конфигурации
    sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf
    sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf

    # Применить изменения
    sysctl -p

    # Проверить, что BBR заменен на CUBIC
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "cubic" ]]; then
        echo -e "${green}BBR успешно заменен на CUBIC.${plain}"
    else
        echo -e "${red}Не удалось заменить BBR на CUBIC. Пожалуйста, проверьте конфигурацию системы.${plain}"
    fi
}

enable_bbr() {
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${green}BBR уже включен!${plain}"
        before_show_menu
    fi

    # Проверить ОС и установить необходимые пакеты
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -yqq --no-install-recommends ca-certificates
        ;;
    centos | rhel | almalinux | rocky | ol)
        yum -y update && yum -y install ca-certificates
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf -y install ca-certificates
        ;;
    arch | manjaro | parch)
        pacman -Sy --noconfirm ca-certificates
        ;;
	opensuse-tumbleweed | opensuse-leap)
        zypper refresh && zypper -q install -y ca-certificates
        ;;
    alpine)
        apk add ca-certificates
        ;;
    *)
        echo -e "${red}Неподдерживаемая операционная система. Пожалуйста, проверьте скрипт и установите необходимые пакеты вручную.${plain}\n"
        exit 1
        ;;
    esac

    # Включить BBR
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf

    # Применить изменения
    sysctl -p

    # Проверить, что BBR включен
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
        echo -e "${green}BBR успешно включен.${plain}"
    else
        echo -e "${red}Не удалось включить BBR. Пожалуйста, проверьте конфигурацию системы.${plain}"
    fi
}

update_shell() {
    wget -O /usr/bin/x-ui -N https://github.com/MHSanaei/3x-ui/raw/main/x-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "Не удалось загрузить скрипт, пожалуйста, проверьте, может ли машина подключиться к Github"
        before_show_menu
    else
        chmod +x /usr/bin/x-ui
        LOGI "Обновление скрипта успешно, пожалуйста, перезапустите скрипт"
        before_show_menu
    fi
}

# 0: запущена, 1: не запущена, 2: не установлена
check_status() {
    if [[ $release == "alpine" ]]; then
        if [[ ! -f /etc/init.d/x-ui ]]; then
            return 2
        fi
        if [[ $(rc-service x-ui status | grep -F 'status: started' -c) == 1 ]]; then
            return 0
        else
            return 1
        fi
    else
        if [[ ! -f /etc/systemd/system/x-ui.service ]]; then
            return 2
        fi
        temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ "${temp}" == "running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

check_enabled() {
    if [[ $release == "alpine" ]]; then
        if [[ $(rc-update show | grep -F 'x-ui' | grep default -c) == 1 ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl is-enabled x-ui)
        if [[ "${temp}" == "enabled" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        LOGE "Панель установлена, пожалуйста, не переустанавливайте"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        LOGE "Пожалуйста, сначала установите панель"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
    0)
        echo -e "Состояние панели: ${green}Запущена${plain}"
        show_enable_status
        ;;
    1)
        echo -e "Состояние панели: ${yellow}Не запущена${plain}"
        show_enable_status
        ;;
    2)
        echo -e "Состояние панели: ${red}Не установлена${plain}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "Автозапуск: ${green}Да${plain}"
    else
        echo -e "Автозапуск: ${red}Нет${plain}"
    fi
}

check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "Состояние xray: ${green}Запущен${plain}"
    else
        echo -e "Состояние xray: ${red}Не запущен${plain}"
    fi
}

firewall_menu() {
    echo -e "${green}\t1.${plain} ${green}Установить${plain} Файрвол"
    echo -e "${green}\t2.${plain} Список портов [пронумерованный]"
    echo -e "${green}\t3.${plain} ${green}Открыть${plain} Порты"
    echo -e "${green}\t4.${plain} ${red}Удалить${plain} Порты из списка"
    echo -e "${green}\t5.${plain} ${green}Включить${plain} Файрвол"
    echo -e "${green}\t6.${plain} ${red}Отключить${plain} Файрвол"
    echo -e "${green}\t7.${plain} Статус файрвола"
    echo -e "${green}\t0.${plain} Вернуться в главное меню"
    read -rp "Выберите опцию: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        install_firewall
        firewall_menu
        ;;
    2)
        ufw status numbered
        firewall_menu
        ;;
    3)
        open_ports
        firewall_menu
        ;;
    4)
        delete_ports
        firewall_menu
        ;;
    5)
        ufw enable
        firewall_menu
        ;;
    6)
        ufw disable
        firewall_menu
        ;;
    7)
        ufw status verbose
        firewall_menu
        ;;
    *)
        echo -e "${red}Неверная опция. Пожалуйста, выберите правильный номер.${plain}\n"
        firewall_menu
        ;;
    esac
}

install_firewall() {
    if ! command -v ufw &>/dev/null; then
        echo "Файрвол ufw не установлен. Устанавливаем сейчас..."
        apt-get update
        apt-get install -y ufw
    else
        echo "Файрвол ufw уже установлен"
    fi

    # Проверить, неактивен ли файрвол
    if ufw status | grep -q "Status: active"; then
        echo "Файрвол уже активен"
    else
        echo "Активация файрвола..."
        # Открыть необходимые порты
        ufw allow ssh
        ufw allow http
        ufw allow https
        ufw allow 2053/tcp #веб-порт
        ufw allow 2096/tcp #порт подписки

        # Включить файрвол
        ufw --force enable
    fi
}

open_ports() {
    # Запросить у пользователя порты, которые нужно открыть
    read -rp "Введите порты, которые хотите открыть (например 80,443,2053 или диапазон 400-500): " ports

    # Проверить, валидны ли введенные данные
    if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
        echo "Ошибка: Неверный ввод. Пожалуйста, введите список портов через запятую или диапазон портов (например 80,443,2053 или 400-500)." >&2
        exit 1
    fi

    # Открыть указанные порты с помощью ufw
    IFS=',' read -ra PORT_LIST <<<"$ports"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            # Разделить диапазон на начальный и конечный порты
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            # Открыть диапазон портов
            ufw allow $start_port:$end_port/tcp
            ufw allow $start_port:$end_port/udp
        else
            # Открыть одиночный порт
            ufw allow "$port"
        fi
    done

    # Подтвердить, что порты открыты
    echo "Открыты указанные порты:"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            # Check if the port range has been successfully opened
            (ufw status | grep -q "$start_port:$end_port") && echo "$start_port-$end_port"
        else
            # Check if the individual port has been successfully opened
            (ufw status | grep -q "$port") && echo "$port"
        fi
    done
}

delete_ports() {
    # Показать текущие правила с номерами
    echo "Текущие правила UFW:"
    ufw status numbered

    # Спросить пользователя, как он хочет удалять правила
    echo "Хотите удалить правила по:"
    echo "1) Номерам правил"
    echo "2) Портам"
    read -rp "Введите ваш выбор (1 или 2): " choice

    if [[ $choice -eq 1 ]]; then
        # Удаление по номерам правил
        read -rp "Введите номера правил, которые хотите удалить (1, 2 и т.д.): " rule_numbers

        # Проверить ввод
        if ! [[ $rule_numbers =~ ^([0-9]+)(,[0-9]+)*$ ]]; then
            echo "Ошибка: Неверный ввод. Пожалуйста, введите список номеров правил через запятую." >&2
            exit 1
        fi

        # Разделить номера на массив
        IFS=',' read -ra RULE_NUMBERS <<<"$rule_numbers"
        for rule_number in "${RULE_NUMBERS[@]}"; do
            # Удалить правило по номеру
            ufw delete "$rule_number" || echo "Не удалось удалить правило номер $rule_number"
        done

        echo "Выбранные правила удалены."

    elif [[ $choice -eq 2 ]]; then
        # Удаление по портам
        read -rp "Введите порты, которые хотите удалить (например 80,443,2053 или диапазон 400-500): " ports

        # Проверить ввод
        if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
            echo "Ошибка: Неверный ввод. Пожалуйста, введите список портов через запятую или диапазон портов (например 80,443,2053 или 400-500)." >&2
            exit 1
        fi

        # Разделить порты на массив
        IFS=',' read -ra PORT_LIST <<<"$ports"
        for port in "${PORT_LIST[@]}"; do
            if [[ $port == *-* ]]; then
                # Разделить диапазон портов
                start_port=$(echo $port | cut -d'-' -f1)
                end_port=$(echo $port | cut -d'-' -f2)
                # Удалить диапазон портов
                ufw delete allow $start_port:$end_port/tcp
                ufw delete allow $start_port:$end_port/udp
            else
                # Удалить одиночный порт
                ufw delete allow "$port"
            fi
        done

        # Подтверждение удаления
        echo "Удалены указанные порты:"
        for port in "${PORT_LIST[@]}"; do
            if [[ $port == *-* ]]; then
                start_port=$(echo $port | cut -d'-' -f1)
                end_port=$(echo $port | cut -d'-' -f2)
                # Check if the port range has been deleted
                (ufw status | grep -q "$start_port:$end_port") || echo "$start_port-$end_port"
            else
                # Check if the individual port has been deleted
                (ufw status | grep -q "$port") || echo "$port"
            fi
        done
    else
        echo "${red}Ошибка:${plain} Неверный выбор. Пожалуйста, введите 1 или 2." >&2
        exit 1
    fi
}

update_all_geofiles() {
        update_main_geofiles
        update_ir_geofiles
        update_ru_geofiles
}

update_main_geofiles() {
        wget -O geoip.dat       https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
        wget -O geosite.dat     https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
}

update_ir_geofiles() {
        wget -O geoip_IR.dat    https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
        wget -O geosite_IR.dat  https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
}

update_ru_geofiles() {
        wget -O geoip_RU.dat    https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat
        wget -O geosite_RU.dat  https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat
}

update_geo() {
    echo -e "${green}\t1.${plain} Loyalsoldier (geoip.dat, geosite.dat)"
    echo -e "${green}\t2.${plain} chocolate4u (geoip_IR.dat, geosite_IR.dat)"
    echo -e "${green}\t3.${plain} runetfreedom (geoip_RU.dat, geosite_RU.dat)"
    echo -e "${green}\t4.${plain} Все"
    echo -e "${green}\t0.${plain} Вернуться в главное меню"
    read -rp "Выберите опцию: " choice

    cd /usr/local/x-ui/bin

    case "$choice" in
    0)
        show_menu
        ;;
    1)
        update_main_geofiles
        echo -e "${green}Наборы данных Loyalsoldier успешно обновлены!${plain}"
        restart
        ;;
    2)
        update_ir_geofiles
        echo -e "${green}Наборы данных chocolate4u успешно обновлены!${plain}"
        restart
        ;;
    3)
        update_ru_geofiles
        echo -e "${green}Наборы данных runetfreedom успешно обновлены!${plain}"
        restart
        ;;
    4)
        update_all_geofiles
        echo -e "${green}Все геофайлы успешно обновлены!${plain}"
        restart
        ;;
    *)
        echo -e "${red}Неверная опция. Пожалуйста, выберите правильный номер.${plain}\n"
        update_geo
        ;;
    esac

    before_show_menu
}

install_acme() {
    # Проверить, установлен ли acme.sh
    if command -v ~/.acme.sh/acme.sh &>/dev/null; then
        LOGI "acme.sh уже установлен."
        return 0
    fi

    LOGI "Установка acme.sh..."
    cd ~ || return 1 # Убедиться, что можно перейти в домашнюю директорию

    curl -s https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        LOGE "Установка acme.sh не удалась."
        return 1
    else
        LOGI "Установка acme.sh успешна."
    fi

    return 0
}

ssl_cert_issue_main() {
    echo -e "${green}\t1.${plain} Получить SSL"
    echo -e "${green}\t2.${plain} Отозвать"
    echo -e "${green}\t3.${plain} Принудительное обновление"
    echo -e "${green}\t4.${plain} Показать существующие домены"
    echo -e "${green}\t5.${plain} Установить пути сертификатов для панели"
    echo -e "${green}\t0.${plain} Вернуться в главное меню"

    read -rp "Выберите опцию: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        ssl_cert_issue
        ssl_cert_issue_main
        ;;
    2)
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        if [ -z "$domains" ]; then
            echo "Сертификаты для отзыва не найдены."
        else
            echo "Существующие домены:"
            echo "$domains"
            read -rp "Пожалуйста, введите домен из списка для отзыва сертификата: " domain
            if echo "$domains" | grep -qw "$domain"; then
                ~/.acme.sh/acme.sh --revoke -d ${domain}
                LOGI "Сертификат отозван для домена: $domain"
            else
                echo "Введен неверный домен."
            fi
        fi
        ssl_cert_issue_main
        ;;
    3)
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        if [ -z "$domains" ]; then
            echo "Сертификаты для обновления не найдены."
        else
            echo "Существующие домены:"
            echo "$domains"
            read -rp "Пожалуйста, введите домен из списка для обновления SSL сертификата: " domain
            if echo "$domains" | grep -qw "$domain"; then
                ~/.acme.sh/acme.sh --renew -d ${domain} --force
                LOGI "Сертификат принудительно обновлен для домена: $domain"
            else
                echo "Введен неверный домен."
            fi
        fi
        ssl_cert_issue_main
        ;;
    4)
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        if [ -z "$domains" ]; then
            echo "Сертификаты не найдены."
        else
            echo "Существующие домены и их пути:"
            for domain in $domains; do
                local cert_path="/root/cert/${domain}/fullchain.pem"
                local key_path="/root/cert/${domain}/privkey.pem"
                if [[ -f "${cert_path}" && -f "${key_path}" ]]; then
                    echo -e "Домен: ${domain}"
                    echo -e "\tПуть к сертификату: ${cert_path}"
                    echo -e "\tПуть к приватному ключу: ${key_path}"
                else
                    echo -e "Домен: ${domain} - Сертификат или ключ отсутствуют."
                fi
            done
        fi
        ssl_cert_issue_main
        ;;
    5)
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        if [ -z "$domains" ]; then
            echo "Сертификаты не найдены."
        else
            echo "Доступные домены:"
            echo "$domains"
            read -rp "Пожалуйста, выберите домен для установки путей панели: " domain

            if echo "$domains" | grep -qw "$domain"; then
                local webCertFile="/root/cert/${domain}/fullchain.pem"
                local webKeyFile="/root/cert/${domain}/privkey.pem"

                if [[ -f "${webCertFile}" && -f "${webKeyFile}" ]]; then
                    /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
                    echo "Пути панели установлены для домена: $domain"
                    echo "  - Файл сертификата: $webCertFile"
                    echo "  - Файл приватного ключа: $webKeyFile"
                    restart
                else
                    echo "Сертификат или приватный ключ не найдены для домена: $domain."
                fi
            else
                echo "Введен неверный домен."
            fi
        fi
        ssl_cert_issue_main
        ;;

    *)
        echo -e "${red}Неверная опция. Пожалуйста, выберите правильный номер.${plain}\n"
        ssl_cert_issue_main
        ;;
    esac
}

ssl_cert_issue() {
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    # сначала проверить acme.sh
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        echo "acme.sh не найден. Установим его"
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "Установка acme не удалась, пожалуйста, проверьте логи"
            exit 1
        fi
    fi

    # установить socat вторым
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install socat -y
        ;;
    centos | rhel | almalinux | rocky | ol)
        yum -y update && yum -y install socat
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf -y install socat
        ;;
    arch | manjaro | parch)
        pacman -Sy --noconfirm socat
        ;;
	opensuse-tumbleweed | opensuse-leap)
        zypper refresh && zypper -q install -y socat
        ;;
    alpine)
        apk add socat
        ;;
    *)
        echo -e "${red}Неподдерживаемая операционная система. Пожалуйста, проверьте скрипт и установите необходимые пакеты вручную.${plain}\n"
        exit 1
        ;;
    esac
    if [ $? -ne 0 ]; then
        LOGE "Установка socat не удалась, пожалуйста, проверьте логи"
        exit 1
    else
        LOGI "Установка socat успешна..."
    fi

    # получить домен здесь, и нам нужно его проверить
    local domain=""
    read -rp "Пожалуйста, введите ваше доменное имя: " domain
    LOGD "Ваш домен: ${domain}, проверяем его..."

    # проверить, существует ли уже сертификат
    local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')
    if [ "${currentCert}" == "${domain}" ]; then
        local certInfo=$(~/.acme.sh/acme.sh --list)
        LOGE "В системе уже есть сертификаты для этого домена. Невозможно выдать снова. Детали текущего сертификата:"
        LOGI "$certInfo"
        exit 1
    else
        LOGI "Ваш домен готов для выдачи сертификатов..."
    fi

    # создать директорию для сертификата
    certPath="/root/cert/${domain}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    else
        rm -rf "$certPath"
        mkdir -p "$certPath"
    fi

    # получить номер порта для standalone сервера
    local WebPort=80
    read -rp "Пожалуйста, выберите порт для использования (по умолчанию 80): " WebPort
    if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
        LOGE "Ваш ввод ${WebPort} неверен, будет использован порт по умолчанию 80."
        WebPort=80
    fi
    LOGI "Будет использован порт: ${WebPort} для выдачи сертификатов. Пожалуйста, убедитесь, что этот порт открыт."

    # выдать сертификат
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d ${domain} --listen-v6 --standalone --httpport ${WebPort} --force
    if [ $? -ne 0 ]; then
        LOGE "Выдача сертификата не удалась, пожалуйста, проверьте логи."
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGE "Выдача сертификата успешна, устанавливаем сертификаты..."
    fi

    reloadCmd="x-ui restart"

    LOGI "Команда --reloadcmd по умолчанию для ACME: ${yellow}x-ui restart"
    LOGI "Эта команда будет выполняться при каждой выдаче и обновлении сертификата."
    read -rp "Хотите изменить --reloadcmd для ACME? (y/n): " setReloadcmd
    if [[ "$setReloadcmd" == "y" || "$setReloadcmd" == "Y" ]]; then
        echo -e "\n${green}\t1.${plain} Предустановка: systemctl reload nginx ; x-ui restart"
        echo -e "${green}\t2.${plain} Ввести свою команду"
        echo -e "${green}\t0.${plain} Оставить reloadcmd по умолчанию"
        read -rp "Выберите опцию: " choice
        case "$choice" in
        1)
            LOGI "Reloadcmd: systemctl reload nginx ; x-ui restart"
            reloadCmd="systemctl reload nginx ; x-ui restart"
            ;;
        2)  
            LOGD "Рекомендуется поставить x-ui restart в конце, чтобы не возникала ошибка, если другие службы не работают"
            read -rp "Пожалуйста, введите ваш reloadcmd (пример: systemctl reload nginx ; x-ui restart): " reloadCmd
            LOGI "Ваш reloadcmd: ${reloadCmd}"
            ;;
        *)
            LOGI "Оставляем reloadcmd по умолчанию"
            ;;
        esac
    fi

    # установить сертификат
    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem --reloadcmd "${reloadCmd}"

    if [ $? -ne 0 ]; then
        LOGE "Установка сертификата не удалась, выход."
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGI "Установка сертификата успешна, включаем автоматическое обновление..."
    fi

    # включить автоматическое обновление
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        LOGE "Автоматическое обновление не удалось, детали сертификата:"
        ls -lah cert/*
        chmod 755 $certPath/*
        exit 1
    else
        LOGI "Автоматическое обновление успешно, детали сертификата:"
        ls -lah cert/*
        chmod 755 $certPath/*
    fi

    # Предложить пользователю установить пути панели после успешной установки сертификата
    read -rp "Хотите установить этот сертификат для панели? (y/n): " setPanel
    if [[ "$setPanel" == "y" || "$setPanel" == "Y" ]]; then
        local webCertFile="/root/cert/${domain}/fullchain.pem"
        local webKeyFile="/root/cert/${domain}/privkey.pem"

        if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
            /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
            LOGI "Пути панели установлены для домена: $domain"
            LOGI "  - Файл сертификата: $webCertFile"
            LOGI "  - Файл приватного ключа: $webKeyFile"
            echo -e "${green}URL доступа: https://${domain}:${existing_port}${existing_webBasePath}${plain}"
            restart
        else
            LOGE "Ошибка: Файл сертификата или приватного ключа не найден для домена: $domain."
        fi
    else
        LOGI "Пропускаем установку путей панели."
    fi
}

ssl_cert_issue_CF() {
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    LOGI "****** Инструкция по использованию ******"
    LOGI "Следуйте шагам ниже для завершения процесса:"
    LOGI "1. Зарегистрированный E-mail в Cloudflare."
    LOGI "2. Глобальный API ключ Cloudflare."
    LOGI "3. Доменное имя."
    LOGI "4. После выдачи сертификата вам будет предложено установить сертификат для панели (опционально)."
    LOGI "5. Скрипт также поддерживает автоматическое обновление SSL сертификата после установки."

    confirm "Вы подтверждаете информацию и хотите продолжить? [y/n]" "y"

    if [ $? -eq 0 ]; then
        # Сначала проверить acme.sh
        if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
            echo "acme.sh не найден. Установим его."
            install_acme
            if [ $? -ne 0 ]; then
                LOGE "Установка acme не удалась, пожалуйста, проверьте логи."
                exit 1
            fi
        fi

        CF_Domain=""

        LOGD "Пожалуйста, установите доменное имя:"
        read -rp "Введите ваш домен здесь: " CF_Domain
        LOGD "Ваше доменное имя установлено на: ${CF_Domain}"

        # Настроить детали API Cloudflare
        CF_GlobalKey=""
        CF_AccountEmail=""
        LOGD "Пожалуйста, установите API ключ:"
        read -rp "Введите ваш ключ здесь: " CF_GlobalKey
        LOGD "Ваш API ключ: ${CF_GlobalKey}"

        LOGD "Пожалуйста, установите зарегистрированный email:"
        read -rp "Введите ваш email здесь: " CF_AccountEmail
        LOGD "Ваш зарегистрированный email адрес: ${CF_AccountEmail}"

        # Установить CA по умолчанию на Let's Encrypt
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            LOGE "CA по умолчанию, Let'sEncrypt не удалось, скрипт завершается..."
            exit 1
        fi

        export CF_Key="${CF_GlobalKey}"
        export CF_Email="${CF_AccountEmail}"

        # Выдать сертификат используя DNS Cloudflare
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log --force
        if [ $? -ne 0 ]; then
            LOGE "Выдача сертификата не удалась, скрипт завершается..."
            exit 1
        else
            LOGI "Сертификат успешно выдан, устанавливаем..."
        fi

         # Установить сертификат
        certPath="/root/cert/${CF_Domain}"
        if [ -d "$certPath" ]; then
            rm -rf ${certPath}
        fi

        mkdir -p ${certPath}
        if [ $? -ne 0 ]; then
            LOGE "Не удалось создать директорию: ${certPath}"
            exit 1
        fi

        reloadCmd="x-ui restart"

        LOGI "Команда --reloadcmd по умолчанию для ACME: ${yellow}x-ui restart"
        LOGI "Эта команда будет выполняться при каждой выдаче и обновлении сертификата."
        read -rp "Хотите изменить --reloadcmd для ACME? (y/n): " setReloadcmd
        if [[ "$setReloadcmd" == "y" || "$setReloadcmd" == "Y" ]]; then
            echo -e "\n${green}\t1.${plain} Предустановка: systemctl reload nginx ; x-ui restart"
            echo -e "${green}\t2.${plain} Ввести свою команду"
            echo -e "${green}\t0.${plain} Оставить reloadcmd по умолчанию"
            read -rp "Выберите опцию: " choice
            case "$choice" in
            1)
                LOGI "Reloadcmd: systemctl reload nginx ; x-ui restart"
                reloadCmd="systemctl reload nginx ; x-ui restart"
                ;;
            2)  
                LOGD "Рекомендуется поставить x-ui restart в конце, чтобы не возникала ошибка, если другие службы не работают"
                read -rp "Пожалуйста, введите ваш reloadcmd (пример: systemctl reload nginx ; x-ui restart): " reloadCmd
                LOGI "Ваш reloadcmd: ${reloadCmd}"
                ;;
            *)
                LOGI "Оставляем reloadcmd по умолчанию"
                ;;
            esac
        fi
        ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} \
            --key-file ${certPath}/privkey.pem \
            --fullchain-file ${certPath}/fullchain.pem --reloadcmd "${reloadCmd}"
        
        if [ $? -ne 0 ]; then
            LOGE "Установка сертификата не удалась, скрипт завершается..."
            exit 1
        else
            LOGI "Сертификат успешно установлен, включаем автоматические обновления..."
        fi

        # Включить автоматическое обновление
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "Настройка автоматического обновления не удалась, скрипт завершается..."
            exit 1
        else
            LOGI "Сертификат установлен и автоматическое обновление включено. Конкретная информация следующая:"
            ls -lah ${certPath}/*
            chmod 755 ${certPath}/*
        fi

        # Предложить пользователю установить пути панели после успешной установки сертификата
        read -rp "Хотите установить этот сертификат для панели? (y/n): " setPanel
        if [[ "$setPanel" == "y" || "$setPanel" == "Y" ]]; then
            local webCertFile="${certPath}/fullchain.pem"
            local webKeyFile="${certPath}/privkey.pem"

            if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
                /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
                LOGI "Пути панели установлены для домена: $CF_Domain"
                LOGI "  - Файл сертификата: $webCertFile"
                LOGI "  - Файл приватного ключа: $webKeyFile"
                echo -e "${green}URL доступа: https://${CF_Domain}:${existing_port}${existing_webBasePath}${plain}"
                restart
            else
                LOGE "Ошибка: Файл сертификата или приватного ключа не найден для домена: $CF_Domain."
            fi
        else
            LOGI "Пропускаем установку путей панели."
        fi
    else
        show_menu
    fi
}

run_speedtest() {
    # Проверить, установлен ли Speedtest
    if ! command -v speedtest &>/dev/null; then
        # Если не установлен, определить метод установки
        if command -v snap &>/dev/null; then
            # Использовать snap для установки Speedtest
            echo "Установка Speedtest используя snap..."
            snap install speedtest
        else
            # Резервный вариант - использовать менеджеры пакетов
            local pkg_manager=""
            local speedtest_install_script=""

            if command -v dnf &>/dev/null; then
                pkg_manager="dnf"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh"
            elif command -v yum &>/dev/null; then
                pkg_manager="yum"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh"
            elif command -v apt-get &>/dev/null; then
                pkg_manager="apt-get"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
            elif command -v apt &>/dev/null; then
                pkg_manager="apt"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
            fi

            if [[ -z $pkg_manager ]]; then
                echo "Ошибка: Менеджер пакетов не найден. Возможно, вам нужно установить Speedtest вручную."
                return 1
            else
                echo "Установка Speedtest используя $pkg_manager..."
                curl -s $speedtest_install_script | bash
                $pkg_manager install -y speedtest
            fi
        fi
    fi

    speedtest
}

nginx_check_ports() {
    local port_80_open=false
    local port_443_open=false
    local port_80_used=false
    local port_443_used=false
    
    # Проверка открытости портов через netstat/ss
    if command -v ss &>/dev/null; then
        if ss -tuln | grep -q ":80 "; then
            port_80_open=true
        fi
        if ss -tuln | grep -q ":443 "; then
            port_443_open=true
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tuln | grep -q ":80 "; then
            port_80_open=true
        fi
        if netstat -tuln | grep -q ":443 "; then
            port_443_open=true
        fi
    fi
    
    # Проверка использования портов в инбаундах X-UI
    if [ -f "/etc/x-ui/x-ui.db" ]; then
        if command -v sqlite3 &>/dev/null; then
            # Проверяем порт 80
            if sqlite3 /etc/x-ui/x-ui.db "SELECT port FROM inbounds WHERE port = 80 LIMIT 1;" 2>/dev/null | grep -q "80"; then
                port_80_used=true
            fi
            # Проверяем порт 443
            if sqlite3 /etc/x-ui/x-ui.db "SELECT port FROM inbounds WHERE port = 443 LIMIT 1;" 2>/dev/null | grep -q "443"; then
                port_443_used=true
            fi
        fi
    fi
    
    # Вывод предупреждений
    echo ""
    echo -e "${yellow}════════════════════════════════════════════════${plain}"
    echo -e "${yellow}           ПРОВЕРКА ПОРТОВ${plain}"
    echo -e "${yellow}════════════════════════════════════════════════${plain}"
    
    if [ "$port_80_open" = true ]; then
        echo -e "${red}⚠ ПРЕДУПРЕЖДЕНИЕ: Порт 80 уже открыт!${plain}"
        if [ "$port_80_used" = true ]; then
            echo -e "${red}   Порт 80 используется в инбаунде X-UI!${plain}"
        fi
        echo -e "${yellow}   Nginx требует порт 80 для работы.${plain}"
    else
        echo -e "${green}✓ Порт 80 свободен${plain}"
    fi
    
    if [ "$port_443_open" = true ]; then
        echo -e "${red}⚠ ПРЕДУПРЕЖДЕНИЕ: Порт 443 уже открыт!${plain}"
        if [ "$port_443_used" = true ]; then
            echo -e "${red}   Порт 443 используется в инбаунде X-UI!${plain}"
        fi
        echo -e "${yellow}   Nginx требует порт 443 для работы.${plain}"
    else
        echo -e "${green}✓ Порт 443 свободен${plain}"
    fi
    
    echo -e "${yellow}════════════════════════════════════════════════${plain}"
    echo ""
    
    if [ "$port_80_open" = true ] || [ "$port_443_open" = true ]; then
        echo -e "${yellow}Продолжить установку? (y/n):${plain}"
        read -p "-> " confirm_continue
        if [ "$confirm_continue" != "y" ] && [ "$confirm_continue" != "Y" ]; then
            LOGE "Установка отменена."
            return 1
        fi
    fi
    return 0
}

nginx_generate_location_block() {
    local trans_type=$1
    local path_name=$2
    local target=$3 # IP:PORT

    local block=""

    # === gRPC ===
    if [ "$trans_type" == "1" ]; then
        block="\n    # --- gRPC ($path_name) ---\n    location $path_name {\n        if (\$content_type !~ \"application/grpc\") { return 404; }\n        client_max_body_size 0;\n        grpc_socket_keepalive on;\n        grpc_read_timeout 1h;\n        grpc_send_timeout 1h;\n        grpc_pass grpc://$target;\n    }"

    # === WebSocket ===
    elif [ "$trans_type" == "2" ]; then
        block="\n    # --- WebSocket ($path_name) ---\n    location $path_name {\n        if (\$http_upgrade != \"websocket\") { return 404; }\n        proxy_http_version 1.1;\n        proxy_set_header Upgrade \$http_upgrade;\n        proxy_set_header Connection \"upgrade\";\n        proxy_buffering off;\n        proxy_read_timeout 1h;\n        proxy_send_timeout 1h;\n        proxy_pass http://$target;\n        proxy_set_header X-Real-IP \$remote_addr;\n        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n        proxy_set_header Host \$host;\n    }"

    # === XHTTP ===
    elif [ "$trans_type" == "3" ]; then
        block="\n    # --- SplitHTTP ($path_name) ---\n    location $path_name {\n        client_max_body_size 0;\n        proxy_buffering off;\n        proxy_request_buffering off;\n        proxy_http_version 1.1;\n        proxy_set_header Connection \"\";\n        keepalive_timeout 1h;\n        proxy_pass http://$target;\n        proxy_set_header X-Real-IP \$remote_addr;\n        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n        proxy_set_header Host \$host;\n    }"
    fi

    echo "$block"
}

install_nginx_reverse_proxy() {
    echo ""
    echo -e "${green}====================================================${plain}"
    echo -e "${green}       NGINX + 3XUI: Автоустановщик Reverse Proxy      ${plain}"
    echo -e "${green}====================================================${plain}"
    
    echo ""
    echo -e "${yellow}Что вы хотите сделать?${plain}"
    echo "1) Полная установка с нуля (Nginx + SSL + Конфиг)"
    echo "2) Добавить новый маршрут (Location) в существующий конфиг"
    read -p "Ваш выбор (1 или 2): " MAIN_ACTION

    # ==========================================================
    # ВЕТКА 2: ДОБАВЛЕНИЕ LOCATION (БЫСТРАЯ)
    # ==========================================================
    if [ "$MAIN_ACTION" == "2" ]; then
        echo ""
        echo -e "${green}Введите домен ЭТОГО сервера (чей конфиг правим):${plain}"
        read -p "-> " CURRENT_DOMAIN
        
        CONF_FILE="/etc/nginx/sites-available/$CURRENT_DOMAIN.conf"
        
        if [ ! -f "$CONF_FILE" ]; then
            LOGE "Конфиг файл $CONF_FILE не найден!"
            if [[ $# == 0 ]]; then
                before_show_menu
            fi
            return 1
        fi

        echo -e "${green}--- Настройка нового маршрута ---${plain}"
        echo "1) gRPC"
        echo "2) WebSocket (WS)"
        echo "3) XHTTP / SplitHTTP"
        read -p "Выберите транспорт: " TRANSPORT_TYPE

        echo -e "Введите путь (например ${blue}/grpc-new${plain}):"
        read -p "-> " PATH_NAME

        echo -e "Введите ЛОКАЛЬНЫЙ порт Inbound (например ${blue}2055${plain}):"
        read -p "-> " L_PORT
        TARGET="127.0.0.1:$L_PORT"

        # Генерируем блок
        NEW_BLOCK=$(nginx_generate_location_block "$TRANSPORT_TYPE" "$PATH_NAME" "$TARGET")

        # Вставляем в конфиг (удаляем последнюю скобку, пишем блок, возвращаем скобку)
        # Используем временный файл для безопасности
        head -n -1 "$CONF_FILE" > "${CONF_FILE}.tmp"
        echo -e "$NEW_BLOCK" >> "${CONF_FILE}.tmp"
        echo "}" >> "${CONF_FILE}.tmp"
        
        mv "${CONF_FILE}.tmp" "$CONF_FILE"

        LOGI "Проверка и перезагрузка Nginx..."
        nginx -t
        if [ $? -eq 0 ]; then
            systemctl reload nginx
            LOGI "Маршрут добавлен успешно!"
        else
            LOGE "Ошибка в конфиге!"
        fi
        
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi

    # ==========================================================
    # ВЕТКА 1: ПОЛНАЯ УСТАНОВКА
    # ==========================================================

    # 1. ПРОВЕРКА ПОРТОВ
    nginx_check_ports
    if [ $? -ne 0 ]; then
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi

    # 2. УСТАНОВКА ПАКЕТОВ
    LOGI "Установка Nginx и Certbot..."
    apt-get update -qq
    apt-get install -y nginx curl certbot -qq

    # 3. ВВОД ДОМЕНА
    echo ""
    echo -e "${green}Введите домен ЭТОГО сервера (например: rus.tunnel.ru):${plain}"
    read -p "-> " CURRENT_DOMAIN
    if [ -z "$CURRENT_DOMAIN" ]; then
        LOGE "Домен обязателен!"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi

    # 4. SSL - ИСПОЛЬЗУЕМ СЕРТИФИКАТЫ 3XUI
    echo ""
    echo -e "${yellow}Откуда берем SSL сертификаты?${plain}"
    echo "1) Сгенерировать НОВЫЕ бесплатно (Let's Encrypt)"
    echo "2) Использовать существующие из 3XUI (/root/cert/...)"
    read -p "Ваш выбор: " CERT_MODE

    FINAL_CRT=""
    FINAL_KEY=""

    if [ "$CERT_MODE" == "1" ]; then
        systemctl stop nginx
        LOGI "Генерация SSL..."
        certbot certonly --standalone -d "$CURRENT_DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email
        if [ $? -eq 0 ]; then
            FINAL_CRT="/etc/letsencrypt/live/$CURRENT_DOMAIN/fullchain.pem"
            FINAL_KEY="/etc/letsencrypt/live/$CURRENT_DOMAIN/privkey.pem"
        else
            LOGE "Ошибка получения SSL!"
            if [[ $# == 0 ]]; then
                before_show_menu
            fi
            return 1
        fi
    else
        # Используем стандартный путь 3XUI
        CERT_SRC="/root/cert/$CURRENT_DOMAIN"
        if [ ! -f "$CERT_SRC/fullchain.pem" ]; then
            LOGE "Файлы сертификатов не найдены в $CERT_SRC!"
            echo -e "${yellow}Проверьте, что сертификаты установлены через 3XUI.${plain}"
            if [[ $# == 0 ]]; then
                before_show_menu
            fi
            return 1
        fi
        # Копируем в стандартное место для Nginx
        CERT_DEST="/etc/nginx/ssl/$CURRENT_DOMAIN"
        mkdir -p "$CERT_DEST"
        cp "$CERT_SRC/fullchain.pem" "$CERT_DEST/fullchain.pem"
        cp "$CERT_SRC/privkey.pem" "$CERT_DEST/privkey.pem"
        chmod -R 755 "$CERT_DEST"
        FINAL_CRT="$CERT_DEST/fullchain.pem"
        FINAL_KEY="$CERT_DEST/privkey.pem"
    fi

    # 5. ЗАГЛУШКА
    mkdir -p /var/www/html
    echo "<h1>System Operational</h1>" > /var/www/html/index.html
    chown -R www-data:www-data /var/www/html

    # 6. СБОРКА ЛОКАЦИЙ (ТОЛЬКО BACKEND РЕЖИМ)
    echo ""
    echo -e "${green}Режим работы: Проксирующий под 3XUI (BACKEND -> Принимает на 127.0.0.1)${plain}"
    LOCATIONS_CONF=""
    while true; do
        echo ""
        echo -e "${green}--- Добавление маршрута ---${plain}"
        echo "1) gRPC"
        echo "2) WebSocket (WS)"
        echo "3) XHTTP / SplitHTTP"
        echo "0) ДАЛЕЕ (Создать конфиг)"
        read -p "Выбор: " T_TYPE
        if [ "$T_TYPE" == "0" ]; then break; fi

        read -p "Путь (например /secret): " P_NAME

        read -p "Локальный порт Inbound (например 2053): " L_PORT
        TARGET="127.0.0.1:$L_PORT"

        BLOCK=$(nginx_generate_location_block "$T_TYPE" "$P_NAME" "$TARGET")
        LOCATIONS_CONF+="$BLOCK"
        LOGI "Добавлено!"
    done

    # 7. ЗАПИСЬ КОНФИГА
    CONF_FILE="/etc/nginx/sites-available/$CURRENT_DOMAIN.conf"
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default

    cat <<EOF > "$CONF_FILE"
server {
    listen 80;
    server_name $CURRENT_DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name $CURRENT_DOMAIN;
    ssl_certificate $FINAL_CRT;
    ssl_certificate_key $FINAL_KEY;
    ssl_protocols TLSv1.2;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    keepalive_timeout 1h;
    client_body_timeout 1h;
    client_max_body_size 0;
    root /var/www/html;
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
$LOCATIONS_CONF
}
EOF

    ln -sf "$CONF_FILE" "/etc/nginx/sites-enabled/$CURRENT_DOMAIN.conf"

    LOGI "Перезагрузка Nginx..."
    nginx -t
    if [ $? -eq 0 ]; then
        systemctl restart nginx
        LOGI "Nginx успешно настроен!"
        echo ""
        echo -e "${green}════════════════════════════════════════════════${plain}"
        echo -e "${green}   Nginx успешно настроен!${plain}"
        echo -e "${green}════════════════════════════════════════════════${plain}"
        echo -e "${blue}Конфиг: $CONF_FILE${plain}"
        echo -e "${blue}Для добавления новых маршрутов запустите скрипт снова и выберите опцию 2.${plain}"
    else
        LOGE "ОШИБКА КОНФИГУРАЦИИ!"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}



ip_validation() {
    ipv6_regex="^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$"
    ipv4_regex="^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$"
}

iplimit_main() {
    echo -e "\n${green}\t1.${plain} Установить Fail2ban и настроить лимит IP"
    echo -e "${green}\t2.${plain} Изменить длительность бана"
    echo -e "${green}\t3.${plain} Разбанить всех"
    echo -e "${green}\t4.${plain} Логи банов"
    echo -e "${green}\t5.${plain} Забанить IP адрес"
    echo -e "${green}\t6.${plain} Разбанить IP адрес"
    echo -e "${green}\t7.${plain} Логи в реальном времени"
    echo -e "${green}\t8.${plain} Статус службы"
    echo -e "${green}\t9.${plain} Перезапуск службы"
    echo -e "${green}\t10.${plain} Удалить Fail2ban и лимит IP"
    echo -e "${green}\t0.${plain} Вернуться в главное меню"
    read -rp "Выберите опцию: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        confirm "Продолжить установку Fail2ban и лимита IP?" "y"
        if [[ $? == 0 ]]; then
            install_iplimit
        else
            iplimit_main
        fi
        ;;
    2)
        read -rp "Пожалуйста, введите новую длительность бана в минутах [по умолчанию 30]: " NUM
        if [[ $NUM =~ ^[0-9]+$ ]]; then
            create_iplimit_jails ${NUM}
            if [[ $release == "alpine" ]]; then
                rc-service fail2ban restart
            else
                systemctl restart fail2ban
            fi
        else
            echo -e "${red}${NUM} не является числом! Пожалуйста, попробуйте снова.${plain}"
        fi
        iplimit_main
        ;;
    3)
        confirm "Продолжить разбан всех из тюрьмы лимита IP?" "y"
        if [[ $? == 0 ]]; then
            fail2ban-client reload --restart --unban 3x-ipl
            truncate -s 0 "${iplimit_banned_log_path}"
            echo -e "${green}Все пользователи успешно разбанены.${plain}"
            iplimit_main
        else
            echo -e "${yellow}Отменено.${plain}"
        fi
        iplimit_main
        ;;
    4)
        show_banlog
        iplimit_main
        ;;
    5)
        read -rp "Введите IP адрес, который хотите забанить: " ban_ip
        ip_validation
        if [[ $ban_ip =~ $ipv4_regex || $ban_ip =~ $ipv6_regex ]]; then
            fail2ban-client set 3x-ipl banip "$ban_ip"
            echo -e "${green}IP адрес ${ban_ip} успешно забанен.${plain}"
        else
            echo -e "${red}Неверный формат IP адреса! Пожалуйста, попробуйте снова.${plain}"
        fi
        iplimit_main
        ;;
    6)
        read -rp "Введите IP адрес, который хотите разбанить: " unban_ip
        ip_validation
        if [[ $unban_ip =~ $ipv4_regex || $unban_ip =~ $ipv6_regex ]]; then
            fail2ban-client set 3x-ipl unbanip "$unban_ip"
            echo -e "${green}IP адрес ${unban_ip} успешно разбанен.${plain}"
        else
            echo -e "${red}Неверный формат IP адреса! Пожалуйста, попробуйте снова.${plain}"
        fi
        iplimit_main
        ;;
    7)
        tail -f /var/log/fail2ban.log
        iplimit_main
        ;;
    8)
        service fail2ban status
        iplimit_main
        ;;
    9)
        if [[ $release == "alpine" ]]; then
            rc-service fail2ban restart
        else
            systemctl restart fail2ban
        fi
        iplimit_main
        ;;
    10)
        remove_iplimit
        iplimit_main
        ;;
    *)
        echo -e "${red}Неверная опция. Пожалуйста, выберите правильный номер.${plain}\n"
        iplimit_main
        ;;
    esac
}

install_iplimit() {
    if ! command -v fail2ban-client &>/dev/null; then
        echo -e "${green}Fail2ban не установлен. Устанавливаем сейчас...!${plain}\n"

        # Проверить ОС и установить необходимые пакеты
        case "${release}" in
        ubuntu)
            apt-get update
            if [[ "${os_version}" -ge 24 ]]; then
                apt-get install python3-pip -y
                python3 -m pip install pyasynchat --break-system-packages
            fi
            apt-get install fail2ban -y
            ;;
        debian)
            apt-get update
            if [ "$os_version" -ge 12 ]; then
                apt-get install -y python3-systemd
            fi
            apt-get install -y fail2ban
            ;;
        armbian)
            apt-get update && apt-get install fail2ban -y
            ;;
        centos | rhel | almalinux | rocky | ol)
            yum update -y && yum install epel-release -y
            yum -y install fail2ban
            ;;
        fedora | amzn | virtuozzo)
            dnf -y update && dnf -y install fail2ban
            ;;
        arch | manjaro | parch)
            pacman -Syu --noconfirm fail2ban
            ;;
        alpine)
            apk add fail2ban
            ;;
        *)
            echo -e "${red}Неподдерживаемая операционная система. Пожалуйста, проверьте скрипт и установите необходимые пакеты вручную.${plain}\n"
            exit 1
            ;;
        esac

        if ! command -v fail2ban-client &>/dev/null; then
            echo -e "${red}Установка Fail2ban не удалась.${plain}\n"
            exit 1
        fi

        echo -e "${green}Fail2ban успешно установлен!${plain}\n"
    else
        echo -e "${yellow}Fail2ban уже установлен.${plain}\n"
    fi

    echo -e "${green}Настройка лимита IP...${plain}\n"

    # убедиться, что нет конфликтов для файлов jail
    iplimit_remove_conflicts

    # Проверить, существует ли файл лога
    if ! test -f "${iplimit_banned_log_path}"; then
        touch ${iplimit_banned_log_path}
    fi

    # Проверить, существует ли файл лога службы, чтобы fail2ban не возвращал ошибку
    if ! test -f "${iplimit_log_path}"; then
        touch ${iplimit_log_path}
    fi

    # Создать файлы jail для iplimit
    # мы не передали bantime здесь, чтобы использовать значение по умолчанию
    create_iplimit_jails

    # Запуск fail2ban
    if [[ $release == "alpine" ]]; then
        if [[ $(rc-service fail2ban status | grep -F 'status: started' -c) == 0 ]]; then
            rc-service fail2ban start
        else
            rc-service fail2ban restart
        fi
        rc-update add fail2ban
    else
        if ! systemctl is-active --quiet fail2ban; then
            systemctl start fail2ban
        else
            systemctl restart fail2ban
        fi
        systemctl enable fail2ban
    fi

    echo -e "${green}Лимит IP успешно установлен и настроен!${plain}\n"
    before_show_menu
}

remove_iplimit() {
    echo -e "${green}\t1.${plain} Только удалить конфигурации лимита IP"
    echo -e "${green}\t2.${plain} Удалить Fail2ban и лимит IP"
    echo -e "${green}\t0.${plain} Вернуться в главное меню"
    read -rp "Выберите опцию: " num
    case "$num" in
    1)
        rm -f /etc/fail2ban/filter.d/3x-ipl.conf
        rm -f /etc/fail2ban/action.d/3x-ipl.conf
        rm -f /etc/fail2ban/jail.d/3x-ipl.conf
        if [[ $release == "alpine" ]]; then
            rc-service fail2ban restart
        else
            systemctl restart fail2ban
        fi
        echo -e "${green}Лимит IP успешно удален!${plain}\n"
        before_show_menu
        ;;
    2)
        rm -rf /etc/fail2ban
        if [[ $release == "alpine" ]]; then
            rc-service fail2ban stop
        else
            systemctl stop fail2ban
        fi
        case "${release}" in
        ubuntu | debian | armbian)
            apt-get remove -y fail2ban
            apt-get purge -y fail2ban -y
            apt-get autoremove -y
            ;;
        centos | rhel | almalinux | rocky | ol)
            yum remove fail2ban -y
            yum autoremove -y
            ;;
        fedora | amzn | virtuozzo)
            dnf remove fail2ban -y
            dnf autoremove -y
            ;;
        arch | manjaro | parch)
            pacman -Rns --noconfirm fail2ban
            ;;
        alpine)
            apk del fail2ban
            ;;
        *)
            echo -e "${red}Неподдерживаемая операционная система. Пожалуйста, удалите Fail2ban вручную.${plain}\n"
            exit 1
            ;;
        esac
        echo -e "${green}Fail2ban и лимит IP успешно удалены!${plain}\n"
        before_show_menu
        ;;
    0)
        show_menu
        ;;
    *)
        echo -e "${red}Неверная опция. Пожалуйста, выберите правильный номер.${plain}\n"
        remove_iplimit
        ;;
    esac
}

show_banlog() {
    local system_log="/var/log/fail2ban.log"

    echo -e "${green}Проверка логов банов...${plain}\n"

    if [[ $release == "alpine" ]]; then
        if [[ $(rc-service fail2ban status | grep -F 'status: started' -c) == 0 ]]; then
            echo -e "${red}Служба Fail2ban не запущена!${plain}\n"
            return 1
        fi
    else
        if ! systemctl is-active --quiet fail2ban; then
            echo -e "${red}Служба Fail2ban не запущена!${plain}\n"
            return 1
        fi
    fi

    if [[ -f "$system_log" ]]; then
        echo -e "${green}Недавние системные действия по банам из fail2ban.log:${plain}"
        grep "3x-ipl" "$system_log" | grep -E "Ban|Unban" | tail -n 10 || echo -e "${yellow}Недавних системных действий по банам не найдено${plain}"
        echo ""
    fi

    if [[ -f "${iplimit_banned_log_path}" ]]; then
        echo -e "${green}Записи логов банов 3X-IPL:${plain}"
        if [[ -s "${iplimit_banned_log_path}" ]]; then
            grep -v "INIT" "${iplimit_banned_log_path}" | tail -n 10 || echo -e "${yellow}Записей банов не найдено${plain}"
        else
            echo -e "${yellow}Файл лога банов пуст${plain}"
        fi
    else
        echo -e "${red}Файл лога банов не найден по пути: ${iplimit_banned_log_path}${plain}"
    fi

    echo -e "\n${green}Текущий статус тюрьмы:${plain}"
    fail2ban-client status 3x-ipl || echo -e "${yellow}Не удалось получить статус тюрьмы${plain}"
}

create_iplimit_jails() {
    # Использовать время бана по умолчанию, если не передано => 30 минут
    local bantime="${1:-30}"

    # Раскомментировать 'allowipv6 = auto' в fail2ban.conf
    sed -i 's/#allowipv6 = auto/allowipv6 = auto/g' /etc/fail2ban/fail2ban.conf

    # На Debian 12+ backend по умолчанию для fail2ban должен быть изменен на systemd
    if [[  "${release}" == "debian" && ${os_version} -ge 12 ]]; then
        sed -i '0,/action =/s/backend = auto/backend = systemd/' /etc/fail2ban/jail.conf
    fi

    cat << EOF > /etc/fail2ban/jail.d/3x-ipl.conf
[3x-ipl]
enabled=true
backend=auto
filter=3x-ipl
action=3x-ipl
logpath=${iplimit_log_path}
maxretry=2
findtime=32
bantime=${bantime}m
EOF

    cat << EOF > /etc/fail2ban/filter.d/3x-ipl.conf
[Definition]
datepattern = ^%%Y/%%m/%%d %%H:%%M:%%S
failregex   = \[LIMIT_IP\]\s*Email\s*=\s*<F-USER>.+</F-USER>\s*\|\|\s*SRC\s*=\s*<ADDR>
ignoreregex =
EOF

    cat << EOF > /etc/fail2ban/action.d/3x-ipl.conf
[INCLUDES]
before = iptables-allports.conf

[Definition]
actionstart = <iptables> -N f2b-<name>
              <iptables> -A f2b-<name> -j <returntype>
              <iptables> -I <chain> -p <protocol> -j f2b-<name>

actionstop = <iptables> -D <chain> -p <protocol> -j f2b-<name>
             <actionflush>
             <iptables> -X f2b-<name>

actioncheck = <iptables> -n -L <chain> | grep -q 'f2b-<name>[ \t]'

actionban = <iptables> -I f2b-<name> 1 -s <ip> -j <blocktype>
            echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   BAN   [Email] = <F-USER> [IP] = <ip> banned for <bantime> seconds." >> ${iplimit_banned_log_path}

actionunban = <iptables> -D f2b-<name> -s <ip> -j <blocktype>
              echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   UNBAN   [Email] = <F-USER> [IP] = <ip> unbanned." >> ${iplimit_banned_log_path}

[Init]
name = default
protocol = tcp
chain = INPUT
EOF

    echo -e "${green}Файлы jail лимита IP созданы с временем бана ${bantime} минут.${plain}"
}

iplimit_remove_conflicts() {
    local jail_files=(
        /etc/fail2ban/jail.conf
        /etc/fail2ban/jail.local
    )

    for file in "${jail_files[@]}"; do
        # Проверить конфигурацию [3x-ipl] в файле jail, затем удалить её
        if test -f "${file}" && grep -qw '3x-ipl' ${file}; then
            sed -i "/\[3x-ipl\]/,/^$/d" ${file}
            echo -e "${yellow}Удаление конфликтов [3x-ipl] в jail (${file})!${plain}\n"
        fi
    done
}

SSH_port_forwarding() {
    local URL_lists=(
        "https://api4.ipify.org"
		"https://ipv4.icanhazip.com"
		"https://v4.api.ipinfo.io/ip"
		"https://ipv4.myexternalip.com/raw"
		"https://4.ident.me"
		"https://check-host.net/ip"
    )
    local server_ip=""
    for ip_address in "${URL_lists[@]}"; do
        server_ip=$(curl -s --max-time 3 "${ip_address}" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "${server_ip}" ]]; then
            break
        fi
    done
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_listenIP=$(/usr/local/x-ui/x-ui setting -getListen true | grep -Eo 'listenIP: .+' | awk '{print $2}')
    local existing_cert=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
    local existing_key=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'key: .+' | awk '{print $2}')

    local config_listenIP=""
    local listen_choice=""

    if [[ -n "$existing_cert" && -n "$existing_key" ]]; then
        echo -e "${green}Панель защищена SSL.${plain}"
        before_show_menu
    fi
    if [[ -z "$existing_cert" && -z "$existing_key" && (-z "$existing_listenIP" || "$existing_listenIP" == "0.0.0.0") ]]; then
        echo -e "\n${red}Предупреждение: Сертификат и ключ не найдены! Панель не защищена.${plain}"
        echo "Пожалуйста, получите сертификат или настройте SSH проброс портов."
    fi

    if [[ -n "$existing_listenIP" && "$existing_listenIP" != "0.0.0.0" && (-z "$existing_cert" && -z "$existing_key") ]]; then
        echo -e "\n${green}Текущая конфигурация SSH проброса портов:${plain}"
        echo -e "Стандартная SSH команда:"
        echo -e "${yellow}ssh -L 2222:${existing_listenIP}:${existing_port} root@${server_ip}${plain}"
        echo -e "\nЕсли используется SSH ключ:"
        echo -e "${yellow}ssh -i <sshkeypath> -L 2222:${existing_listenIP}:${existing_port} root@${server_ip}${plain}"
        echo -e "\nПосле подключения доступ к панели по адресу:"
        echo -e "${yellow}http://localhost:2222${existing_webBasePath}${plain}"
    fi

    echo -e "\nВыберите опцию:"
    echo -e "${green}1.${plain} Установить IP для прослушивания"
    echo -e "${green}2.${plain} Очистить IP для прослушивания"
    echo -e "${green}0.${plain} Вернуться в главное меню"
    read -rp "Выберите опцию: " num

    case "$num" in
    1)
        if [[ -z "$existing_listenIP" || "$existing_listenIP" == "0.0.0.0" ]]; then
            echo -e "\nIP для прослушивания не настроен. Выберите опцию:"
            echo -e "1. Использовать IP по умолчанию (127.0.0.1)"
            echo -e "2. Установить пользовательский IP"
            read -rp "Выберите опцию (1 или 2): " listen_choice

            config_listenIP="127.0.0.1"
            [[ "$listen_choice" == "2" ]] && read -rp "Введите пользовательский IP для прослушивания: " config_listenIP

            /usr/local/x-ui/x-ui setting -listenIP "${config_listenIP}" >/dev/null 2>&1
            echo -e "${green}IP для прослушивания установлен на ${config_listenIP}.${plain}"
            echo -e "\n${green}Конфигурация SSH проброса портов:${plain}"
            echo -e "Стандартная SSH команда:"
            echo -e "${yellow}ssh -L 2222:${config_listenIP}:${existing_port} root@${server_ip}${plain}"
            echo -e "\nЕсли используется SSH ключ:"
            echo -e "${yellow}ssh -i <sshkeypath> -L 2222:${config_listenIP}:${existing_port} root@${server_ip}${plain}"
            echo -e "\nПосле подключения доступ к панели по адресу:"
            echo -e "${yellow}http://localhost:2222${existing_webBasePath}${plain}"
            restart
        else
            config_listenIP="${existing_listenIP}"
            echo -e "${green}Текущий IP для прослушивания уже установлен на ${config_listenIP}.${plain}"
        fi
        ;;
    2)
        /usr/local/x-ui/x-ui setting -listenIP 0.0.0.0 >/dev/null 2>&1
        echo -e "${green}IP для прослушивания очищен.${plain}"
        restart
        ;;
    0)
        show_menu
        ;;
    *)
        echo -e "${red}Неверная опция. Пожалуйста, выберите правильный номер.${plain}\n"
        SSH_port_forwarding
        ;;
    esac
}

show_usage() {
    echo -e "┌────────────────────────────────────────────────────────────────
│  ${blue}Использование меню управления x-ui (подкоманды):${plain}            
│                                                                
│  ${blue}x-ui${plain}                       - Скрипт управления администратором          
│  ${blue}x-ui start${plain}                 - Запустить                            
│  ${blue}x-ui stop${plain}                  - Остановить                             
│  ${blue}x-ui restart${plain}               - Перезапустить                          
│  ${blue}x-ui status${plain}                - Текущий статус                   
│  ${blue}x-ui settings${plain}              - Текущие настройки                 
│  ${blue}x-ui enable${plain}                - Включить автозапуск при загрузке ОС   
│  ${blue}x-ui disable${plain}               - Отключить автозапуск при загрузке ОС  
│  ${blue}x-ui log${plain}                   - Проверить логи                       
│  ${blue}x-ui banlog${plain}                - Проверить логи банов Fail2ban          
│  ${blue}x-ui update${plain}                - Обновить                           
│  ${blue}x-ui update-all-geofiles${plain}   - Обновить все геофайлы             
│  ${blue}x-ui legacy${plain}                - Старая версия                   
│  ${blue}x-ui install${plain}               - Установить                          
│  ${blue}x-ui uninstall${plain}             - Удалить                        
│  ${blue}x-ui nginx-install${plain}         - Установить NGINX Reverse Proxy    
└────────────────────────────────────────────────────────────────┘"
}

show_menu() {
    echo -e "
╔════════════════════════════════════════════════╗
│   ${green}Скрипт управления панелью 3X-UI${plain}                
│   ${green}0.${plain} Выход из скрипта                               
│════════════════════════════════════════════════│
│   ${green}1.${plain} Установить                                   
│   ${green}2.${plain} Обновить                                    
│   ${green}3.${plain} Обновить меню                               
│   ${green}4.${plain} Старая версия                               
│   ${green}5.${plain} Удалить                                   
│════════════════════════════════════════════════│
│   ${green}6.${plain} Сбросить имя пользователя и пароль                 
│   ${green}7.${plain} Сбросить базовый путь веб-интерфейса                       
│   ${green}8.${plain} Сбросить настройки                            
│   ${green}9.${plain} Изменить порт                               
│  ${green}10.${plain} Просмотреть текущие настройки                     
│════════════════════════════════════════════════│
│  ${green}11.${plain} Запустить                                     
│  ${green}12.${plain} Остановить                                     
│  ${green}13.${plain} Перезапустить                                   
│  ${green}14.${plain} Проверить статус                              
│  ${green}15.${plain} Управление логами                             
│════════════════════════════════════════════════│
│  ${green}16.${plain} Включить автозапуск                             
│  ${green}17.${plain} Отключить автозапуск                            
│════════════════════════════════════════════════│
│  ${green}18.${plain} Управление SSL сертификатами                
│  ${green}19.${plain} SSL сертификат Cloudflare                
│  ${green}20.${plain} Управление лимитом IP                       
│  ${green}21.${plain} Управление файрволом                       
│  ${green}22.${plain} Управление SSH пробросом портов            
│════════════════════════════════════════════════│
│  ${green}23.${plain} Включить BBR                                 
│  ${green}24.${plain} Обновить геофайлы                             
│  ${green}25.${plain} Speedtest от Ookla                            
│  ${green}26.${plain} Установить NGINX Reverse Proxy                
╚════════════════════════════════════════════════╝
"
    show_status
    echo && read -rp "Пожалуйста, введите ваш выбор [0-26]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        check_uninstall && install
        ;;
    2)
        check_install && update
        ;;
    3)
        check_install && update_menu
        ;;
    4)
        check_install && legacy_version
        ;;
    5)
        check_install && uninstall
        ;;
    6)
        check_install && reset_user
        ;;
    7)
        check_install && reset_webbasepath
        ;;
    8)
        check_install && reset_config
        ;;
    9)
        check_install && set_port
        ;;
    10)
        check_install && check_config
        ;;
    11)
        check_install && start
        ;;
    12)
        check_install && stop
        ;;
    13)
        check_install && restart
        ;;
    14)
        check_install && status
        ;;
    15)
        check_install && show_log
        ;;
    16)
        check_install && enable
        ;;
    17)
        check_install && disable
        ;;
    18)
        ssl_cert_issue_main
        ;;
    19)
        ssl_cert_issue_CF
        ;;
    20)
        iplimit_main
        ;;
    21)
        firewall_menu
        ;;
    22)
        SSH_port_forwarding
        ;;
    23)
        bbr_menu
        ;;
    24)
        update_geo
        ;;
    25)
        run_speedtest
        ;;
    26)
        install_nginx_reverse_proxy
        ;;
    *)
        LOGE "Пожалуйста, введите правильный номер [0-26]"
        ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start")
        check_install 0 && start 0
        ;;
    "stop")
        check_install 0 && stop 0
        ;;
    "restart")
        check_install 0 && restart 0
        ;;
    "status")
        check_install 0 && status 0
        ;;
    "settings")
        check_install 0 && check_config 0
        ;;
    "enable")
        check_install 0 && enable 0
        ;;
    "disable")
        check_install 0 && disable 0
        ;;
    "log")
        check_install 0 && show_log 0
        ;;
    "banlog")
        check_install 0 && show_banlog 0
        ;;
    "update")
        check_install 0 && update 0
        ;;
    "legacy")
        check_install 0 && legacy_version 0
        ;;
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    "update-all-geofiles")
        check_install 0 && update_all_geofiles 0 && restart 0
        ;;
    "nginx-install")
        install_nginx_reverse_proxy 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi

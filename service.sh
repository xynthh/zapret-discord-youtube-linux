#!/bin/bash

# Константы
SERVICE_NAME="zapret_discord_youtube"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
HOME_DIR_PATH="$(dirname "$0")"
MAIN_SCRIPT_PATH="$(dirname "$0")/main_script.sh"  # Путь к основному скрипту
CONF_FILE="$(dirname "$0")/conf.env"  # Путь к файлу конфигурации
STOP_SCRIPT="$(dirname "$0")/stop_and_clean_nft.sh"  # Путь к скрипту остановки и очистки nftables

# Функция для проверки существования conf.env и необходимых полей
check_conf_file() {
    if [[ ! -f "$CONF_FILE" ]]; then
        echo "Ошибка: Файл конфигурации conf.env не найден."
        return 1
    fi

    # Проверяем наличие необходимых полей
    local required_fields=("interface" "auto_update" "strategy")
    for field in "${required_fields[@]}"; do
        if ! grep -q "^${field}=" "$CONF_FILE"; then
            echo "Ошибка: Поле ${field} отсутствует в conf.env."
            return 1
        fi
    done
    return 0
}

# Функция для проверки статуса процесса nfqws
check_nfqws_status() {
    if pgrep -f "nfqws" >/dev/null; then
        echo "Демоны nfqws запущены."
    else
        echo "Демоны nfqws не запущены."
    fi
}

# Функция для проверки статуса сервиса
check_service_status() {
    if ! systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
        echo "Статус: Сервис не установлен."
        return 1
    fi

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "Статус: Сервис установлен и активен."
        return 2
    else
        echo "Статус: Сервис установлен, но не активен."
        return 3
    fi
}

# Функция для установки сервиса
install_service() {
    # Проверяем файл конфигурации
    if ! check_conf_file; then
        echo "Установка прервана из-за ошибки в conf.env."
        return
    fi

    # Получение абсолютного пути к основному и скрипту остановки
    local absolute_homedir_path="$(realpath "$HOME_DIR_PATH")"
    local absolute_main_script_path="$(realpath "$MAIN_SCRIPT_PATH")"
    local absolute_stop_script_path="$(realpath "$STOP_SCRIPT")"

    echo "Создание systemd сервиса для автозагрузки..."
    sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Custom Script Service
After=network.target

[Service]
Type=simple
WorkingDirectory=
ExecStart=sudo /bin/bash $absolute_main_script_path -nointeractive >> /var/log/$SERVICE_NAME.log 2>&1
ExecStop=sudo /bin/bash $absolute_stop_script_path
ExecStopPost=/bin/echo "Сервис завершён"
PIDFile=/run/$SERVICE_NAME.pid

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
    sudo systemctl start "$SERVICE_NAME"
    echo "Сервис успешно установлен и запущен."
}

# Функция для удаления сервиса
remove_service() {
    echo "Удаление сервиса..."
    sudo systemctl stop "$SERVICE_NAME"
    sudo systemctl disable "$SERVICE_NAME"
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload
    echo "Сервис удален."
}

# Функция для запуска сервиса
start_service() {
    echo "Запуск сервиса..."
    sudo systemctl start "$SERVICE_NAME"
    echo "Сервис запущен."
    sleep 5
    check_nfqws_status
}

# Функция для остановки сервиса
stop_service() {
    echo "Остановка сервиса..."
    sudo systemctl stop "$SERVICE_NAME"
    echo "Сервис остановлен."
    # Вызов скрипта для остановки и очистки nftables
    $STOP_SCRIPT
}

# Основное меню управления
show_menu() {
    check_service_status
    local status=$?

    case $status in
        1)
            echo "1. Установить и запустить сервис"
            read -p "Выберите действие: " choice
            if [ "$choice" -eq 1 ]; then
                install_service
            fi
            ;;
        2)
            echo "1. Удалить сервис"
            echo "2. Остановить сервис"
            read -p "Выберите действие: " choice
            case $choice in
                1) remove_service ;;
                2) stop_service ;;
            esac
            ;;
        3)
            echo "1. Удалить сервис"
            echo "2. Запустить сервис"
            read -p "Выберите действие: " choice
            case $choice in
                1) remove_service ;;
                2) start_service ;;
            esac
            ;;
        *)
            echo "Неправильный выбор."
            ;;
    esac
}

# Запуск меню
show_menu

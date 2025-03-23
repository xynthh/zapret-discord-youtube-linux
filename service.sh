#!/usr/bin/env bash

# Подключаем общие функции
source "$(dirname "$0")/common.sh"

# Константы
SERVICE_NAME="zapret_discord_youtube"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
HOME_DIR_PATH="$(dirname "$0")"
MAIN_SCRIPT_PATH="$HOME_DIR_PATH/main_script.sh"
CONF_FILE="$HOME_DIR_PATH/conf.env"
STOP_SCRIPT="$HOME_DIR_PATH/stop_and_clean_nft.sh"
REPO_DIR="$HOME_DIR_PATH/zapret-latest"

# Проверка прав суперпользователя
check_root

# Функция проверки существования и полноты конфигурационного файла
check_conf_file() {
    if [ ! -f "$CONF_FILE" ]; then
        return 1
    fi
    source "$CONF_FILE"
    if [ -z "$interface" ] || [ -z "$auto_update" ] || [ -z "$strategy" ]; then
        return 1
    fi
    if ! ip link show "$interface" &>/dev/null; then
        log "Предупреждение: Интерфейс '$interface' не существует."
        return 1
    fi
    if [ ! -f "$REPO_DIR/$strategy" ]; then
        log "Предупреждение: Файл стратегии '$strategy' не найден в '$REPO_DIR'."
        return 1
    fi
    return 0
}

# Функция создания или обновления конфигурационного файла
create_conf_file() {
    log "Создание/обновление файла конфигурации '$CONF_FILE'..."
    local interfaces=($(ls /sys/class/net))
    if [ ${#interfaces[@]} -eq 0 ]; then
        handle_error "Не найдены сетевые интерфейсы."
    fi
    echo "Доступные интерфейсы:"
    for i in "${!interfaces[@]}"; do
        echo "  $((i+1))) ${interfaces[i]}"
    done
    read -p "Выберите номер интерфейса: " iface_choice
    if ! [[ "$iface_choice" =~ ^[0-9]+$ ]] || [ "$iface_choice" -lt 1 ] || [ "$iface_choice" -gt "${#interfaces[@]}" ]; then
        handle_error "Неверный выбор интерфейса."
    fi
    local chosen_interface="${interfaces[$((iface_choice-1))]}"
    
    read -p "Включить автообновление? (true/false) [false]: " auto_update_choice
    [ "$auto_update_choice" != "true" ] && auto_update_choice="false"
    
    local strategy_choice=""
    if [ -d "$REPO_DIR" ]; then
        local bat_files=($(find "$REPO_DIR" -maxdepth 1 -type f -name "*general*.bat" -o -name "*discord*.bat"))
        if [ ${#bat_files[@]} -gt 0 ]; then
            echo "Доступные стратегии:"
            for i in "${!bat_files[@]}"; do
                echo "  $((i+1))) $(basename "${bat_files[i]}")"
            done
            read -p "Выберите номер стратегии: " bat_choice
            if [[ "$bat_choice" =~ ^[0-9]+$ ]] && [ "$bat_choice" -ge 1 ] && [ "$bat_choice" -le "${#bat_files[@]}" ]; then
                strategy_choice="$(basename "${bat_files[$((bat_choice-1))]}")"
            else
                handle_error "Неверный выбор стратегии."
            fi
        fi
    fi
    if [ -z "$strategy_choice" ]; then
        read -p "Введите имя файла стратегии вручную: " strategy_choice
        if [ ! -f "$REPO_DIR/$strategy_choice" ]; then
            handle_error "Файл стратегии '$strategy_choice' не найден в '$REPO_DIR'."
        fi
    fi
    
    # Запись конфигурации в файл
    echo "interface=$chosen_interface" > "$CONF_FILE"
    echo "auto_update=$auto_update_choice" >> "$CONF_FILE"
    echo "strategy=$strategy_choice" >> "$CONF_FILE"
    log "Конфигурация сохранена в '$CONF_FILE'."
}

# Функция проверки статуса nfqws
check_nfqws_status() {
    if pgrep -f "nfqws" >/dev/null; then
        log "Процессы nfqws запущены."
    else
        log "Процессы nfqws не запущены."
    fi
}

# Функция проверки статуса сервиса
check_service_status() {
    if ! systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
        log "Статус: Сервис не установлен."
        return 1
        elif systemctl is-active --quiet "$SERVICE_NAME"; then
        log "Статус: Сервис установлен и активен."
        return 2
    else
        log "Статус: Сервис установлен, но не активен."
        return 3
    fi
}

# Функция установки сервиса
install_service() {
    if ! check_conf_file; then
        read -p "Конфигурация отсутствует или неполна. Создать сейчас? (y/n): " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            create_conf_file
        else
            log "Установка отменена."
            return
        fi
        if ! check_conf_file; then
            handle_error "Конфигурация всё ещё некорректна. Установка отменена."
        fi
    fi
    local absolute_homedir_path="$(realpath "$HOME_DIR_PATH")"
    local absolute_main_script_path="$(realpath "$MAIN_SCRIPT_PATH")"
    local absolute_stop_script_path="$(realpath "$STOP_SCRIPT")"
    log "Создание systemd-сервиса..."
    sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Zapret Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$absolute_homedir_path
User=root
ExecStart=/usr/bin/env bash $absolute_main_script_path -nointeractive
ExecStop=/usr/bin/env bash $absolute_stop_script_path
ExecStopPost=/usr/bin/env echo "Сервис завершён"
PIDFile=/run/$SERVICE_NAME.pid

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload || handle_error "Не удалось обновить конфигурацию systemd."
    sudo systemctl enable "$SERVICE_NAME" || handle_error "Не удалось включить сервис."
    sudo systemctl start "$SERVICE_NAME" || handle_error "Не удалось запустить сервис."
    log "Сервис успешно установлен и запущен."
    check_nfqws_status
}

# Функция удаления сервиса
uninstall_service() {
    log "Удаление сервиса..."
    sudo systemctl stop "$SERVICE_NAME" || log "Сервис уже остановлен или не существует."
    sudo systemctl disable "$SERVICE_NAME" || log "Сервис уже отключен или не существует."
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload || log "Не удалось обновить конфигурацию systemd."
    log "Сервис удален."
}

# Функция запуска сервиса
start_service() {
    log "Запуск сервиса..."
    sudo systemctl start "$SERVICE_NAME" || handle_error "Не удалось запустить сервис."
    log "Сервис запущен."
    sleep 2
    check_nfqws_status
}

# Функция остановки сервиса
stop_service() {
    log "Остановка сервиса..."
    sudo systemctl stop "$SERVICE_NAME" || log "Сервис уже остановлен."
    log "Сервис остановлен."
    check_nfqws_status
}

# Функция перезапуска сервиса
restart_service() {
    log "Перезапуск сервиса..."
    sudo systemctl restart "$SERVICE_NAME" || handle_error "Не удалось перезапустить сервис."
    log "Сервис перезапущен."
    sleep 2
    check_nfqws_status
}

# Основное меню управления с динамическим отображением опций
show_menu() {
    check_service_status
    local status=$?
    local options=()
    local actions=()
    
    case $status in
        1) # Сервис не установлен
            options+=("1) Установить и запустить сервис")
            options+=("2) Создать/пересоздать конфигурацию")
            options+=("3) Выйти")
            actions=("install_service" "create_conf_file" "exit 0")
        ;;
        2) # Сервис установлен и активен
            options+=("1) Остановить сервис")
            options+=("2) Перезапустить сервис")
            options+=("3) Удалить сервис")
            options+=("4) Создать/пересоздать конфигурацию")
            options+=("5) Выйти")
            actions=("stop_service" "restart_service" "uninstall_service" "create_conf_file" "exit 0")
        ;;
        3) # Сервис установлен, но не активен
            options+=("1) Запустить сервис")
            options+=("2) Удалить сервис")
            options+=("3) Создать/пересоздать конфигурацию")
            options+=("4) Выйти")
            actions=("start_service" "uninstall_service" "create_conf_file" "exit 0")
        ;;
    esac
    
    # Вывод доступных опций
    for opt in "${options[@]}"; do
        echo "$opt"
    done
    
    # Чтение выбора пользователя
    read -p "Выберите действие: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#actions[@]}" ]; then
        eval "${actions[$((choice-1))]}"
    else
        log "Неверный выбор."
    fi
}

# Запуск меню
show_menu
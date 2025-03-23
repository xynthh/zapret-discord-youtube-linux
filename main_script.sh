#!/usr/bin/env bash

# Подключаем общие функции
source "$(dirname "$0")/common.sh"

# Константы
BASE_DIR="$(realpath "$(dirname "$0")")"
REPO_DIR="$BASE_DIR/zapret-latest"
REPO_URL="https://github.com/Flowseal/zapret-discord-youtube"
NFQWS_PATH="$BASE_DIR/nfqws"
CONF_FILE="$BASE_DIR/conf.env"
STOP_SCRIPT="$BASE_DIR/stop_and_clean_nft.sh"

# Флаги
DEBUG=false
NOINTERACTIVE=false

# Проверка прав суперпользователя
check_root

# Функция для остановки и очистки при получении SIGINT
_term() {
    log "Получен сигнал завершения. Выполняется очистка..."
    sudo /usr/bin/env bash "$STOP_SCRIPT"
    exit 0
}

# Проверка зависимостей (git, nft, sed, grep)
check_dependencies() {
    check_utilities git nft sed grep
}

# Загрузка и валидация конфигурации для неинтерактивного режима
load_config() {
    if [ ! -f "$CONF_FILE" ]; then
        handle_error "Файл конфигурации '$CONF_FILE' не найден."
    fi
    source "$CONF_FILE"
    if [ -z "$interface" ] || [ -z "$auto_update" ] || [ -z "$strategy" ]; then
        handle_error "Отсутствуют обязательные параметры в конфигурационном файле."
    fi
    if ! ip link show "$interface" &>/dev/null; then
        handle_error "Интерфейс '$interface' не существует."
    fi
    if [ ! -f "$REPO_DIR/$strategy" ]; then
        handle_error "Файл стратегии '$strategy' не найден в '$REPO_DIR'."
    fi
}

# Настройка репозитория
setup_repository() {
    if [ -d "$REPO_DIR" ]; then
        if $NOINTERACTIVE && [ "$auto_update" != "true" ]; then
            log "Использование существующей версии репозитория."
            return
        fi
        if $NOINTERACTIVE && [ "$auto_update" == "true" ]; then
            log "Обновление репозитория (автообновление включено)..."
            rm -rf "$REPO_DIR"
        else
            read -p "Репозиторий уже существует. Обновить его? (y/n): " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                log "Обновление репозитория..."
                rm -rf "$REPO_DIR"
            else
                log "Использование существующей версии репозитория."
                return
            fi
        fi
    fi
    log "Клонирование репозитория..."
    git clone "$REPO_URL" "$REPO_DIR" || handle_error "Не удалось клонировать репозиторий."
    rm -rf "$REPO_DIR/.git"
    chmod +x "$BASE_DIR/rename_bat.sh"
    "$BASE_DIR/rename_bat.sh" || handle_error "Не удалось переименовать файлы."
}

# Поиск .bat-файлов в репозитории
find_bat_files() {
    find "$REPO_DIR" -type f -name "general*.bat" -print0
    find "$REPO_DIR" -type f -name "discord*.bat" -print0
}

# Выбор стратегии (интерактивный или неинтерактивный режим)
select_strategy() {
    cd "$REPO_DIR" || handle_error "Не удалось перейти в '$REPO_DIR'."
    if $NOINTERACTIVE; then
        parse_bat_file "$strategy"
        cd ..
        return
    fi
    local bat_files=()
    while IFS= read -r -d '' file; do
        bat_files+=("$(basename "$file")")
    done < <(find_bat_files)
    if [ ${#bat_files[@]} -eq 0 ]; then
        cd ..
        handle_error "Не найдены подходящие .bat-файлы в '$REPO_DIR'."
    fi
    log "Доступные стратегии:"
    for i in "${!bat_files[@]}"; do
        echo "  $((i+1))) ${bat_files[i]}"
    done
    read -p "Выберите номер стратегии: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#bat_files[@]}" ]; then
        strategy="${bat_files[$((choice-1))]}"
        log "Выбрана стратегия: $strategy"
        parse_bat_file "$strategy"
        cd ..
    else
        handle_error "Неверный выбор стратегии."
    fi
}

# Парсинг .bat-файла для извлечения правил и параметров
parse_bat_file() {
    local file="$1"
    local queue_num=0
    local bin_path="bin/"
    debug_log "Парсинг файла: $file"
    nft_rules=()
    nfqws_params=()
    while IFS= read -r line; do
        debug_log "Обработка строки: $line"
        [[ "$line" =~ ^[:space:]*:: || -z "$line" ]] && continue
        if [[ "$line" =~ ^set[[:space:]]+BIN=%~dp0bin\\ ]]; then
            debug_log "Обнаружена установка BIN. Замена %BIN% на $bin_path."
            continue
        fi
        line="${line//%BIN%/$bin_path}"
        if [[ "$line" =~ --filter-(tcp|udp)=([0-9,-]+)[[:space:]](.*?)(--new|$) ]]; then
            local protocol="${BASH_REMATCH[1]}"
            local ports="${BASH_REMATCH[2]}"
            local nfqws_args="${BASH_REMATCH[3]}"
            nft_rules+=("$protocol dport {$ports} counter queue num $queue_num bypass")
            # Очищаем аргументы от символа ^
            nfqws_args="${nfqws_args//^/}"
            nfqws_params+=("$nfqws_args")
            debug_log "Протокол: $protocol, порты: $ports, очередь: $queue_num"
            debug_log "Параметры nfqws: $nfqws_args"
            ((queue_num++))
        fi
    done < <(grep -v "^@echo" "$file" | grep -v "^chcp" | tr -d '\r')
}

# Проверка наличия файлов в параметрах nfqws
check_nfqws_files() {
    local params="$1"
    local file_patterns=(--hostlist= --dpi-desync-fake-quic= --dpi-desync-fake-tls=)
    for pattern in "${file_patterns[@]}"; do
        if [[ "$params" =~ $pattern\"([^\"]+)\" ]]; then
            local file="${BASH_REMATCH[1]}"
            if [ ! -f "$REPO_DIR/$file" ]; then
                handle_error "Файл '$file', указанный в параметрах nfqws, не найден в '$REPO_DIR'."
            fi
        fi
    done
}

# Настройка nftables
setup_nftables() {
    local interface="$1"
    local table_name="inet zapretunix"
    local chain_name="output"
    local rule_comment="Added by zapret script"
    log "Настройка nftables..."
    if sudo nft list tables | grep -q "$table_name"; then
        sudo nft flush chain $table_name $chain_name
        sudo nft delete chain $table_name $chain_name
        sudo nft delete table $table_name
    fi
    sudo nft add table $table_name
    sudo nft add chain $table_name $chain_name { type filter hook output priority 0\; }
    for rule in "${nft_rules[@]}"; do
        sudo nft add rule $table_name $chain_name oifname \"$interface\" $rule comment \"$rule_comment\" ||
            handle_error "Не удалось добавить правило nftables: $rule"
    done
}

# Запуск nfqws
start_nfqws() {
    log "Запуск nfqws..."
    sudo pkill -f nfqws
    cd "$REPO_DIR" || handle_error "Не удалось перейти в директорию $REPO_DIR"
    for queue_num in "${!nfqws_params[@]}"; do
        debug_log "Запуск nfqws с параметрами: $NFQWS_PATH --daemon --qnum=$queue_num ${nfqws_params[$queue_num]}"
        eval "sudo $NFQWS_PATH --daemon --qnum=$queue_num ${nfqws_params[$queue_num]}" ||
        handle_error "Ошибка при запуске nfqws для очереди $queue_num"
    done
}

# Основная функция
main() {
    if [[ "$1" == "-debug" ]]; then
        DEBUG=true
        shift
    elif [[ "$1" == "-nointeractive" ]]; then
        NOINTERACTIVE=true
        shift
        load_config
    fi
    check_dependencies
    setup_repository
    if $NOINTERACTIVE; then
        select_strategy
        setup_nftables "$interface"
    else
        select_strategy
        local interfaces=($(ls /sys/class/net))
        if [ ${#interfaces[@]} -eq 0 ]; then
            handle_error "Не найдены сетевые интерфейсы."
        fi
        echo "Доступные сетевые интерфейсы:"
        select interface in "${interfaces[@]}"; do
            if [ -n "$interface" ] && ip link show "$interface" &>/dev/null; then
                log "Выбран интерфейс: $interface"
                setup_nftables "$interface"
                break
            fi
            echo "Неверный выбор. Попробуйте еще раз."
        done
    fi
    start_nfqws
    log "Настройка успешно завершена."
}

# Запуск программы с обработкой SIGINT
main "$@"
trap _term SIGINT
sleep infinity &
wait
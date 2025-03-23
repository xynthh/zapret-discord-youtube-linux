#!/usr/bin/env bash

# Функция для логирования сообщений с временной меткой
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Функция для отладочного логирования (работает, если DEBUG=true)
debug_log() {
    if [ "$DEBUG" = "true" ]; then
        echo "[DEBUG] $1"
    fi
}

# Функция для обработки ошибок с выводом сообщения и завершением скрипта
handle_error() {
    log "Ошибка: $1"
    exit 1
}

# Функция для проверки прав суперпользователя
check_root() {
    if [ "$EUID" -ne 0 ]; then
        handle_error "Скрипт должен быть запущен с правами суперпользователя (sudo)."
    fi
}

# Функция для проверки наличия необходимых утилит
check_utilities() {
    local utils=("$@")
    for util in "${utils[@]}"; do
        if ! command -v "$util" &>/dev/null; then
            handle_error "Утилита '$util' не установлена."
        fi
    done
}
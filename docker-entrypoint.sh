#!/bin/bash -e
# Этот скрипт настраивает пользователя при запуске контейнера.
# Если контейнер запущен от root (UID=0), то просто устанавливается пароль для root.
# Если запущен от обычного пользователя, то создаётся пользователь с заданным UID/GID,
# а затем ему назначается пароль.

# Если переменные USER и PASSWD не заданы, используются значения из DEFAULT_USER и DEFAULT_PASSWD.
# Для запуска в режиме root можно задать:
#   ENV DEFAULT_USER=root
#   ENV DEFAULT_PASSWD=your_root_password
USER=${USER:-${DEFAULT_USER:-root}}
PASSWD=${PASSWD:-${DEFAULT_PASSWD:-your_root_password}}

# Получаем UID и GID текущего процесса
USER_ID=$(id -u)
GROUP_ID=$(id -g)

# Если переменные DEFAULT_* установлены, удаляем их
unset DEFAULT_USER DEFAULT_PASSWD

# Если контейнер запущен не от root, создаём группу и пользователя
if [[ "$USER_ID" != "0" ]]; then
    # Добавляем группу, если её ещё нет
    if ! getent group "$USER" > /dev/null; then
        groupadd -g "$GROUP_ID" "$USER"
    fi
    # Добавляем пользователя, если он ещё не существует
    if ! getent passwd "$USER" > /dev/null; then
        export HOME=/home/$USER
        useradd -d "$HOME" -m -s /bin/bash -u "$USER_ID" -g "$GROUP_ID" "$USER"
    fi
else
    # Если мы root, задаём домашнюю директорию по умолчанию
    export HOME=/root
fi

# Отменяем бит SUID для команд useradd и groupadd, если они были изменены ранее
sudo chmod u-s /usr/sbin/useradd
sudo chmod u-s /usr/sbin/groupadd

# Если скрипту не переданы параметры – выполняем настройку по умолчанию
if (( $# == 0 )); then
    # Определяем имя пользователя (для root будет "root")
    USER=$(whoami)
    echo "USER: $USER"

    # Устанавливаем пароль для указанного пользователя
    echo "PASSWD: $PASSWD"
    echo "${USER}:${PASSWD}" | sudo chpasswd

    # Если отсутствует файл .xsession в домашней директории, копируем его из /etc/skel
    [[ ! -e ${HOME}/.xsession ]] && cp /etc/skel/.xsession ${HOME}/.xsession
    # Генерируем ключи для xrdp, если их ещё нет
    [[ ! -e /etc/xrdp/rsakeys.ini ]] && sudo -u xrdp -g xrdp xrdp-keygen xrdp /etc/xrdp/rsakeys.ini > /dev/null 2>&1

    # Настраиваем runtime-директорию для пользователя
    RUNTIME_DIR=/run/user/${USER_ID}
    [ -e "$RUNTIME_DIR" ] && sudo rm -rf "$RUNTIME_DIR"
    sudo install -o "$USER_ID" -g "$GROUP_ID" -m 0700 -d "$RUNTIME_DIR"

    # Формируем команду для запуска supervisord с нужным конфигом
    set -- /usr/bin/supervisord -c /etc/supervisor/xrdp.conf
    # Если пользователь не root, используем альтернативную команду для переключения на root
    if [[ "$USER_ID" != "0" ]]; then
        if [[ ! -e /usr/local/bin/_alt-su ]]; then
            sudo install -g "$GROUP_ID" -m 4750 $(which gosu || which su-exec) /usr/local/bin/_alt-su
        fi
        set -- /usr/local/bin/_alt-su root "$@"
    fi
fi

unset PASSWD

echo "#############################"
exec "$@"

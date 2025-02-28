#!/bin/bash -e

# Получаем ID текущего пользователя и группы
USER_ID=$(id -u)
GROUP_ID=$(id -g)

# Устанавливаем значения по умолчанию, если переменные не заданы
USER=${USER:-${DEFAULT_USER}}
GROUP=${GROUP:-${USER}}
PASSWD=${PASSWD:-${DEFAULT_PASSWD}}

# Убираем переменные с дефолтными значениями
unset DEFAULT_USER DEFAULT_PASSWD

# Добавляем группу, если её ещё нет
echo "GROUP_ID: $GROUP_ID"
if [[ $GROUP_ID != "0" && ! $(getent group $GROUP) ]]; then
    groupadd -g $GROUP_ID $GROUP
fi

# Добавляем пользователя, если его ещё нет
echo "USER_ID: $USER_ID"
if [[ $USER_ID != "0" && ! $(getent passwd $USER) ]]; then
    export HOME=/home/$USER
    useradd -d ${HOME} -m -s /bin/bash -u $USER_ID -g $GROUP_ID $USER
fi

# Возвращаем стандартные права для команд useradd и groupadd
sudo chmod u-s /usr/sbin/useradd
sudo chmod u-s /usr/sbin/groupadd

# Если скрипт запущен без аргументов
if (( $# == 0 )); then
    # Определяем имя текущего пользователя
    USER=$(whoami)
    echo "USER: $USER"

    # Устанавливаем пароль для пользователя
    echo "PASSWD: $PASSWD"
    echo ${USER}:${PASSWD} | sudo chpasswd

    # Если у пользователя нет файла .xsession, копируем дефолтный
    [[ ! -e ${HOME}/.xsession ]] && \
        cp /etc/skel/.xsession ${HOME}/.xsession

    # Генерируем ключи для xrdp, если их нет
    [[ ! -e /etc/xrdp/rsakeys.ini ]] && \
        sudo -u xrdp -g xrdp xrdp-keygen xrdp /etc/xrdp/rsakeys.ini > /dev/null 2>&1

    # Создаём рабочий каталог для пользователя, если его нет
    RUNTIME_DIR=/run/user/${USER_ID}
    [ -e $RUNTIME_DIR ] && sudo rm -rf $RUNTIME_DIR
    sudo install -o $USER_ID -g $GROUP_ID -m 0700 -d $RUNTIME_DIR

    # Запускаем supervisord, который будет управлять процессами xrdp
    set -- /usr/bin/supervisord -c /etc/supervisor/xrdp.conf

    # Если пользователь не root, используем gosu/su-exec для смены пользователя
    if [[ $USER_ID != "0" ]]; then
        [[ ! -e /usr/local/bin/_alt-su ]] && \
            sudo install -g $GROUP_ID -m 4750 $(which gosu || which su-exec) /usr/local/bin/_alt-su
        set -- /usr/local/bin/_alt-su root "$@"
    fi
fi

# Удаляем пароль из переменной окружения
unset PASSWD

# Выводим разделительную строку
echo "#############################"

# Выполняем переданную команду или запускаем supervisord
exec "$@"

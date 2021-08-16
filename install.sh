#!/bin/bash

#### Update Repositories ####

apt-get -y update
apt-get -y upgrade


#### Variables ####

MYSQL_USER="admin"
MYSQL_PASS="dashboardpass"
GITHUB_SOURCE="master"
GITHUB_BASE_URL="https://raw.githubusercontent.com/Ferks-FK/ControlPanel.gg-Installer/$GITHUB_SOURCE"


#### User data ####

echo
echo "****************************************************"
echo "* Let's create your database username and password *"
echo "****************************************************"
echo
echo -n "* Username (admin): "
read -r MYSQL_USER_INPUT
[ -z "$MYSQL_USER_INPUT" ] && MYSQL_USER="admin" || MYSQL_USER=$MYSQL_USER_INPUT

echo
echo -n "* Password (dashboardpass): "
read -r MYSQL_PASS_INPUT
[ -z "$MYSQL_PASS_INPUT" ] && MYSQL_PASS="dashboardpass" || MYSQL_PASS=$MYSQL_PASS_INPUT
echo
echo

#### Review of settings ####

summary() {
echo "******************************"
echo "* Username: $MYSQL_USER"
echo "* Password: $MYSQL_PASS"
echo "******************************"
}

#### Exec summary ####
summary


#### Detect existing installation ####

continue_install() {
DEI=/var/www/dashboard

if [ -d "$DEI" ]; then
echo
echo "*******************************************************************"
echo "* There is already a panel installation on your system, aborting! *"
echo "*******************************************************************"
exit 1
else
echo
echo "**********************************************************************"
echo "* No existing installation detected, proceeding with installation... *"
echo "**********************************************************************"
echo
#### Install Dependencies ####
install_dependencies() {
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
add-apt-repository -y ppa:chris-lea/redis-server
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
apt-get -y update && apt-get -y upgrade
apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
apt-get install php8.0-intl
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
}
fi
}


#### Exec Installation ####

echo -e -n "\n* Initial configuration completed. Continue with installation? (y/N): "
read -r CONFIRM
if [[ "$CONFIRM" =~ [Yy] ]]; then
    #### Continue Install ####
    continue_install
  else
    echo "Installation aborted!"
    exit 1
fi

#### Exec Install_Dependencies ####
install_dependencies

#### Download Files ####

download_files() {
mkdir -p /var/www/dashboard
cd /var/www/dashboard || exit
git clone https://github.com/ControlPanel-gg/dashboard.git ./
chmod -R 755 storage/* bootstrap/cache/
}

#### Exec Download_Files ####
download_files

#### Installation ####

installation() {
rm -R .env.example
curl -o example.env $GITHUB_BASE_URL/configs/example.env
cp example.env .env
rm -R example.env
composer install --no-dev --optimize-autoloader
php artisan storage:link
}

#### Exec Installation ####
installation

#### Database ####

setup_database() {
echo "* Creating user..."
mysql -u root -e "CREATE USER '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASS}';"

echo "* Creating database..."
mysql -u root -e "CREATE DATABASE dashboard;"

echo "* Grant privileges..."
mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER}'@'127.0.0.1' WITH GRANT OPTION;"

echo "* Flush privileges..."
mysql -u root -e "FLUSH PRIVILEGES;"

#### Restart MySQL Service ####

echo "* Restarting MySQL..."
systemctl restart mysql

echo "* MySQL user created and configured successfully!"
echo
echo "**************************************************"
}

#### Exec Database Setup ####
setup_database

#### Run command after database creation ####
php artisan key:generate --force
#### Other general commands ####
cd || exit
sed -i -e "s@dashboarduser@${MYSQL_USER}@g" /var/www/dashboard/.env
sed -i -e "s@mysecretpassword@${MYSQL_PASS}@g" /var/www/dashboard/.env
cd /var/www/dashboard || exit
php artisan migrate --seed --force
php artisan db:seed --class=ExampleItemsSeeder --force
#### Set Permissions ####
cd || exit
chown -R www-data:www-data /var/www/dashboard/*
#### Create Queue Worker ####
cd /etc/systemd/system || exit
curl -o /etc/systemd/system/dashboard.service $GITHUB_BASE_URL/configs/dashboard.service
systemctl enable dashboard.service
systemctl start dashboard.service

#### Config Cronjob ####

insert_cronjob() {
  echo "* Installing cronjob.. "

  crontab -l | {
    cat
    echo "* * * * * php /var/www/dashboard/artisan schedule:run >> /dev/null 2>&1"
  } | crontab -

  echo "* Cronjob installed!"
}

#### Exec Cronjob ####
insert_cronjob

#### Enable All Services ####

systemctl enable nginx
systemctl enable mariadb
systemctl enable redis
systemctl enable php-fpm

#### Start All Services ####

systemctl start nginx
systemctl start mariadb
systemctl start redis
systemctl start php-fpm


#!/bin/bash
# shellcheck source=/dev/null

set -e

########################################################
# 
#         Pterodactyl-AutoThemes Installation
#
#         Created and maintained by Ferks-FK
#
#            Protected by MIT License
#
########################################################

# Get the latest version before running the script #
get_release() {
curl --silent \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/Ferks-FK/ControlPanel.gg-Installer/releases/latest |
  grep '"tag_name":' |
  sed -E 's/.*"([^"]+)".*/\1/'
}

# Variables #
SCRIPT_RELEASE="$(get_release)"
GITHUB_URL="https://raw.githubusercontent.com/Ferks-FK/ControlPanel.gg-Installer/$SCRIPT_RELEASE"
CONFIGURE_SSL=false
SETUP_MYSQL_MANUALLY=false

# Visual Functions #
print_brake() {
  for ((n = 0; n < $1; n++)); do
    echo -n "#"
  done
  echo ""
}

print_warning() {
  echo ""
  echo -e "* ${YELLOW}WARNING${RESET}: $1"
  echo ""
}

print_error() {
  echo ""
  echo -e "* ${RED}ERROR${RESET}: $1"
  echo ""
}

print_hint() {
  echo ""
  echo -e "* ${GREEN}HINT${RESET}: $1"
  echo ""
}

print() {
  echo ""
  echo -e "* ${GREEN}$1${RESET}"
  echo ""
}

hyperlink() {
  echo -e "\e]8;;${1}\a${1}\e]8;;\a"
}

# Colors #
GREEN="\e[0;92m"
YELLOW="\033[1;33m"
RED='\033[0;31m'
RESET="\e[0m"

password_input() {
  local __resultvar=$1
  local result=''
  local default="$4"

  while [ -z "$result" ]; do
    echo -n "* ${2}"
    while IFS= read -r -s -n1 char; do
      [[ -z $char ]] && {
        printf '\n'
        break
      }
      if [[ $char == $'\x7f' ]]; then
        if [ -n "$result" ]; then
          [[ -n $result ]] && result=${result%?}
          printf '\b \b'
        fi
      else
        result+=$char
        printf '*'
      fi
    done
    [ -z "$result" ] && [ -n "$default" ] && result="$default"
    [ -z "$result" ] && print_error "${3}"
  done

  eval "$__resultvar="'$result'""
}

# OS check #
check_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$(echo "$ID" | awk '{print tolower($0)}')
    OS_VER=$VERSION_ID
  elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si | awk '{print tolower($0)}')
    OS_VER=$(lsb_release -sr)
  elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$(echo "$DISTRIB_ID" | awk '{print tolower($0)}')
    OS_VER=$DISTRIB_RELEASE
  elif [ -f /etc/debian_version ]; then
    OS="debian"
    OS_VER=$(cat /etc/debian_version)
  elif [ -f /etc/SuSe-release ]; then
    OS="SuSE"
    OS_VER="?"
  elif [ -f /etc/redhat-release ]; then
    OS="Red Hat/CentOS"
    OS_VER="?"
  else
    OS=$(uname -s)
    OS_VER=$(uname -r)
  fi

  OS=$(echo "$OS" | awk '{print tolower($0)}')
  OS_VER_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
}

enable_services_debian_based() {
systemctl enable mariadb --now
systemctl enable redis-server --now
}

enable_services_centos_based() {
systemctl enable mariadb --now
systemctl enable nginx --now
systemctl enable redis --now
}

allow_selinux() {
setsebool -P httpd_can_network_connect 1 || true
setsebool -P httpd_execmem 1 || true
setsebool -P httpd_unified 1 || true
}

centos_php() {
curl -so /etc/php-fpm.d/www-controlpanel.conf "$GITHUB_URL"/configs/www-controlpanel.conf

systemctl enable php-fpm --now
}

check_compatibility() {
print "Checking if your system is compatible with the script..."
sleep 2

case "$OS" in
    debian)
      PHP_SOCKET="/run/php/php8.0-fpm.sock"
      [ "$OS_VER_MAJOR" == "9" ] && SUPPORTED=true
      [ "$OS_VER_MAJOR" == "10" ] && SUPPORTED=true
      [ "$OS_VER_MAJOR" == "11" ] && SUPPORTED=true
    ;;
    ubuntu)
      PHP_SOCKET="/run/php/php8.0-fpm.sock"
      [ "$OS_VER_MAJOR" == "18" ] && SUPPORTED=true
      [ "$OS_VER_MAJOR" == "20" ] && SUPPORTED=true
    ;;
    centos)
      PHP_SOCKET="/var/run/php-fpm/controlpanel.sock"
      [ "$OS_VER_MAJOR" == "7" ] && SUPPORTED=true
      [ "$OS_VER_MAJOR" == "8" ] && SUPPORTED=true
    ;;
    pop)
      PHP_SOCKET="/run/php/php8.0-fpm.sock"
      [ "$OS_VER_MAJOR" == "20" ] && SUPPORTED=true
    ;;
    *)
        SUPPORTED=false
    ;;
esac

if [ "$SUPPORTED" == true ]; then
    print "$OS $OS_VER is supported!"
  else
    print_error "$OS $OS_VER is not supported!"
    exit 1
fi
}

inicial_deps() {
print "Downloading packages required for FQDN validation..."

case "$OS" in
  debian | ubuntu)
    apt-get update -y && apt-get install -y dnsutils
  ;;
  centos)
    yum update -y && yum install -y bind-utils
  ;;
esac
}

check_fqdn() {
print "Checking FQDN..."
sleep 2
IP="$(curl -s https://ipecho.net/plain ; echo)"
CHECK_DNS="$(dig +short @8.8.8.8 "$FQDN" | tail -n1)"
if [[ "$IP" != "$CHECK_DNS" ]]; then
    print_error "Your FQDN (${YELLOW}$FQDN${RESET}) is not pointing to the public IP (${YELLOW}$IP${RESET}), please make sure your domain is set correctly."
    echo -n "* Would you like to check again? (y/N): "
    read -r CHECK_DNS_AGAIN
    [[ "$CHECK_DNS_AGAIN" =~ [Yy] ]] && check_fqdn
    [[ "$CHECK_DNS_AGAIN" == * ]] && print_error "Installation aborted!" && exit 1
  else
    print_success "DNS successfully verified!"
fi
}

ask_ssl() {
echo -ne "* Would you like to configure ssl for your domain? (y/N): "
read -r CONFIGURE_SSL
if [[ "$CONFIGURE_SSL" == [Yy] ]]; then
  CONFIGURE_SSL=true
fi
}

install_composer() {
print "Installing Composer..."

curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
}

download_files() {
print "Downloading Necessary Files..."

git clone -q https://github.com/ControlPanel-gg/dashboard.git /var/www/controlpanel
rm -rf /var/www/controlpanel/.env.example
curl -so /var/www/controlpanel/.env.example "$GITHUB_URL"/configs/.env.example

cd /var/www/controlpanel
[ "$OS" == "centos" ] && export PATH=/usr/local/bin:$PATH
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
}

set_permissions() {
print "Setting Necessary Permissions..."

case "$OS" in
  debian | ubuntu)
    chown -R www-data:www-data /var/www/controlpanel/
  ;;
  centos)
    chown -R nginx:nginx /var/www/controlpanel/
  ;;
esac

cd /var/www/controlpanel
chmod -R 755 storage/* bootstrap/cache/
}

configure_environment() {
print "Configuring the base file..."

sed -i -e "s@<timezone>@$TIMEZONE@g" /var/www/controlpanel/.env.example
sed -i -e "s@<db_host>@$DB_HOST@g" /var/www/controlpanel/.env.example
sed -i -e "s@<db_port>@$DB_PORT@g" /var/www/controlpanel/.env.example
sed -i -e "s@<db_name>@$DB_NAME@g" /var/www/controlpanel/.env.example
sed -i -e "s@<db_user>@$DB_USER@g" /var/www/controlpanel/.env.example
sed -i -e "s@<db_pass>@$DB_PASS@g" /var/www/controlpanel/.env.example
}

configure_database() {
print "Configuring Database..."

mysql -u root -e "show databases;" &>/dev/null
if mysql -u root -e "show databases;" &>/dev/null; then
    mysql -u root -e "CREATE DATABASE ${DB_NAME};"
    mysql -u root -e "CREATE USER '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${DB_HOST}';"
    mysql -u root -e "FLUSH PRIVILEGES;"
  else
    print_warning "The database could not be configured, because apparently it has a password to access it."
    echo -n "* Does your mysql have a password to be accessed? (y/N): "
    read -r MYSQL_ROOT_PASS
    if [[ "$MYSQL_ROOT_PASS" =~ [Yy] ]]; then
        password_input MYSQL_ROOT_PASS "Enter your mysql password: " "Password cannot by empty!"
        mysql -u root -p"$MYSQL_ROOT_PASS" -e "show databases;" &>/dev/null
        if mysql -u root -p"$MYSQL_ROOT_PASS" -e "show databases;" &>/dev/null; then
            mysql -u root -p"$MYSQL_ROOT_PASS" -e "CREATE DATABASE ${DB_NAME};"
            mysql -u root -p"$MYSQL_ROOT_PASS" -e "CREATE USER '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';"
            mysql -u root -p"$MYSQL_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${DB_HOST}';"
            mysql -u root -p"$MYSQL_ROOT_PASS" -e "FLUSH PRIVILEGES;"
          else
            print_warning "It looks like you got your mysql password wrong, try again..."
            configure_database
        fi
      else
        print_warning "The script was not able to configure your mysql, do this manually once the script has completed the installation."
        SETUP_MYSQL_MANUALLY=true
        sleep 3
    fi
fi
}

configure_webserver() {
print "Configuring Web-Server..."

if [ "$CONFIGURE_SSL" == true ]; then
    WEB_FILE="controlpanel_ssl.conf"
  else
    WEB_FILE="controlpanel.conf"
fi

case "$OS" in
  debian | ubuntu)
    rm -rf /etc/nginx/sites-enabled/default

    curl -so /etc/nginx/sites-available/controlpanel.conf "$GITHUB_URL"/configs/$WEB_FILE

    sed -i -e "s@<domain>@$FQDN@g" /etc/nginx/sites-available/controlpanel.conf

    sed -i -e "s@<php_socket>@$PHP_SOCKET@g" /etc/nginx/sites-available/controlpanel.conf

    [ "$OS" == "debian" ] && [ "$OS_VER_MAJOR" == "9" ] && sed -i -e 's/ TLSv1.3//' /etc/nginx/sites-available/controlpanel.conf

    ln -s /etc/nginx/sites-available/controlpanel.conf /etc/nginx/sites-enabled/controlpanel.conf

    systemctl restart nginx
  ;;
  centos)
    rm -rf /etc/nginx/conf.d/default

    curl -so /etc/nginx/conf.d/controlpanel.conf "$GITHUB_URL"/configs/$WEB_FILE

    sed -i -e "s@<domain>@$FQDN@g" /etc/nginx/conf.d/controlpanel.conf

    sed -i -e "s@<php_socket>@$PHP_SOCKET@g" /etc/nginx/conf.d/controlpanel.conf

    systemctl restart nginx
esac
}

configure_firewall() {
print "Configuring the firewall..."

case "$OS" in
  debian | ubuntu)
    apt-get install -qq -y ufw

    ufw allow ssh >/dev/null
    ufw allow http >/dev/null
    ufw allow https >/dev/null

    ufw --force enable
    ufw --force reload
    ufw status numbered | sed '/v6/d'
  ;;
  centos)
    yum update -y -q

    yum -y -q install firewalld >/dev/null

    systemctl --now enable firewalld >/dev/null

    firewall-cmd --add-service=http --permanent -q
    firewall-cmd --add-service=https --permanent -q
    firewall-cmd --add-service=ssh --permanent -q
    firewall-cmd --reload -q
  ;;
esac
}

configure_ssl() {
print "Configuring SSL..."

FAILED=false

case "$OS" in
  debian | ubuntu)
    apt-get update -y -qq && apt-get upgrade -y
    apt-get install -y -qq certbot && apt-get install -y -qq python3-certbot-nginx
  ;;
  centos)
    [ "$OS_VER_MAJOR" == "7" ] && yum -y -q install certbot python-certbot-nginx
    [ "$OS_VER_MAJOR" == "8" ] && yum -y -q install certbot python3-certbot-nginx
  ;;
esac

certbot certonly --nginx -d "$FQDN" || FAILED=true

if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == true ]; then
    print_warning "The script failed to generate the SSL certificate automatically, trying alternate command..."
    FAILED=false
    sleep 2
    [ "$(systemctl is-active --quiet nginx)" == "active" ] && systemctl stop nginx
    
    certbot certonly --standalone -d "$FQDN" || FAILED=true

    if [ -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == false ]; then
        print "The script was able to successfully generate the SSL certificate!"
      else
        print_warning "The script failed to generate the certificate, try to do it manually."
    fi
fi
[ "$(systemctl is-active --quiet nginx)" == "inactive" ] && systemctl start nginx
}

configure_crontab() {
print "Configuring Crontab"

crontab -l | {
  cat
  echo "* * * * * php /var/www/controlpanel/artisan schedule:run >> /dev/null 2>&1"
} | crontab -
}

configure_service() {
print "Configuring ControlPanel Service..."

curl -so /etc/systemd/system/controlpanel.service "$GITHUB_URL"/configs/controlpanel.service

case "$OS" in
  debian | ubuntu)
    sed -i -e "s@<user>@www-data@g" /etc/systemd/system/controlpanel.service
  ;;
  centos)
    sed -i -e "s@<user>@nginx@g" /etc/systemd/system/controlpanel.service
  ;;
esac

systemctl enable controlpanel.service --now
}

deps_ubuntu() {
print "Installing dependencies for Ubuntu ${OS_VER}"

# Add "add-apt-repository" command
apt-get install -y software-properties-common curl apt-transport-https ca-certificates gnupg

# Add additional repositories for PHP, Redis, and MariaDB
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
add-apt-repository -y ppa:chris-lea/redis-server
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

# Update repositories list
apt-get update -y && apt-get upgrade -y

# Add universe repository if you are on Ubuntu 18.04
[ "$OS_VER_MAJOR" == "18" ] && apt-add-repository universe

# Install Dependencies
apt-get install -y php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip,intl} mariadb-server nginx tar unzip git redis-server

# Enable services
enable_services_debian_based
}

deps_debian() {
print "Installing dependencies for Debian ${OS_VER}"

# MariaDB need dirmngr
apt-get install -y dirmngr

# install PHP 8.0 using sury's repo
apt-get install -y ca-certificates apt-transport-https lsb-release
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list

# Add the MariaDB repo
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash

# Update repositories list
apt-get update -y && apt-get upgrade -y

# Install Dependencies
apt-get install -y php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip,intl} mariadb-server nginx tar unzip git redis-server

# Enable services
enable_services_debian_based
}

deps_centos() {
print "Installing dependencies for CentOS ${OS_VER}"

if [ "$OS_VER_MAJOR" == "7" ]; then
    # SELinux tools
    yum install -y policycoreutils policycoreutils-python selinux-policy selinux-policy-targeted libselinux-utils setroubleshoot-server setools setools-console mcstrans
    
    # Install MariaDB
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash

    # Add remi repo (php8.0)
    yum install -y epel-release http://rpms.remirepo.net/enterprise/remi-release-7.rpm
    yum install -y yum-utils
    yum-config-manager -y --disable remi-php54
    yum-config-manager -y --enable remi-php80

    # Install dependencies
    yum -y install php php-common php-tokenizer php-curl php-fpm php-cli php-json php-mysqlnd php-mcrypt php-gd php-mbstring php-pdo php-zip php-bcmath php-dom php-opcache php-intl mariadb-server nginx curl tar zip unzip git redis
    yum update -y
  elif [ "$OS_VER_MAJOR" == "8" ]; then
    # SELinux tools
    yum install -y policycoreutils selinux-policy selinux-policy-targeted setroubleshoot-server setools setools-console mcstrans
    
    # Add remi repo (php8.0)
    yum install -y epel-release http://rpms.remirepo.net/enterprise/remi-release-8.rpm
    yum module enable -y php:remi-8.0

    # Install MariaDB
    yum install -y mariadb mariadb-server

    # Install dependencies
    yum install -y php php-common php-fpm php-cli php-json php-mysqlnd php-gd php-mbstring php-pdo php-zip php-bcmath php-dom php-opcache php-intl
    yum update -y
fi

# Enable services
enable_services_centos_based

# SELinux
allow_selinux
}

install_controlpanel() {
print "Starting installation, this may take a few minutes, please wait."
sleep 2

case "$OS" in
  debian | ubuntu)
    apt-get update -y && apt-get upgrade -y

    [ "$OS" == "ubuntu" ] && deps_ubuntu
    [ "$OS" == "debian" ] && deps_debian
  ;;
  centos)
    yum update -y && yum upgrade -y
    deps_centos
  ;;
esac

[ "$OS" == "centos" ] && centos_php
install_composer
download_files
set_permissions
configure_environment
configure_database
configure_webserver
configure_firewall
[ "$CONFIGURE_SSL" == true ] && configure_ssl
configure_crontab
configure_service
}

main() {
# Check if is already installed #
if [ -d "/var/www/controlpanel" ]; then
  print_warning "You have already installed this panel, aborting..."
  exit 1
fi

# Check if pterodactyl is installed #
if [ ! -d "/var/www/pterodactyl" ]; then
  print_warning "An installation of pterodactyl was not found in the directory $YELLOW/var/www/pterodactyl${RESET}"
  echo -e "* ${GREEN}EXAMPLE${RESET}: /var/www/myptero"
  echo -ne "* Manually enter the directory where your pterodactyl is installed: "
  read -r PTERO_DIR
  if [ -f "$PTERO_DIR/config/app.php" ]; then
      print "Pterodactyl was found, continuing..."
    else
      print_error "Pterodactyl not found, running script again..."
      main
  fi
fi

# Check Distro #
check_distro

# Check if the OS is compatible #
check_compatibility

# Set FQDN for panel #
FQDN=""
while [ -z "$FQDN" ]; do
  echo -ne "* Set the Hostname/FQDN for panel (${YELLOW}panel.example.com${RESET}): "
  read -r FQDN
  [ -z "$FQDN" ] && print_error "FQDN cannot be empty"
done

# Install the packages to check FQDN and ask about SSL only if FQDN is a string #
if [[ "$FQDN" == [a-zA-Z]* ]]; then
  inicial_deps
  check_fqdn
  ask_ssl
fi

# Set host of the database #
echo -ne "* Enter the host of the database (${YELLOW}127.0.0.1${RESET}): "
read -r DB_HOST
[ -z "$DB_HOST" ] && DB_HOST="127.0.0.1"

# Set port of the database #
echo -ne "* Enter the port of the database (${YELLOW}3306${RESET}): "
read -r DB_PORT
[ -z "$DB_PORT" ] && DB_PORT="3306"

# Set name of the database #
echo -ne "* Enter the name of the database (${YELLOW}dashboard${RESET}): "
read -r DB_NAME
[ -z "$DB_NAME" ] && DB_NAME="dashboard"

# Set user of the database #
echo -ne "* Enter the username of the database (${YELLOW}dashboarduser${RESET}): "
read -r DB_USER
[ -z "$DB_USER" ] && DB_USER="dashboarduser"

# Set pass of the database #
DB_PASS=""
while [ -z "$DB_PASS" ]; do
  password_input DB_PASS "Enter the password of the database: " "Password cannot by empty!"
done

# Ask Time-Zone #
echo -e "* List of valid time-zones here: ${YELLOW}$(hyperlink "http://php.net/manual/en/timezones.php")${RESET}"
echo -ne "* Select Time-Zone (${YELLOW}America/New_York${RESET}): "
read -r TIMEZONE
[ -z "$TIMEZONE" ] && TIMEZONE="America/New_York"

# Summary #
echo
print_brake 75
echo
{
  echo -e "* Hostname/FQDN: $FQDN"
  echo -e "* Database Host: $DB_HOST"
  echo -e "* Database Port: $DB_PORT"
  echo -e "* Database Name: $DB_NAME"
  echo -e "* Database User: $DB_USER"
  echo -e "* Database Pass: (censored)"
} >> /var/log/controlpanel.info
echo -e "* Time-Zone: $TIMEZONE"
[ "$CONFIGURE_SSL" == true ] && echo -e "* Configure SSL: $CONFIGURE_SSL"
echo
print_brake 75
echo
sed -i -e "s@(censored)@$DB_PASS@g" /var/log/controlpanel.info
echo "" >> /var/log/controlpanel.info
echo "* After using this file, delete it immediately!" >> /var/log/controlpanel.info

# Confirm all the choices #
echo -n "* Initial settings complete, do you want to continue to the installation? (y/N): "
read -r CONTINUE_INSTALL
[[ "$CONTINUE_INSTALL" =~ [Yy] ]] && install_controlpanel
[[ "$CONTINUE_INSTALL" == * ]] && print_error "Installation aborted!" && exit 1
}

bye() {
echo
print_brake 70
echo
echo -e "${GREEN}* The script has finished the installation process!${RESET}"

[ "$CONFIGURE_SSL" == true ] && APP_URL="https://$FQDN"
[ "$CONFIGURE_SSL" == false ] && APP_URL="http://$FQDN"

echo -e "${GREEN}* To complete the configuration of your panel, go to ${YELLOW}$(hyperlink "$APP_URL/install").${RESET}"
echo -e "${GREEN}* Thank you for using this script!"
echo -e "* Support Group: ${YELLOW}$(hyperlink "$SUPPORT_LINK")${RESET}"
echo -e "${GREEN}HINT${RESET}: If you have questions about the information that is requested on the installation page\nall the necessary information about it is written in: ($YELLOW/var/log/controlpanel.info$RESET)."
print_brake 70
echo
}

# Exec Script #
main
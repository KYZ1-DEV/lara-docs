#!/bin/bash
set -e

APP_DIR=/var/www/html
GIT_REPO=${GIT_REPO:-"https://github.com/KYZ1-DEV/lara-docs.git"}
GIT_BRANCH=${GIT_BRANCH:-"main"}

cd $APP_DIR

echo "========================================"
echo "Laravel Docker Init Starting..."
echo "========================================"

# ==============================
# CLONE REPOSITORY
# ==============================
if [ ! -d "$APP_DIR/.git" ]; then
  echo "Repository belum ada, melakukan git clone..."
  rm -rf $APP_DIR/*
  git clone -b $GIT_BRANCH $GIT_REPO $APP_DIR
else
  echo "Repository sudah ada."
fi

# ==============================
# SETUP ENV
# ==============================
if [ ! -f ".env" ]; then
  echo "Copy .env.example → .env"
  cp .env.example .env
fi

echo "Inject environment ke .env"

sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=${DB_CONNECTION}/" .env
sed -i "s/^#* *DB_HOST=.*/DB_HOST=${DB_HOST}/" .env
sed -i "s/^#* *DB_PORT=.*/DB_PORT=${DB_PORT:-3306}/" .env
sed -i "s/^#* *DB_DATABASE=.*/DB_DATABASE=${DB_DATABASE}/" .env
sed -i "s/^#* *DB_USERNAME=.*/DB_USERNAME=${DB_USERNAME}/" .env
sed -i "s/^#* *DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/" .env

APP_ENV=$(grep ^APP_ENV= .env | cut -d '=' -f2 | tr -d '\r')
APP_ENV=${APP_ENV:-local}

echo "APP_ENV: $APP_ENV"

# ==============================
# PERMISSION
# ==============================
echo "Set permission..."
chown -R www-data:www-data $APP_DIR
chmod -R 775 storage bootstrap/cache || true

# ==============================
# COMPOSER INSTALL
# ==============================
echo "Running composer install..."
composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev

# ==============================
# GENERATE APP KEY
# ==============================
if ! grep -q "^APP_KEY=base64" .env; then
  php artisan key:generate
fi

# ==============================
# NPM INSTALL & BUILD
# ==============================
if [ -f "package.json" ]; then
  echo "Running npm install..."
  npm install

  echo "Building frontend assets..."
  npm run build
else
  echo "package.json tidak ditemukan, skip npm build."
fi

# ==============================
# WAIT DATABASE READY
# ==============================
echo "Waiting database ${DB_HOST}:${DB_PORT}..."
until nc -z ${DB_HOST} ${DB_PORT:-3306}; do
  sleep 2
done
echo "Database ready."

# ==============================
# MIGRATE
# ==============================
php artisan migrate --force

# ==============================
# OPTIMIZE
# ==============================
if [ "$APP_ENV" = "production" ]; then
  php artisan config:cache
  php artisan route:cache
  php artisan view:cache
else
  php artisan optimize:clear
fi

echo "Laravel ready 🚀"

exec apache2-foreground

#!/bin/bash
set -e

APP_DIR=/var/www/html
GIT_REPO=${GIT_REPO:-"https://github.com/KYZ1-DEV/stater-live.git"}
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
  echo "Repository sudah ada, skip clone."
fi

# ==============================
# SETUP ENV FILE
# ==============================
if [ ! -f ".env" ]; then
  echo "File .env belum ada, menyalin dari .env.example"
  cp .env.example .env
fi

echo "Menyesuaikan .env dengan variabel environment (${DB_CONNECTION})"

sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=${DB_CONNECTION}/" .env
sed -i "s/^#* *DB_HOST=.*/DB_HOST=${DB_HOST}/" .env
sed -i "s/^#* *DB_PORT=.*/DB_PORT=${DB_PORT:-3306}/" .env
sed -i "s/^#* *DB_DATABASE=.*/DB_DATABASE=${DB_DATABASE}/" .env
sed -i "s/^#* *DB_USERNAME=.*/DB_USERNAME=${DB_USERNAME}/" .env
sed -i "s/^#* *DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/" .env

cat .env | grep DB_

# ==============================
# PERMISSION
# ==============================
echo "Mengatur permission direktori..."

chown -R $USER_ID:$GROUP_ID $APP_DIR

mkdir -p storage/logs
touch storage/logs/laravel.log

chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

# ==============================
# INSTALL DEPENDENCY
# ==============================
echo "Validasi composer..."
composer validate --strict || true

echo "Menjalankan composer install..."
composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev

# ==============================
# GENERATE APP KEY (jika belum ada)
# ==============================
if ! grep -q "^APP_KEY=base64" .env; then
  echo "Generate APP_KEY..."
  php artisan key:generate
fi

# ==============================
# CEK APP_ENV
# ==============================
APP_ENV=$(grep ^APP_ENV= .env | cut -d '=' -f2 | tr -d '\r')
APP_ENV=${APP_ENV:-local}

echo "Environment Laravel: $APP_ENV"


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
# MIGRATION
# ==============================
echo "Menjalankan migrate..."
php artisan migrate --force

# ==============================
# OPTIMIZE / CLEAR CACHE
# ==============================
if [ "$APP_ENV" = "production" ]; then
  echo "Mode production: caching..."
  php artisan config:clear
  php artisan cache:clear
  php artisan view:clear
  php artisan route:clear

  php artisan config:cache
  php artisan route:cache
  php artisan view:cache
else
  echo "Mode development: clear cache..."
  php artisan config:clear
  php artisan cache:clear
  php artisan view:clear
  php artisan route:clear
fi

# ==============================
# START APACHE
# ==============================
exec apache2-foreground

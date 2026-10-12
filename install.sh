#!/usr/bin/env bash
# Installs or updates Tazavera: creates the settings on the first run, gets the code,
# builds the images, prepares the API and starts the stack, in that order.
# Run inside WSL from the tazavera folder: ./install.sh
set -euo pipefail

API_REPO=https://github.com/EdwinB1025/tazzavera-api.git
FRONT_REPO=https://github.com/EdwinB1025/tazavera-front.git
API_BRANCH=PROD
FRONT_BRANCH=master
ENV_PROD=.env.prod

cd "$(dirname "$0")"

fail() { echo "install.sh: $*" >&2; exit 1; }
artisan() { docker compose exec -T api php artisan --no-ansi "$@"; }

# Asks until the answer matches the pattern; secret answers are not shown
ask() {
  local prompt=$1 pattern=$2 secret=${3:-} value=
  while true; do
    if [ -n "$secret" ]; then read -rsp "$prompt: " value; echo >&2; else read -rp "$prompt: " value; fi
    [[ $value =~ $pattern ]] && break
    echo "  Not valid, try again." >&2
  done
  printf '%s' "$value"
}
# Writes KEY=value into a settings file (the value never contains | & or \)
set_value() { sed -i "s|^$2=.*|$2=$3|" "$1"; }
read_value() { sed -n "s/^$2=//p" "$1" | tr -d '\r'; }

# 1. Requirements
command -v git >/dev/null || fail "git is missing: sudo apt install git"
docker info >/dev/null 2>&1 || fail "Docker is not reachable: open Docker Desktop and turn on its WSL integration for Ubuntu"

# 2. Settings: the first run creates .env and .env.prod from the templates
if [ ! -f .env ]; then
  echo "First install: a few questions (the answers stay only on this machine, in .env)."
  tr -d '\r' < .env.example > .env
  set_value .env PUBLIC_ORIGIN "$(ask 'ngrok domain, e.g. https://xxxx.ngrok-free.dev' '^https://[A-Za-z0-9.-]+$')"
  set_value .env NGROK_AUTHTOKEN "$(ask 'ngrok authtoken' '^[A-Za-z0-9_]+$' secret)"
  echo "Database passwords: at least 12 characters, letters, digits and . _ - only."
  set_value .env DB_PASSWORD "$(ask 'Database password (app user)' '^[A-Za-z0-9._-]{12,}$' secret)"
  set_value .env DB_ROOT_PASSWORD "$(ask 'Database password (root)' '^[A-Za-z0-9._-]{12,}$' secret)"
fi
PUBLIC_ORIGIN=$(read_value .env PUBLIC_ORIGIN)
[ -n "$PUBLIC_ORIGIN" ] || fail "PUBLIC_ORIGIN is empty in .env"
[ -n "$(read_value .env NGROK_AUTHTOKEN)" ] || fail "NGROK_AUTHTOKEN is empty in .env"
[ -n "$(read_value .env DB_PASSWORD)" ] || fail "DB_PASSWORD is empty in .env"
[ -n "$(read_value .env DB_ROOT_PASSWORD)" ] || fail "DB_ROOT_PASSWORD is empty in .env"

if [ ! -f "$ENV_PROD" ]; then
  tr -d '\r' < .env.prod.example > "$ENV_PROD"
  set_value "$ENV_PROD" APP_URL "$PUBLIC_ORIGIN"
  set_value "$ENV_PROD" FRONT_URL "$PUBLIC_ORIGIN"
fi
[ "$(read_value "$ENV_PROD" APP_URL)" = "$PUBLIC_ORIGIN" ] || fail "APP_URL in .env.prod must be $PUBLIC_ORIGIN"
[ "$(read_value "$ENV_PROD" FRONT_URL)" = "$PUBLIC_ORIGIN" ] || fail "FRONT_URL in .env.prod must be $PUBLIC_ORIGIN"

# 3. Code: first run clones, later runs match the remote branch exactly
sync_repo() {
  local url=$1 branch=$2 dir=$3
  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch origin "$branch"
    git -C "$dir" checkout "$branch"
    git -C "$dir" reset --hard "origin/$branch"
  else
    git clone --branch "$branch" "$url" "$dir"
  fi
}
sync_repo "$API_REPO" "$API_BRANCH" tazavera-api
sync_repo "$FRONT_REPO" "$FRONT_BRANCH" tazavera-front

# 4. API image (api and scheduler), then its check (A7)
docker compose build api
docker compose run --rm --no-deps -T api composer check-platform-reqs --no-dev \
  || fail "The API image lacks PHP requirements (see the list above, step A3)"

# 5. APP_KEY, only while it is empty
if [ -z "$(read_value "$ENV_PROD" APP_KEY)" ]; then
  key=$(docker compose run --rm --no-deps -T api php artisan key:generate --show --no-ansi | tr -d '\r')
  set_value "$ENV_PROD" APP_KEY "$key"
fi

# 6. Database, API and scheduler
docker compose up -d --wait db api scheduler
artisan config:clear

# 7. Migrations, every run
artisan migrate --force

# 8. Seed and Passport keys, only on an empty install
has_client=$(artisan tinker --execute='echo App\Models\Passport\Client::front()->exists() ? 1 : 0;' | tr -d '\r')
[ "$has_client" = 1 ] || artisan db:seed --force
docker compose exec -T api test -f storage/oauth-private.key || artisan passport:keys

# 9. Front client ID: the seeder reuses the existing client and prints its ID
FRONT_CLIENT_ID=$(artisan db:seed --class=FrontClientSeeder --force | sed -n 's/.*Front client ID: //p' | tr -d '\r')
[ -n "$FRONT_CLIENT_ID" ] || fail "The API did not print the front client ID"
export FRONT_CLIENT_ID

# 10. API caches, every run
artisan config:cache
artisan route:cache
artisan view:cache
artisan event:cache

# 11. Front image with the public origin and the client ID, then the front and the tunnel
docker compose build front
docker compose up -d front ngrok

# Check (B5): the front answers on /es within about a minute
front_ok=0
for _ in $(seq 1 30); do
  if docker compose exec -T front wget -q -O /dev/null http://localhost:3000/es; then front_ok=1; break; fi
  sleep 2
done
if [ "$front_ok" != 1 ]; then
  docker compose logs --tail=30 front
  fail "The front does not answer on /es (see its log above)"
fi

# 12. State
docker compose ps
echo "Front client ID: $FRONT_CLIENT_ID"
echo "Public origin: $PUBLIC_ORIGIN"
echo "Next: the checks (C8)."

<p align="center">
  <img src="https://raw.githubusercontent.com/EdwinB1025/tazzavera-api/PROD/public/scribeIcon.svg" width="120">
</p>


Deployment repository for **Tazavera**, the specialty coffee verification platform. It holds the `docker-compose.yml` and the `install.sh` script that install or update the whole platform (API, front, database, scheduler and public tunnel) on a single machine, with one command.

> This repository has **no application code**. The code lives in `tazzavera-api` (Laravel) and `tazavera-front` (Next.js); `install.sh` downloads them from GitHub and builds them here.

## 🧩 What it runs

| Service | What it is | Reachable from |
|---|---|---|
| 🌐 **ngrok** | The single public door and the `https` | The internet, on the fixed public address |
| 🖥️ **front** | Next.js: the pages, and it forwards the API calls | ngrok (inside the network); `localhost:3000` for local checks |
| 🐘 **api** | Laravel on Apache (`php:8.5-apache`) | Only the front |
| ⏱️ **scheduler** | Same image as the API, runs the scheduled tasks | — |
| 🗄️ **db** | MySQL 8 | Only the API and the scheduler |

```
browser ──https──▶ ngrok ──▶ front :3000 ──http──▶ api :80 ──▶ db :3306
```

The API and the database have no public address: everything the browser needs from the API goes through the front.

## ✅ Requirements

**The machine**
- 🪟 Windows with **WSL2** and the **Ubuntu** distribution.
- 🐳 **Docker Desktop** installed and **open**, with *Settings → Resources → WSL integration → Ubuntu* turned on. In the Ubuntu terminal, `docker compose version` must answer.
- 🔧 **git** in Ubuntu (`sudo apt install git` if missing).
- 💾 About **7.5 GiB of memory** for Docker (`docker info`). With less, lower `MaxRequestWorkers` in `docker-compose.yml` (see Notes).
- 🔌 **Port 3000 free** on the machine.
- 📶 **Internet access**: the builds download from GitHub, Docker Hub, npm and Packagist.

**The accounts**
- 🌐 An **ngrok account**: its domain (dashboard → *Domains*; on the free plan, one fixed domain with a random name) and its authtoken (*Getting Started → Your Authtoken*). Nothing to install: ngrok runs as a container.
- 🐙 The repositories `EdwinB1025/tazzavera-api` (branch `deploy`) and `EdwinB1025/tazavera-front` (branch `develop`) **public**, with what you want to deploy pushed to those branches.

**Have at hand** for the first run (the script asks for them)
- 🌐 The ngrok domain, with `https://` (e.g. `https://xxxx.ngrok-free.dev`).
- 🔑 The ngrok authtoken.
- 🗄️ Two database passwords (app user and root): at least 12 characters, letters, digits and `. _ -` only.

## 🚀 Installation (first time)

Everything runs in the **Ubuntu terminal**, inside the WSL file system (not under `/mnt/c/…`).

### 1. Clone this repository

```bash
git clone https://github.com/EdwinB1025/tazavera.git ~/tazavera
cd ~/tazavera
chmod +x install.sh
```

### 2. Run the installation

```bash
./install.sh
```

On the first run the script asks for the ngrok domain, the ngrok token and the two database passwords (the secret answers are not shown). It writes them into two settings files on this machine, `.env` and `.env.prod`, created from the templates `.env.example` and `.env.prod.example`. They hold secrets and never go to git. Later runs reuse them and ask nothing.

Then it downloads and builds everything: the first run takes several minutes. It ends with every service `running`, the front client ID and the public address.

### 3. Check

- 🌍 Open the public address: the landing lists the verified offerings (on the free plan, ngrok shows a warning page on the first visit: *Visit Site*).
- 🔐 Sign in as a specialist and as a coffee shop.

## 🔄 Updating

After pushing to `deploy` (API) or `develop` (front):

```bash
cd ~/tazavera
./install.sh
```

The same script updates: it downloads the new commits, rebuilds only what changed, applies the new migrations and restarts what is needed. The database, the API key and the Passport keys are kept.

## ⚙️ What `install.sh` does

1. ✅ Checks that git and Docker are available.
2. 📝 First run: asks for the ngrok domain, the token and the database passwords, and creates `.env` and `.env.prod`. Later runs: checks them.
3. 📥 Clones the API and the front (first run) or updates them to match GitHub exactly.
4. 🏗️ Builds the API image and checks its PHP requirements.
5. 🔑 Generates `APP_KEY` the first time.
6. ▶️ Starts the database, the API and the scheduler.
7. 🗃️ Applies the migrations.
8. 🌱 Seeds the database and creates the Passport keys, only on an empty install.
9. 🪪 Reads the front client ID from the API.
10. ⚡ Rebuilds the API caches.
11. 🖥️ Builds the front with the public address and the client ID, starts it with the tunnel, and waits until it answers.
12. 📋 Shows the state of every service.

> The images and the containers are **always** built and started by `install.sh`. Never `docker compose build` or `up` by hand: the front would be built without its client ID and could not sign in.

## 🛠️ Everyday commands

Run them from `~/tazavera`.

| Command | Does |
|---|---|
| `./install.sh` | Installs or updates everything |
| `docker compose ps` | State of every service |
| `docker compose logs -f api` | Follows a service's log (`api`, `front`, `db`, `ngrok`, `scheduler`) |
| `docker compose exec api bash` | Opens a shell inside a container |
| `docker compose down` | Stops and removes the containers; **the data is kept** |
| `docker compose down -v` | ⚠️ Also deletes the database and the Passport keys |
| `docker stats --no-stream` | Memory and CPU of each container |

## 🩹 Troubleshooting

| Message or symptom | Cause |
|---|---|
| `docker: command not found` in Ubuntu | Docker Desktop's WSL integration for Ubuntu is off |
| `Docker is not reachable` | Docker Desktop is closed |
| `APP_URL in .env.prod must be …` | `.env.prod` was edited by hand and its address no longer matches `PUBLIC_ORIGIN` in `.env` |
| A setting was typed wrong on the first run | Delete `.env` and `.env.prod` before the database exists, and run `./install.sh` again (after the first full install, change only `.env` and keep the database passwords) |
| `$'\r': command not found` | `install.sh` was saved with Windows line endings: save it with LF |
| `The API image lacks PHP requirements` | A PHP extension is missing in the API's Dockerfile |
| `The front does not answer on /es` | See the front's log printed above the message |
| The first install failed during the seed | Start clean: `docker compose down -v`, then `./install.sh` |

## 📝 Notes

- 🗄️ **The database passwords are fixed after the first install**: MySQL keeps the ones it was created with. Changing them in `.env` later breaks the API's connection.
- 🌐 **The public address is fixed.** It is built into the front and the API. Changing it means new values in both settings files, updating the OAuth client's redirect by hand, rebuilding the front (`./install.sh`) and losing the registered passkeys.
- 🔑 **`APP_KEY` must never change** once generated: it encrypts the sessions and the two-factor secrets.
- 🧮 **Simultaneous requests:** `MaxRequestWorkers 70` in `docker-compose.yml` (section `configs:`) is sized for ~7.5 GiB of Docker memory. To change it, edit the number and run `./install.sh`.
- 📂 **`tazavera-api/` and `tazavera-front/`** are copies for the deploy: never edit them, the next run discards the changes.
- 🔒 **`.env` and `.env.prod` hold secrets**: they never go to git.

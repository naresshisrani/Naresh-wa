#!/usr/bin/env bash
# ==============================================================================
# 🚀 1-COMMAND AWS EC2 DEPLOYMENT SCRIPT FOR NARESH-WA
# Repo: https://github.com/naresshisrani/Naresh-wa
# ==============================================================================
set -euo pipefail

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   WhatsApp Automation & AI SaaS — AWS EC2 One-Command Deploy ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

APP_DIR="/home/ubuntu/whatsapp-automation"
REPO_URL="https://github.com/naresshisrani/Naresh-wa.git"

# 1. Install prerequisites (Docker, Docker Compose, Git, Curl) if missing
echo "📦 [1/6] Verifying system packages and Docker..."
if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
    echo "   Installing Docker & Docker Compose..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release git

    # Official Docker repo setup
    sudo install -m 0755 -d /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER" || true
    echo "   ✔ Docker installed successfully"
else
    echo "   ✔ Docker is already installed"
fi

# 2. Clone or pull repository
echo "📂 [2/6] Setting up project directory..."
if [ -d "$APP_DIR/.git" ]; then
    echo "   Repository already exists at $APP_DIR. Pulling latest code..."
    cd "$APP_DIR"
    git fetch origin main
    git reset --hard origin/main
else
    echo "   Cloning $REPO_URL to $APP_DIR..."
    sudo mkdir -p "$APP_DIR"
    sudo chown -R "$USER:$USER" "$APP_DIR"
    git clone "$REPO_URL" "$APP_DIR"
    cd "$APP_DIR"
fi

# 3. Memory & Resource Sizing
echo "📊 [3/6] Analyzing instance capacity..."
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
TOTAL_RAM_GB=$(awk "BEGIN {print int($TOTAL_RAM_MB / 1024)}")
echo "   Total Server RAM: ${TOTAL_RAM_MB}MB (~${TOTAL_RAM_GB}GB)"

if [ "$TOTAL_RAM_GB" -ge 14 ]; then
    WA_SESSIONS=35
    MEM_LIMIT="12G"
elif [ "$TOTAL_RAM_GB" -ge 7 ]; then
    WA_SESSIONS=18
    MEM_LIMIT="6G"
elif [ "$TOTAL_RAM_GB" -ge 3 ]; then
    WA_SESSIONS=7
    MEM_LIMIT="2.5G"
else
    WA_SESSIONS=2
    MEM_LIMIT="750M"
fi
echo "   Allocated limits: ${WA_SESSIONS} concurrent WhatsApp sessions, ${MEM_LIMIT} memory cap"

# 4. Configure Production Environment (.env)
echo "🔐 [4/6] Checking production environment (.env)..."
if [ ! -f .env ]; then
    echo "   Creating production .env from template..."
    cp PRODUCTION_ENV.example .env
    
    # Generate cryptographically secure 48-byte session secret
    RAND_SECRET=$(openssl rand -hex 48)
    sed -i "s/^SESSION_SECRET=.*/SESSION_SECRET=${RAND_SECRET}/" .env || echo "SESSION_SECRET=${RAND_SECRET}" >> .env
    
    sed -i "s/^MAX_CONCURRENT_WHATSAPP_SESSIONS=.*/MAX_CONCURRENT_WHATSAPP_SESSIONS=${WA_SESSIONS}/" .env || true
    sed -i "s/^MEM_LIMIT=.*/MEM_LIMIT=${MEM_LIMIT}/" .env || true
    sed -i "s/^TRUST_PROXY=.*/TRUST_PROXY=true/" .env || true
    sed -i "s/^FORCE_HTTPS=.*/FORCE_HTTPS=true/" .env || true
    
    echo "   ✔ .env generated with a secure random SESSION_SECRET"
    echo "   ⚠️ Notice: To enable Gemini AI auto-replies, edit .env and set GEMINI_API_KEY=your_key"
else
    echo "   ✔ Existing .env preserved"
fi

# 5. Build and launch Docker services
echo "🐳 [5/6] Building and launching containers..."
sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build --remove-orphans

# 6. Verify health
echo "🩺 [6/6] Checking service status..."
sleep 5
sudo docker compose ps

PUBLIC_IP=$(curl -s -m 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || curl -s -m 3 ifconfig.me 2>/dev/null || echo "localhost")

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   ✅ DEPLOYMENT SUCCESSFUL!                                   ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║   • Direct IP Access:  http://${PUBLIC_IP} (or https if domain pointed)"
echo "║   • Health check:      curl -f http://localhost:3000/health"
echo "║   • Logs:              sudo docker compose logs -f app"
echo "║   • Data Dir:          $APP_DIR/data"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

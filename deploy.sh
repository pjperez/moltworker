#!/bin/bash
# Interactive deployment script for Moltworker
# This script will guide you through setting up all required secrets and deploy

set -e

echo "=========================================="
echo "  Moltworker Deployment Setup"
echo "=========================================="
echo ""
echo "This script will help you deploy Moltworker to Cloudflare."
echo "You'll need to provide 4 secrets. Don't worry, I'll tell you where to get each one!"
echo ""

# Check if wrangler is installed
if ! command -v npx &> /dev/null; then
    echo "❌ Error: npm/npx is not installed. Please install Node.js first."
    echo "   Visit: https://nodejs.org/"
    exit 1
fi

# Function to prompt for secret
prompt_secret() {
    local name=$1
    local description=$2
    local where_to_get=$3
    local example=$4
    
    echo ""
    echo "----------------------------------------"
    echo "🔑 Setting up: $name"
    echo "----------------------------------------"
    echo "📋 What is it: $description"
    echo "🌐 Where to get it: $where_to_get"
    if [ -n "$example" ]; then
        echo "💡 Example: $example"
    fi
    echo ""
    
    # Check if already set
    if npx wrangler secret list 2>/dev/null | grep -q "^$name$"; then
        echo "✅ $name is already set. Skip? (y/n) [y]: "
        read -r skip
        if [ -z "$skip" ] || [ "$skip" = "y" ] || [ "$skip" = "Y" ]; then
            echo "Skipping $name..."
            return
        fi
    fi
    
    echo "Paste your $name (input will be VISIBLE - press Enter when done, Ctrl+C to cancel):"
    read -r value
    echo ""
    
    if [ -z "$value" ]; then
        echo "❌ Error: $name cannot be empty"
        exit 1
    fi
    
    echo "Setting $name..."
    echo "$value" | npx wrangler secret put "$name"
    echo "✅ $name set successfully!"
}

echo "Step 1/5: Checking prerequisites..."
echo ""

# Check if logged in
echo "Checking Cloudflare authentication..."
if ! npx wrangler whoami &>/dev/null; then
    echo "🔐 You need to log in to Cloudflare first."
    echo "Running: npx wrangler login"
    npx wrangler login
fi
echo "✅ Authenticated with Cloudflare!"

# Secret 1: GLM_API_KEY
prompt_secret \
    "GLM_API_KEY" \
    "Your API key from Z.ai (GLM Coding Plan) - this powers the AI" \
    "1. Go to https://z.ai/ and create an account\n   2. Click 'Subscribe' to get GLM Coding Plan\n   3. Go to your account settings to find your API key" \
    "sk-xxxxxxxxxxxxxxxxxxxxxxxx"

# Secret 2: MOLTBOT_GATEWAY_TOKEN
prompt_secret \
    "MOLTBOT_GATEWAY_TOKEN" \
    "A secret token to protect your gateway - like a password" \
    "Generate one by running: openssl rand -hex 32\n   Or just make up a random string (keep it secret!)" \
    "a1b2c3d4e5f6... (64 characters)"

# Optional: Cloudflare Access (for admin UI)
echo ""
echo "----------------------------------------"
echo "🔑 Optional: Admin UI Authentication"
echo "----------------------------------------"
echo "The admin UI lets you manage devices at /_admin"
echo "You can secure it with Cloudflare Access (Zero Trust) or leave it open (less secure)"
echo ""
echo "Set up Cloudflare Access for admin UI? (y/n) [n]: "
read -r setup_access

if [ "$setup_access" = "y" ] || [ "$setup_access" = "Y" ]; then
    # Secret 3: CF_ACCESS_TEAM_DOMAIN
    prompt_secret \
        "CF_ACCESS_TEAM_DOMAIN" \
        "Your Cloudflare Access team domain" \
        "Cloudflare Dashboard → Zero Trust → Access (shown at top)" \
        "yourname.cloudflareaccess.com"

    # Secret 4: CF_ACCESS_AUD
    prompt_secret \
        "CF_ACCESS_AUD" \
        "Application Audience tag" \
        "Cloudflare Dashboard → Zero Trust → Access → Applications → your app" \
        "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
else
    echo "Skipping Cloudflare Access setup. Admin UI will be accessible without authentication."
    echo "⚠️  WARNING: Anyone with your worker URL can access /_admin"
fi

echo ""
echo "=========================================="
echo "Step 5/5: Optional - R2 Storage Setup"
echo "=========================================="
echo ""
echo "R2 storage saves your data so it doesn't disappear when the container restarts."
echo "This is OPTIONAL but recommended for production."
echo ""
echo "To set up R2 (you can skip this for now):"
echo "1. Cloudflare Dashboard → R2 → Create bucket"
echo "2. Name it: moltbot-data"
echo "3. Location: Europe (WEUR)"
echo "4. R2 → Manage R2 API Tokens → Create"
echo "5. Then run this script again and it will ask for R2 secrets"
echo ""
echo "Skip R2 for now? (y/n) [y]: "
read -r skip_r2

if [ -z "$skip_r2" ] || [ "$skip_r2" = "y" ] || [ "$skip_r2" = "Y" ]; then
    echo "Skipping R2 setup..."
else
    prompt_secret \
        "R2_ACCESS_KEY_ID" \
        "R2 API access key ID" \
        "Cloudflare Dashboard → R2 → Manage R2 API Tokens → Create" \
        "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    
    prompt_secret \
        "R2_SECRET_ACCESS_KEY" \
        "R2 API secret access key" \
        "Same place as above, shown when you create the token" \
        "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    
    prompt_secret \
        "CF_ACCOUNT_ID" \
        "Your Cloudflare Account ID" \
        "Cloudflare Dashboard (shown in the sidebar or URL)" \
        "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
fi

echo ""
echo "=========================================="
echo "🚀 All secrets configured!"
echo "=========================================="
echo ""
echo "Building and deploying..."
echo ""

# Build and deploy
npm run build
npx wrangler deploy

echo ""
echo "=========================================="
echo "✅ Deployment Complete!"
echo "=========================================="
echo ""
echo "Your Moltworker is now running!"
echo ""
echo "📍 Access your gateway at:"
echo "   https://your-worker-name.workers.dev?token=YOUR_GATEWAY_TOKEN"
echo ""
echo "🔧 Admin UI (requires Cloudflare Access login):"
echo "   https://your-worker-name.workers.dev/_admin/"
echo ""
echo "💡 To find your worker URL:"
echo "   Run: npx wrangler deploy"
echo "   Or check: Cloudflare Dashboard → Workers & Pages"
echo ""

if [ -z "$skip_r2" ] || [ "$skip_r2" = "y" ] || [ "$skip_r2" = "Y" ]; then
    echo "⚠️  WARNING: R2 storage not configured!"
    echo "   Your data will be lost when the container restarts."
    echo "   To add R2 later, run this script again."
    echo ""
fi

echo "Happy hacking! 🎉"
echo ""
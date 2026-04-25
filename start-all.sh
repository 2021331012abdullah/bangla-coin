#!/bin/bash

# Bangla Coin: Linux Deployment Script (PM2 version)
ROOT=$(pwd)
ADDR_FILE="$ROOT/deployedAddresses.json"

# Default fallback addresses
TRANSFER="0x5FbDB2315678afecb367f032d93F642f64180aa3"
DAO="0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"
FLAG="0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"
FREEZE="0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9"

echo "==================================================="
echo "   Starting Bangla Coin Multi-Node Environment"
echo "==================================================="

# 1. Start 3 Hardhat Nodes
echo "1. Starting 3 Hardhat Nodes..."
pm2 start "npx hardhat node --port 10001" --name "node-10001"
pm2 start "npx hardhat node --port 10002" --name "node-10002"
pm2 start "npx hardhat node --port 10003" --name "node-10003"

echo "Waiting 12s for nodes to initialize..."
sleep 12

# 2. Deploy Contracts
echo "2. Deploying Smart Contracts..."
npx hardhat run scripts/deploy.js --network node1

# Read freshly deployed addresses if file exists (using jq for parsing)
if [ -f "$ADDR_FILE" ]; then
    # Note: Requires 'jq' installed (sudo apt install jq)
    TRANSFER=$(jq -r '.Transfer' $ADDR_FILE)
    DAO=$(jq -r '.DAO' $ADDR_FILE)
    FLAG=$(jq -r '.FlagRegistry' $ADDR_FILE)
    FREEZE=$(jq -r '.Freeze' $ADDR_FILE)
    echo "Contracts Updated: Transfer=$TRANSFER"
fi

# 3. API Gateway
echo "3. Starting API Gateway..."
cd "$ROOT/api-gateway" && pm2 start npm --name "api-gateway" -- start
sleep 4

# 4. Gateway Admin UI
echo "4. Starting Gateway Admin UI..."
cd "$ROOT/gateway-admin" && pm2 start npm --name "gateway-admin" -- run dev -- --port 6001

# 5-7. Validators
VAL_ENV="TRANSFER_CONTRACT=$TRANSFER,FLAG_CONTRACT=$FLAG,DAO_CONTRACT=$DAO,FREEZE_CONTRACT=$FREEZE,ADMIN_USER=admin,ADMIN_PASS=admin,JWT_SECRET=validator_secret,GATEWAY_URL=http://localhost:5000"

for i in {1..3}
do
    PORT_BACK=$((3000 + i))
    PORT_UI=$((4000 + i))
    RPC_PORT=$((10000 + i))
    
    echo "Starting Validator $i..."
    # Backend
    cd "$ROOT/validator-template/backend" && \
    VALIDATOR_PORT=$PORT_BACK VALIDATOR_ID=$i RPC_URL="http://127.0.0.1:$RPC_PORT" \
    TRANSFER_CONTRACT=$TRANSFER FLAG_CONTRACT=$FLAG DAO_CONTRACT=$DAO FREEZE_CONTRACT=$FREEZE \
    ADMIN_USER=admin ADMIN_PASS=admin JWT_SECRET=validator_secret GATEWAY_URL=http://localhost:5000 \
    pm2 start npm --name "val-$i-backend" -- start

    # Frontend
    cd "$ROOT/validator-template/frontend" && \
    VITE_PORT=$PORT_UI VITE_API_URL="http://localhost:$PORT_BACK" \
    pm2 start npm --name "val-$i-ui" -- run dev -- --port $PORT_UI
done

# 8. User App
echo "8. Starting User App..."
cd "$ROOT/user-app" && pm2 start npm --name "user-app" -- run dev -- --port 3000

echo "✅ All services launched in PM2!"
pm2 list

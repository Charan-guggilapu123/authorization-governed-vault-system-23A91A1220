#!/bin/sh
set -e

export RPC_URL=${RPC_URL:-http://blockchain:8545}
export PRIVATE_KEY=${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}

echo "Using RPC_URL=$RPC_URL"
node -v
npm -v

npm install
npx hardhat compile
npx hardhat run scripts/deploy.js --network local

if [ -f deployment-output.json ]; then
  echo "Deployment result:"
  cat deployment-output.json
fi

exec "$@"

#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
PROJECT_NAME=${2:-twin}
FUNCTION_NAME="${PROJECT_NAME}-${ENVIRONMENT}-api"
REGION="us-west-1"

echo "🚀 Deploying backend only for ${FUNCTION_NAME}..."

# 1. Build Lambda package
cd "$(dirname "$0")/.."
echo "📦 Building Lambda package..."
(cd backend && uv run deploy.py)

# 2. Update Lambda function code directly (no Terraform)
echo "⬆️  Updating Lambda function code..."
aws lambda update-function-code \
  --function-name "$FUNCTION_NAME" \
  --zip-file fileb://backend/lambda-deployment.zip \
  --region "$REGION" \
  --query 'FunctionName' \
  --output text

echo ""
echo "✅ Backend deployment complete!"
echo "🔧 Function: $FUNCTION_NAME"

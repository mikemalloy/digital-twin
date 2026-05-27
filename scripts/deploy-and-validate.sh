#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
PROJECT_NAME=${2:-twin}

echo "🚀 Deploying and validating ${PROJECT_NAME} to ${ENVIRONMENT}..."

# 1. Run the normal deployment
./scripts/deploy.sh "$ENVIRONMENT" "$PROJECT_NAME"

echo ""
echo "🔍 Validating deployment..."

# 2. Get the function name
FUNCTION_NAME="${PROJECT_NAME}-${ENVIRONMENT}-api"

# 3. Check Lambda environment variables
echo "📋 Checking Lambda environment variables..."
ACTUAL_MODEL=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --query 'Environment.Variables.BEDROCK_MODEL_ID' --output text)
ACTUAL_BUCKET=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --query 'Environment.Variables.S3_BUCKET' --output text)
ACTUAL_CORS=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --query 'Environment.Variables.CORS_ORIGINS' --output text)

echo "  ✓ BEDROCK_MODEL_ID: $ACTUAL_MODEL"
echo "  ✓ S3_BUCKET: $ACTUAL_BUCKET"
echo "  ✓ CORS_ORIGINS: $ACTUAL_CORS"

# 4. Validate expected values
EXPECTED_MODEL="us.amazon.nova-lite-v1:0"
EXPECTED_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-memory-$(aws sts get-caller-identity --query Account --output text)"

if [ "$ACTUAL_MODEL" != "$EXPECTED_MODEL" ]; then
    echo "❌ ERROR: Model ID mismatch!"
    echo "   Expected: $EXPECTED_MODEL"
    echo "   Actual: $ACTUAL_MODEL"
    echo ""
    echo "🔧 Forcing Lambda update..."
    aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --environment Variables="{BEDROCK_MODEL_ID=$EXPECTED_MODEL,S3_BUCKET=$ACTUAL_BUCKET,USE_S3=true,CORS_ORIGINS=$ACTUAL_CORS}" \
        --query 'FunctionName' --output text
    echo "✓ Lambda configuration updated"
else
    echo "✅ Model ID is correct"
fi

if [[ "$ACTUAL_BUCKET" != *"$EXPECTED_BUCKET"* ]]; then
    echo "❌ WARNING: S3 bucket name unexpected: $ACTUAL_BUCKET"
else
    echo "✅ S3 bucket is correct"
fi

# 5. Test the API endpoint
echo ""
echo "🧪 Testing API endpoint..."
API_URL=$(cd terraform && terraform output -raw api_gateway_url)
echo "Testing: $API_URL/health"

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/health" || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ Health check passed (200 OK)"
    
    # Test chat endpoint
    echo "Testing chat endpoint..."
    CHAT_RESPONSE=$(curl -s -X POST "$API_URL/chat" \
        -H "Content-Type: application/json" \
        -d '{"message": "Hello, test message"}' \
        -w "HTTP_STATUS:%{http_code}" || echo "HTTP_STATUS:000")
    
    CHAT_STATUS=$(echo "$CHAT_RESPONSE" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
    CHAT_BODY=$(echo "$CHAT_RESPONSE" | sed 's/HTTP_STATUS:[0-9]*$//')
    
    if [ "$CHAT_STATUS" = "200" ]; then
        echo "✅ Chat endpoint working correctly"
        echo "   Response preview: $(echo "$CHAT_BODY" | jq -r '.response' 2>/dev/null | head -c 50)..."
    else
        echo "❌ Chat endpoint failed (Status: $CHAT_STATUS)"
        echo "   Response: $CHAT_BODY"
    fi
else
    echo "❌ Health check failed (Status: $HTTP_STATUS)"
fi

# 6. Show final URLs
echo ""
echo "🌐 Deployment URLs:"
echo "   API Gateway: $API_URL"
cd terraform
echo "   Frontend: $(terraform output -raw s3_website_url)"

echo ""
echo "✅ Deployment validation complete!"
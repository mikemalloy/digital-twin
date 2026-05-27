#!/bin/bash

# Test API script - Direct backend testing
ENVIRONMENT=${1:-test}
PROJECT_NAME=${2:-twin}

echo "🔬 Testing ${PROJECT_NAME}-${ENVIRONMENT} API directly..."

# Get API URL from Terraform
cd terraform
API_URL=$(terraform output -raw api_gateway_url 2>/dev/null)

if [ -z "$API_URL" ]; then
    echo "❌ Could not get API URL from Terraform outputs"
    exit 1
fi

echo "📡 API URL: $API_URL"
echo ""

# Test 1: Health Check
echo "🏥 Testing health endpoint..."
HEALTH_RESPONSE=$(curl -s -w "HTTP_STATUS:%{http_code}" "$API_URL/health")
HEALTH_STATUS=$(echo "$HEALTH_RESPONSE" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | sed 's/HTTP_STATUS:[0-9]*$//')

if [ "$HEALTH_STATUS" = "200" ]; then
    echo "✅ Health check passed"
    echo "   Response: $HEALTH_BODY"
    BEDROCK_MODEL=$(echo "$HEALTH_BODY" | grep -o '"bedrock_model":"[^"]*"' | cut -d'"' -f4)
    echo "   Model ID: $BEDROCK_MODEL"
else
    echo "❌ Health check failed (Status: $HEALTH_STATUS)"
    echo "   Response: $HEALTH_BODY"
    exit 1
fi

echo ""

# Test 2: Root endpoint
echo "🏠 Testing root endpoint..."
ROOT_RESPONSE=$(curl -s -w "HTTP_STATUS:%{http_code}" "$API_URL/")
ROOT_STATUS=$(echo "$ROOT_RESPONSE" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
ROOT_BODY=$(echo "$ROOT_RESPONSE" | sed 's/HTTP_STATUS:[0-9]*$//')

if [ "$ROOT_STATUS" = "200" ]; then
    echo "✅ Root endpoint passed"
    echo "   Model: $(echo "$ROOT_BODY" | grep -o '"ai_model":"[^"]*"' | cut -d'"' -f4)"
else
    echo "❌ Root endpoint failed (Status: $ROOT_STATUS)"
    echo "   Response: $ROOT_BODY"
fi

echo ""

# Test 3: Chat endpoint
echo "💬 Testing chat endpoint..."
CHAT_PAYLOAD='{"message": "Hello, this is a test message. Please respond briefly."}'
CHAT_RESPONSE=$(curl -s -w "HTTP_STATUS:%{http_code}" \
    -X POST "$API_URL/chat" \
    -H "Content-Type: application/json" \
    -d "$CHAT_PAYLOAD")

CHAT_STATUS=$(echo "$CHAT_RESPONSE" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
CHAT_BODY=$(echo "$CHAT_RESPONSE" | sed 's/HTTP_STATUS:[0-9]*$//')

if [ "$CHAT_STATUS" = "200" ]; then
    echo "✅ Chat endpoint working!"
    
    # Parse JSON response (basic extraction)
    SESSION_ID=$(echo "$CHAT_BODY" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
    AI_RESPONSE=$(echo "$CHAT_BODY" | grep -o '"response":"[^"]*"' | cut -d'"' -f4)
    
    echo "   Session ID: $SESSION_ID"
    echo "   AI Response: ${AI_RESPONSE:0:100}..." # First 100 chars
    
    # Test follow-up message
    echo ""
    echo "🔄 Testing follow-up message..."
    FOLLOWUP_PAYLOAD="{\"message\": \"What was my previous message?\", \"session_id\": \"$SESSION_ID\"}"
    FOLLOWUP_RESPONSE=$(curl -s -w "HTTP_STATUS:%{http_code}" \
        -X POST "$API_URL/chat" \
        -H "Content-Type: application/json" \
        -d "$FOLLOWUP_PAYLOAD")
    
    FOLLOWUP_STATUS=$(echo "$FOLLOWUP_RESPONSE" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
    if [ "$FOLLOWUP_STATUS" = "200" ]; then
        echo "✅ Memory/session working!"
        FOLLOWUP_AI=$(echo "$FOLLOWUP_RESPONSE" | sed 's/HTTP_STATUS:[0-9]*$//' | grep -o '"response":"[^"]*"' | cut -d'"' -f4)
        echo "   AI Response: ${FOLLOWUP_AI:0:100}..."
    else
        echo "❌ Follow-up failed (Status: $FOLLOWUP_STATUS)"
        FOLLOWUP_BODY=$(echo "$FOLLOWUP_RESPONSE" | sed 's/HTTP_STATUS:[0-9]*$//')
        echo "   Response: $FOLLOWUP_BODY"
    fi
    
else
    echo "❌ Chat endpoint failed (Status: $CHAT_STATUS)"
    echo "   Response: $CHAT_BODY"
    
    # Show recent Lambda logs for debugging
    echo ""
    echo "📋 Recent Lambda logs:"
    aws logs get-log-events \
        --log-group-name "/aws/lambda/${PROJECT_NAME}-${ENVIRONMENT}-api" \
        --log-stream-name "$(aws logs describe-log-streams \
            --log-group-name "/aws/lambda/${PROJECT_NAME}-${ENVIRONMENT}-api" \
            --order-by LastEventTime --descending --limit 1 \
            --query 'logStreams[0].logStreamName' --output text)" \
        --query 'events[-3:].message' --output text 2>/dev/null | tail -3
fi

echo ""
echo "🏁 API testing complete!"
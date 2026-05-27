#!/bin/bash
# Load environment variables
source .env


# Create a unique S3 bucket name for deployment
DEPLOY_BUCKET="twin-deploy-$(date +%s)"

# Create the bucket
aws s3 mb s3://$DEPLOY_BUCKET --region $DEFAULT_AWS_REGION

# Upload your zip file to S3
aws s3 cp lambda-deployment.zip s3://$DEPLOY_BUCKET/ --region $DEFAULT_AWS_REGION

# Update Lambda function from S3
aws lambda update-function-code \
    --function-name twin-api \
    --s3-bucket $DEPLOY_BUCKET \
    --s3-key lambda-deployment.zip \
    --region $DEFAULT_AWS_REGION

# Clean up: delete the temporary bucket
aws s3 rm s3://$DEPLOY_BUCKET/lambda-deployment.zip
aws s3 rb s3://$DEPLOY_BUCKET
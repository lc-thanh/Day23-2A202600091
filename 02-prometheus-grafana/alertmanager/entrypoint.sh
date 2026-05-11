#!/bin/sh
# Create webhook URL file from environment variable
mkdir -p /etc/alertmanager
echo "$SLACK_WEBHOOK_URL" > /etc/alertmanager/slack_webhook_url

# Start alertmanager
exec alertmanager --config.file=/etc/alertmanager/alertmanager.yml

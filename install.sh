#!/bin/bash

set -e

# --- Configuration ---
INSTALL_DIR="/root/apple-id-bot"
SERVICE_NAME="apple-bot"
EXECUTABLE_NAME="apple_bot"
GITHUB_REPO_URL="https://github.com/MBNpro-ir/Apple-Id-seller-bot"
GITHUB_EXECUTABLE_URL="${GITHUB_REPO_URL}/raw/main/apple_bot"
GITHUB_REQUIREMENTS_URL="${GITHUB_REPO_URL}/raw/main/requirements.txt"

BACKUP_DIR="${INSTALL_DIR}/backups"
LOG_FILE="${INSTALL_DIR}/update.log"
LICENSE_API_URL="http://38.180.138.154:8080"

# --- Colors for Output ---
YELLOW='\033[0;93m'
GREEN='\033[0;92m'
RED='\033[0;91m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Functions ---
log_message() {
    echo -e "\n${GREEN}=> $1${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}ERROR: This script must be run as root. Please use 'sudo ./install.sh'${NC}"
        exit 1
    fi
}

# Show main menu
show_menu() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Apple ID Bot Manager                      ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}║  ${YELLOW}1.${NC} ${GREEN}Install Bot                                              ║${NC}"
    echo -e "${GREEN}║  ${YELLOW}2.${NC} ${GREEN}Update Bot                                               ║${NC}"
    echo -e "${GREEN}║  ${YELLOW}3.${NC} ${GREEN}Uninstall Bot                                            ║${NC}"
    echo -e "${GREEN}║  ${YELLOW}4.${NC} ${GREEN}Check Bot Status                                         ║${NC}"
    echo -e "${GREEN}║  ${YELLOW}5.${NC} ${GREEN}View Bot Logs                                            ║${NC}"
    echo -e "${GREEN}║  ${YELLOW}6.${NC} ${GREEN}Start Bot Service                                        ║${NC}"
    echo -e "${GREEN}║  ${YELLOW}7.${NC} ${GREEN}Restart Bot Service                                      ║${NC}"
    echo -e "${GREEN}║  ${YELLOW}8.${NC} ${GREEN}Stop Bot Service                                         ║${NC}"
    echo -e "${GREEN}║  ${YELLOW}0.${NC} ${GREEN}Exit                                                     ║${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    # Read from terminal directly
    read -p "Please select an option [0-8]: " choice < /dev/tty
    export choice
}
prompt_for_input() {
    local prompt=$1 var_name=$2 default_value=$3
    local full_prompt="${prompt}"
    if [ -n "$default_value" ]; then full_prompt+=" [Default: $default_value]"; fi
    while true; do
        read -p "$full_prompt: " user_input < /dev/tty
        local final_value="${user_input:-$default_value}"
        if [ -n "$final_value" ]; then
            eval "$var_name=\"$final_value\""
            break
        else
            echo -e "   ${RED}[ERROR] This field cannot be empty. Please try again.${NC}"
        fi
    done
}

# Prompt for BOT_TOKEN with validation
prompt_for_bot_token() {
    local value

    while true; do
        read -p "Enter your BOT_TOKEN: " value < /dev/tty

        if [ -z "$value" ]; then
            echo -e "   ${RED}[ERROR] BOT_TOKEN cannot be empty. Please try again.${NC}"
            continue
        fi

        # Validate BOT_TOKEN format (should be like: 123456789:AAA...)
        if [[ "$value" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            # Check if it contains colon and has reasonable length
            if [[ ${#value} -ge 35 && "$value" == *":"* ]]; then
                BOT_TOKEN="$value"
                echo -e "   ${GREEN}✅ Valid BOT_TOKEN format${NC}"
                break
            else
                echo -e "   ${RED}[ERROR] Invalid BOT_TOKEN format. Should be like: 123456789:AAA...${NC}"
                echo -e "   ${YELLOW}💡 Example: 1234567890:AAGBCoKoGdM80pLx90CSSSeupXc-rg2v2Lw${NC}"
            fi
        else
            echo -e "   ${RED}[ERROR] Invalid BOT_TOKEN format. Should contain numbers:letters${NC}"
            echo -e "   ${YELLOW}💡 Example: 1234567890:AAGBCoKoGdM80pLx90CSSSeupXc-rg2v2Lw${NC}"
        fi
    done
}

# Generate API key from secret
generate_api_key() {
    local secret=$1
    # Try different hash commands
    if command -v sha256sum >/dev/null 2>&1; then
        echo -n "$secret" | sha256sum | cut -d' ' -f1 | cut -c1-32
    elif command -v shasum >/dev/null 2>&1; then
        echo -n "$secret" | shasum -a 256 | cut -d' ' -f1 | cut -c1-32
    elif command -v openssl >/dev/null 2>&1; then
        echo -n "$secret" | openssl dgst -sha256 | cut -d' ' -f2 | cut -c1-32
    else
        # Fallback - simple hash (not secure but works for testing)
        echo -n "$secret" | od -A n -t x1 | tr -d ' \n' | cut -c1-32
    fi
}

# Validate license key with API
validate_license_key() {
    local license_key=$1
    local api_secret=$2

    echo "   Validating license key..."

    # Check if API is running
    if ! curl -s "$LICENSE_API_URL/status" >/dev/null 2>&1; then
        echo -e "   ${RED}[ERROR] License API server is not running or unreachable.${NC}"
        echo -e "   ${YELLOW}[INFO] Contact @mbnsubmanager_bot for support.${NC}"
        return 1
    fi

    # Generate API key
    local api_key=$(generate_api_key "$api_secret")

    # Validate license
    local response=$(curl -s -X POST "$LICENSE_API_URL/validate" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $api_key" \
        -d "{\"license_key\":\"$license_key\"}" 2>/dev/null)

    if [ $? -eq 0 ] && echo "$response" | grep -q '"valid":true'; then
        local license_name=$(echo "$response" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
        local expires_at=$(echo "$response" | grep -o '"expires_at":"[^"]*"' | cut -d'"' -f4)
        echo -e "   ${GREEN}✅ License validated successfully!${NC}"
        echo "   License Name: $license_name"
        echo "   Expires: $expires_at"
        return 0
    else
        local error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        echo -e "   ${RED}[ERROR] License validation failed: ${error_msg:-Unknown error}${NC}"
        return 1
    fi
}

prompt_for_license() {
    local prompt=$1 var_name=$2 api_secret=$3
    while true; do
        read -p "$prompt: " user_input < /dev/tty
        if [ -n "$user_input" ]; then
            if validate_license_key "$user_input" "$api_secret"; then
                eval "$var_name=\"$user_input\""
                break
            else
                echo -e "   ${RED}[ERROR] Invalid license key. Please try again.${NC}"
            fi
        else
            echo -e "   ${RED}[ERROR] License key cannot be empty. Please try again.${NC}"
        fi
    done
}
prompt_for_numeric() {
    local prompt=$1 var_name=$2 default_value=$3
    local full_prompt="${prompt}"
    if [ -n "$default_value" ]; then full_prompt+=" [Default: $default_value]"; fi
    while true; do
        read -p "$full_prompt: " user_input < /dev/tty
        local final_value="${user_input:-$default_value}"
        if [[ "$final_value" =~ ^-?[0-9]+$ ]]; then
            eval "$var_name=\"$final_value\""
            break
        else
            echo -e "   ${RED}[ERROR] This field must be a numeric value. Please try again.${NC}"
        fi
    done
}

# Prompt for ADMIN_ID with validation
prompt_for_admin_id() {
    local value

    while true; do
        read -p "Enter your primary ADMIN_ID (numeric): " value < /dev/tty

        if [ -z "$value" ]; then
            echo -e "   ${RED}[ERROR] ADMIN_ID cannot be empty. Please try again.${NC}"
            continue
        fi

        # Validate ADMIN_ID format (should be numeric and reasonable length)
        if [[ "$value" =~ ^[0-9]+$ ]]; then
            # Check if it has reasonable length for Telegram user ID (7-10 digits typically)
            if [[ ${#value} -ge 7 && ${#value} -le 12 ]]; then
                ADMIN_ID="$value"
                echo -e "   ${GREEN}✅ Valid ADMIN_ID format${NC}"
                break
            else
                echo -e "   ${RED}[ERROR] ADMIN_ID should be 7-12 digits long${NC}"
                echo -e "   ${YELLOW}💡 Example: 123456789 or 1234567890${NC}"
            fi
        else
            echo -e "   ${RED}[ERROR] ADMIN_ID should contain only numbers${NC}"
            echo -e "   ${YELLOW}💡 Example: 123456789 or 1234567890${NC}"
        fi
    done
}

prompt_for_payment_group() {
    local prompt=$1 var_name=$2 default_value=$3
    local full_prompt="${prompt}"
    if [ -n "$default_value" ]; then full_prompt+=" [Default: $default_value]"; fi
    while true; do
        read -p "$full_prompt: " user_input < /dev/tty
        local final_value="${user_input:-$default_value}"
        if [ -n "$final_value" ]; then
            # Accept both numeric IDs (like -100123456789) and usernames (like @channel_name)
            if [[ "$final_value" =~ ^-?[0-9]+$ ]] || [[ "$final_value" =~ ^@[a-zA-Z0-9_]+$ ]]; then
                eval "$var_name=\"$final_value\""
                break
            else
                echo -e "   ${RED}[ERROR] Please enter a valid group ID (numeric like -100123456789) or username (like @channel_name).${NC}"
            fi
        else
            echo -e "   ${RED}[ERROR] This field cannot be empty. Please try again.${NC}"
        fi
    done
}

# Prompt for ADMIN_LINK with validation
prompt_for_admin_link() {
    local value

    while true; do
        read -p "Enter the admin contact link (e.g., @your_username): " value < /dev/tty

        if [ -z "$value" ]; then
            echo -e "   ${RED}[ERROR] Admin link cannot be empty. Please try again.${NC}"
            continue
        fi

        # Validate ADMIN_LINK format (should start with @)
        if [[ "$value" =~ ^@[a-zA-Z0-9_]{5,32}$ ]]; then
            ADMIN_LINK="$value"
            echo -e "   ${GREEN}✅ Valid admin link format${NC}"
            break
        else
            echo -e "   ${RED}[ERROR] Admin link should start with @ and be 5-32 characters${NC}"
            echo -e "   ${YELLOW}💡 Example: @your_username or @admin_support${NC}"
        fi
    done
}

# Get file hash for comparison
get_file_hash() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        sha256sum "$file_path" | cut -d' ' -f1
    else
        echo "none"
    fi
}


# Check if update is available
check_for_update() {
    local current_file="${INSTALL_DIR}/${EXECUTABLE_NAME}"
    local temp_file="${INSTALL_DIR}/${EXECUTABLE_NAME}.new"

    log_message "Checking for updates..."

    # Download new version
    log_message "Downloading latest version..."
    if ! wget -q -O "$temp_file" "$GITHUB_EXECUTABLE_URL"; then
        log_message "${RED}ERROR: Failed to download new version${NC}"
        return 1
    fi

    chmod +x "$temp_file"

    # Compare hashes
    local current_hash=$(get_file_hash "$current_file")
    local new_hash=$(get_file_hash "$temp_file")

    if [ "$current_hash" != "$new_hash" ]; then
        log_message "${GREEN}Update available!${NC}"
        return 0
    else
        log_message "${YELLOW}No update available${NC}"
        rm -f "$temp_file"
        return 1
    fi
}

# Backup current version
backup_current_version() {
    local current_file="${INSTALL_DIR}/${EXECUTABLE_NAME}"
    local backup_file="${BACKUP_DIR}/${EXECUTABLE_NAME}.backup.$(date +%Y%m%d_%H%M%S)"

    if [ -f "$current_file" ]; then
        log_message "Creating backup..."
        mkdir -p "$BACKUP_DIR"
        cp "$current_file" "$backup_file"
        log_message "Backup created: $backup_file"
        return 0
    else
        log_message "${YELLOW}No current version to backup${NC}"
        return 1
    fi
}

# Install function
install_bot() {
    log_message "Starting Apple ID Bot installation..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
log_message "Step 1: Installing required system packages..."
echo "   Updating package lists..."
apt-get update -y > /dev/null 2>&1
echo "   Installing required packages..."
if ! apt-get install -y wget curl python3 python3-pip > /dev/null 2>&1; then
    echo "   ${YELLOW}[WARNING] Failed to install some packages. The script will continue, but may not work correctly.${NC}"
fi
echo "   System packages are ready."
log_message "Step 2: Downloading bot application..."

# Create installation directory
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# Download the compiled executable
echo "   Downloading compiled bot executable..."
if ! wget -q --show-progress -O "${EXECUTABLE_NAME}" "${GITHUB_EXECUTABLE_URL}"; then
    log_message "${RED}ERROR: Failed to download the bot executable. Please check your internet connection.${NC}"
    exit 1
fi

# Make executable
chmod +x "${EXECUTABLE_NAME}"
echo "   Bot executable downloaded successfully."

# Download requirements.txt for reference (optional)
echo "   Downloading requirements.txt..."
if wget -q -O "requirements.txt" "${GITHUB_REQUIREMENTS_URL}"; then
    echo "   Requirements file downloaded."
else
    echo "   ${YELLOW}[WARNING] Could not download requirements.txt. Creating minimal version.${NC}"
    # Create a minimal requirements.txt as fallback
    cat > requirements.txt << EOF
# This file is for reference only
# The bot executable is already compiled with all dependencies
python-telegram-bot>=20.0
python-dotenv>=1.0.0
openpyxl>=3.1.0
aiosqlite>=0.19.0
EOF
fi

echo "   Download complete."

while true; do
    log_message "Step 3: License validation..."
    echo "--------------------------------------------------"
    echo -e "${YELLOW}⚠️  This bot requires a valid license to operate.${NC}"
    echo ""

    # First get API secret for validation
    API_SECRET="MBN_AppleID_2025_SecureKey_9x7K2mP8qR5vN3wE6tY1uI4oA8sD7fG"

    prompt_for_license "Enter your LICENSE KEY" LICENSE_KEY "$API_SECRET"
    echo ""

    log_message "Step 4: Please provide the bot configuration..."
    echo "--------------------------------------------------"
    prompt_for_bot_token
    prompt_for_admin_id
    prompt_for_admin_link
    prompt_for_payment_group "Enter the payment group ID (e.g., -100123456789 or @channel_name)" PAYMENT_GROUP_ID
    prompt_for_input "Log Level (DEBUG, INFO, WARNING, ERROR)" LOG_LEVEL "INFO"
    prompt_for_numeric "Backup Hour (0-23)" BACKUP_TIME_HOUR "0"
    prompt_for_numeric "Backup Minute (0-59)" BACKUP_TIME_MINUTE "0"
    prompt_for_input "Timezone" TIMEZONE "Asia/Tehran"
    prompt_for_input "Bank Name" BANK_NAME "بانک ملی ایران"
    prompt_for_input "Bank Account Number" BANK_ACCOUNT_NUMBER "1234567890123456"
    prompt_for_input "Bank Account Holder's Name" BANK_ACCOUNT_HOLDER "نام صاحب حساب"
    prompt_for_input "Bank IBAN" BANK_IBAN "IR123456789012345678901234"
    prompt_for_input "Support Username (e.g., @your_username)" SUPPORT_USERNAME "@your_support"
    echo "--------------------------------------------------"
    log_message "Configuration Summary - Please review:"
    echo -e "${YELLOW}"
    cat << EOF
LICENSE_KEY=${LICENSE_KEY}
BOT_TOKEN=${BOT_TOKEN}
ADMIN_ID=${ADMIN_ID}
ADMIN_LINK=${ADMIN_LINK}
PAYMENT_GROUP_ID=${PAYMENT_GROUP_ID}
LOG_LEVEL=${LOG_LEVEL}
BACKUP_TIME_HOUR=${BACKUP_TIME_HOUR}
BACKUP_TIME_MINUTE=${BACKUP_TIME_MINUTE}
TIMEZONE=${TIMEZONE}
BANK_NAME=${BANK_NAME}
BANK_ACCOUNT_NUMBER=${BANK_ACCOUNT_NUMBER}
BANK_ACCOUNT_HOLDER=${BANK_ACCOUNT_HOLDER}
BANK_IBAN=${BANK_IBAN}
SUPPORT_USERNAME=${SUPPORT_USERNAME}
EOF
    echo -e "${NC}"
    read -p "Is the configuration correct? [Y/n]: " confirmation < /dev/tty
    if [[ "$confirmation" != "n" && "$confirmation" != "N" ]]; then
        break
    else
        echo -e "${YELLOW}Restarting configuration process...${NC}"
    fi
done
log_message "Step 5: Creating .env configuration file..."
cat > .env << EOF
# Telegram Bot Configuration
BOT_TOKEN=${BOT_TOKEN}
ADMIN_ID=${ADMIN_ID}
ADMIN_LINK=${ADMIN_LINK}
PAYMENT_GROUP_ID=${PAYMENT_GROUP_ID}

# Database Configuration (Dual Storage System)
EXCEL_FILE_PATH=database/data.xlsx
SQL_DATABASE_PATH=database/bot_database.db
JSON_DATABASE_PATH=database/bot_data.json
JSON_BACKUP_PATH=backups/

# Logging Configuration
LOG_LEVEL=${LOG_LEVEL}
LOG_FILE=botlog.txt

# Backup Configuration
BACKUP_TIME_HOUR=${BACKUP_TIME_HOUR}
BACKUP_TIME_MINUTE=${BACKUP_TIME_MINUTE}
TIMEZONE=${TIMEZONE}

# Bank Information (for wallet deposits)
BANK_NAME=${BANK_NAME}
BANK_ACCOUNT_NUMBER=${BANK_ACCOUNT_NUMBER}
BANK_ACCOUNT_HOLDER=${BANK_ACCOUNT_HOLDER}
BANK_IBAN=${BANK_IBAN}

# License Configuration
LICENSE_KEY=${LICENSE_KEY}
LICENSE_API_URL=http://38.180.138.154:8080
API_SECRET=MBN_AppleID_2025_SecureKey_9x7K2mP8qR5vN3wE6tY1uI4oA8sD7fG

# Other Configuration
SUPPORT_USERNAME=${SUPPORT_USERNAME}
EOF
echo "   .env file created."
log_message "Step 6: Creating user data directories..."
cd "${INSTALL_DIR}"
mkdir -p database config backups
touch botlog.txt
echo "   Directories (database, config, backups) are ready."

log_message "Step 7: Setting up the bot as a system service..."
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Apple ID Bot Service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${EXECUTABLE_NAME}
Restart=always
RestartSec=10
TimeoutStartSec=60
TimeoutStopSec=30
KillMode=mixed
KillSignal=SIGTERM
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
echo "   Service file created."
log_message "Step 8: Starting the bot service..."
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service
systemctl start ${SERVICE_NAME}.service
echo "   Service enabled and started."
    echo "--------------------------------------------------"
    log_message "✅ Installation Complete!"
    log_message "The bot is now running. Use these commands to manage it:"
    echo ""
    echo -e "${YELLOW}📋 Service Management Commands:${NC}"
    echo -e "${GREEN}   Enable & Start:${NC} ${YELLOW}sudo systemctl daemon-reload${NC}"
    echo -e "                   ${YELLOW}sudo systemctl enable ${SERVICE_NAME}${NC}"
    echo -e "                   ${YELLOW}sudo systemctl start ${SERVICE_NAME}${NC}"
    echo -e "                   ${YELLOW}sudo journalctl -u ${SERVICE_NAME} -f${NC}"
    echo ""
    echo -e "${GREEN}   Restart:${NC}        ${YELLOW}sudo systemctl restart ${SERVICE_NAME}${NC}"
    echo -e "                   ${YELLOW}sudo journalctl -u ${SERVICE_NAME} -f${NC}"
    echo ""
    echo -e "${GREEN}   Stop & Disable:${NC} ${YELLOW}sudo systemctl disable ${SERVICE_NAME}${NC}"
    echo -e "                   ${YELLOW}sudo systemctl stop ${SERVICE_NAME}${NC}"
    echo -e "                   ${YELLOW}sudo systemctl daemon-reload${NC}"
    echo ""
    read -p "Press Enter to continue..." < /dev/tty
}

# Update function
update_bot() {
    log_message "Starting Apple ID Bot update..."

    if [ ! -f "${INSTALL_DIR}/${EXECUTABLE_NAME}" ]; then
        log_message "${RED}ERROR: Bot is not installed. Please install it first.${NC}"
        read -p "Press Enter to continue..." < /dev/tty
        return 1
    fi

    # Check for updates
    if check_for_update; then
        local new_file="${INSTALL_DIR}/${EXECUTABLE_NAME}.new"

        backup_current_version

        log_message "Performing update..."

        # Stop the service
        log_message "Stopping bot service..."
        systemctl stop "$SERVICE_NAME"
        sleep 2

        # Replace the executable
        log_message "Replacing executable..."
        mv "$new_file" "${INSTALL_DIR}/${EXECUTABLE_NAME}"

        # Start the service
        log_message "Starting bot service..."
        systemctl start "$SERVICE_NAME"
        sleep 3

        # Check if service started successfully
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log_message "${GREEN}✅ Update completed successfully!${NC}"
            log_message "Service is running"
            echo ""
            read -p "Press Enter to continue..." < /dev/tty
        else
            log_message "${RED}❌ Update failed! Service is not running${NC}"
            # Try to rollback
            local latest_backup=$(ls -t "${BACKUP_DIR}/${EXECUTABLE_NAME}.backup."* 2>/dev/null | head -n1)
            if [ -n "$latest_backup" ]; then
                log_message "${YELLOW}Attempting rollback...${NC}"
                systemctl stop "$SERVICE_NAME"
                cp "$latest_backup" "${INSTALL_DIR}/${EXECUTABLE_NAME}"
                systemctl start "$SERVICE_NAME"
                if systemctl is-active --quiet "$SERVICE_NAME"; then
                    log_message "${GREEN}Rollback completed successfully${NC}"
                else
                    log_message "${RED}Rollback failed${NC}"
                fi
            fi
            echo ""
            read -p "Press Enter to continue..." < /dev/tty
        fi
    else
        # No update available - return to main menu automatically
        sleep 2
        return 0
    fi
}

# Uninstall function
uninstall_bot() {
    log_message "Starting Apple ID Bot uninstallation..."
    echo "--------------------------------------------------"
    echo -e "${RED}⚠️  WARNING: This will remove the bot executable but preserve your data${NC}"
    echo ""
    read -p "Are you sure you want to uninstall the bot? [y/N]: " confirmation < /dev/tty
    if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
        log_message "Uninstallation cancelled."
        read -p "Press Enter to continue..." < /dev/tty
        return 0
    fi

    log_message "Step 1: Stopping and disabling the systemd service..."
    systemctl stop ${SERVICE_NAME}.service &> /dev/null || true
    systemctl disable ${SERVICE_NAME}.service &> /dev/null || true
    echo "   Service stopped and disabled."

    log_message "Step 2: Removing the systemd service file..."
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    if [ -f "$SERVICE_FILE" ]; then
        rm "$SERVICE_FILE"
        echo "   Service file removed."
    fi

    log_message "Step 3: Reloading systemd daemon..."
    systemctl daemon-reload
    echo "   Systemd reloaded."

    log_message "Step 4: Removing application files..."
    if [ -d "$INSTALL_DIR" ]; then
        rm -f "${INSTALL_DIR}/${EXECUTABLE_NAME}"
        echo "   Removed: Bot executable (${EXECUTABLE_NAME})"
    else
        echo "   Installation directory not found. Nothing to remove."
    fi

    echo "--------------------------------------------------"
    log_message "✅ Uninstallation Complete!"
    log_message "The following user data has been PRESERVED in ${INSTALL_DIR}:"
    echo "   - .env (Your configuration)"
    echo "   - database/ (Your user and Apple ID data)"
    echo "   - config/ (Your bot settings)"
    echo "   - backups/ (All created backups)"
    echo "   - botlog.txt (The main application log)"
    echo ""
    read -p "Press Enter to continue..." < /dev/tty
}

# Check status function
check_status() {
    log_message "Bot Service Status:"
    echo "--------------------------------------------------"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}✅ Service is RUNNING${NC}"
    else
        echo -e "${RED}❌ Service is NOT RUNNING${NC}"
    fi
    echo ""
    systemctl status "$SERVICE_NAME" --no-pager -l
    echo ""
    read -p "Press Enter to continue..." < /dev/tty
}

# View logs function
view_logs() {
    log_message "Bot Logs (Press Ctrl+C to exit):"
    echo "--------------------------------------------------"
    echo "Showing last 50 lines and following new logs..."
    echo ""
    journalctl -u "$SERVICE_NAME" -n 50 -f
}

# Start service function
start_service() {
    log_message "Starting bot service..."

    # Reload daemon
    echo "   Reloading systemd daemon..."
    systemctl daemon-reload

    # Enable service
    echo "   Enabling service..."
    systemctl enable "$SERVICE_NAME" 2>/dev/null || true

    # Start service with timeout
    echo "   Starting service..."
    timeout 60 systemctl start "$SERVICE_NAME" 2>/dev/null || {
        log_message "${RED}❌ Service start timed out${NC}"
        echo ""
        echo -e "${YELLOW}📋 Troubleshooting:${NC}"
        echo -e "${GREEN}   Check status: ${YELLOW}sudo systemctl status $SERVICE_NAME${NC}"
        echo -e "${GREEN}   View logs:    ${YELLOW}sudo journalctl -u $SERVICE_NAME -n 20${NC}"
        echo -e "${GREEN}   Manual start: ${YELLOW}sudo systemctl start $SERVICE_NAME${NC}"
        read -p "Press Enter to continue..." < /dev/tty
        return 1
    }

    sleep 5

    # Check status
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_message "${GREEN}✅ Service started successfully${NC}"
        echo ""
        echo -e "${YELLOW}📋 Service is now running!${NC}"
        echo -e "${GREEN}   View logs: ${YELLOW}sudo journalctl -u $SERVICE_NAME -f${NC}"
        echo -e "${GREEN}   Status:    ${YELLOW}sudo systemctl status $SERVICE_NAME${NC}"
        echo ""
        echo -e "${YELLOW}Would you like to view live logs now? [y/N]:${NC}"
        read -p "" view_logs_choice < /dev/tty
        if [[ "$view_logs_choice" == "y" || "$view_logs_choice" == "Y" ]]; then
            echo ""
            echo -e "${GREEN}Showing live logs (Press Ctrl+C to exit):${NC}"
            sleep 2
            journalctl -u "$SERVICE_NAME" -f
        fi
    else
        log_message "${RED}❌ Service failed to start${NC}"
        echo ""
        echo -e "${YELLOW}📋 Troubleshooting:${NC}"
        echo -e "${GREEN}   Check status: ${YELLOW}sudo systemctl status $SERVICE_NAME${NC}"
        echo -e "${GREEN}   View logs:    ${YELLOW}sudo journalctl -u $SERVICE_NAME -n 20${NC}"
        echo -e "${GREEN}   Manual start: ${YELLOW}sudo systemctl start $SERVICE_NAME${NC}"
    fi
    echo ""
    read -p "Press Enter to continue..." < /dev/tty
}

# Restart service function
restart_service() {
    log_message "Restarting bot service..."

    # Stop service first with timeout
    echo "   Stopping service..."
    timeout 30 systemctl stop "$SERVICE_NAME" 2>/dev/null || {
        echo "   Service stop timed out, force killing..."
        timeout 10 systemctl kill --signal=SIGTERM "$SERVICE_NAME" 2>/dev/null || true
        sleep 2
        timeout 5 systemctl kill --signal=SIGKILL "$SERVICE_NAME" 2>/dev/null || true
    }
    sleep 3

    # Reload daemon to ensure clean state
    echo "   Reloading systemd daemon..."
    systemctl daemon-reload

    # Start service with timeout
    echo "   Starting service..."
    timeout 60 systemctl start "$SERVICE_NAME" 2>/dev/null || {
        log_message "${RED}❌ Service start timed out${NC}"
        echo ""
        echo -e "${YELLOW}📋 Troubleshooting:${NC}"
        echo -e "${GREEN}   Check status: ${YELLOW}sudo systemctl status $SERVICE_NAME${NC}"
        echo -e "${GREEN}   View logs:    ${YELLOW}sudo journalctl -u $SERVICE_NAME -n 20${NC}"
        read -p "Press Enter to continue..." < /dev/tty
        return 1
    }
    sleep 5

    # Check status
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_message "${GREEN}✅ Service restarted successfully${NC}"
        echo ""
        echo -e "${YELLOW}📋 Useful commands:${NC}"
        echo -e "${GREEN}   View logs: ${YELLOW}sudo journalctl -u $SERVICE_NAME -f${NC}"
        echo -e "${GREEN}   Status:    ${YELLOW}sudo systemctl status $SERVICE_NAME${NC}"
    else
        log_message "${RED}❌ Service is not running after restart${NC}"
        echo ""
        echo -e "${YELLOW}📋 Troubleshooting:${NC}"
        echo -e "${GREEN}   Check status: ${YELLOW}sudo systemctl status $SERVICE_NAME${NC}"
        echo -e "${GREEN}   View logs:    ${YELLOW}sudo journalctl -u $SERVICE_NAME -n 20${NC}"
        echo -e "${GREEN}   Manual start: ${YELLOW}sudo systemctl start $SERVICE_NAME${NC}"
    fi
    echo ""
    read -p "Press Enter to continue..." < /dev/tty
}

# Stop service function
stop_service() {
    log_message "Stopping bot service..."

    # Stop service with timeout
    echo "   Stopping service..."
    timeout 30 systemctl stop "$SERVICE_NAME" &>/dev/null || {
        echo "   Service stop timed out, force killing..."
        timeout 10 systemctl kill --signal=SIGTERM "$SERVICE_NAME" &>/dev/null || true
        sleep 2
        timeout 5 systemctl kill --signal=SIGKILL "$SERVICE_NAME" &>/dev/null || true
    }

    # Disable service
    echo "   Disabling service..."
    timeout 10 systemctl disable "$SERVICE_NAME" &>/dev/null || true

    # Reload daemon
    echo "   Reloading systemd..."
    timeout 10 systemctl daemon-reload &>/dev/null || true

    sleep 3

    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log_message "${GREEN}✅ Service stopped and disabled successfully${NC}"
        echo ""
        echo -e "${YELLOW}📋 To start again use option 6 or:${NC}"
        echo -e "${GREEN}   ${YELLOW}sudo systemctl daemon-reload${NC}"
        echo -e "${GREEN}   ${YELLOW}sudo systemctl enable $SERVICE_NAME${NC}"
        echo -e "${GREEN}   ${YELLOW}sudo systemctl start $SERVICE_NAME${NC}"
    else
        log_message "${RED}❌ Service is still running${NC}"
        echo ""
        echo -e "${YELLOW}📋 Try manual stop:${NC}"
        echo -e "${GREEN}   Force stop: ${YELLOW}sudo systemctl kill $SERVICE_NAME${NC}"
        echo -e "${GREEN}   Check:      ${YELLOW}sudo systemctl status $SERVICE_NAME${NC}"
    fi
    echo ""
    read -p "Press Enter to continue..." < /dev/tty
}

# Main script
main() {
    check_root

    # Initialize choice variable
    choice=""

    # Check for command line arguments first
    if [ "$1" = "install" ] || [ "$1" = "1" ]; then
        install_bot
        exit 0
    elif [ "$1" = "update" ] || [ "$1" = "2" ]; then
        update_bot
        exit 0
    elif [ "$1" = "uninstall" ] || [ "$1" = "3" ]; then
        uninstall_bot
        exit 0
    elif [ "$1" = "status" ] || [ "$1" = "4" ]; then
        check_status
        exit 0
    elif [ "$1" = "logs" ] || [ "$1" = "5" ]; then
        view_logs
        exit 0
    elif [ "$1" = "restart" ] || [ "$1" = "6" ]; then
        restart_service
        exit 0
    fi

    # Interactive menu
    while true; do
        show_menu

        case $choice in
            1)
                install_bot
                ;;
            2)
                update_bot
                ;;
            3)
                uninstall_bot
                ;;
            4)
                check_status
                ;;
            5)
                view_logs
                ;;
            6)
                start_service
                ;;
            7)
                restart_service
                ;;
            8)
                stop_service
                ;;
            0)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                echo -e "${YELLOW}Please enter a number between 0-8 and press Enter.${NC}"
                sleep 3
                ;;
        esac
    done
}

# Run main function with arguments
main "$@"
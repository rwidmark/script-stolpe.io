#!/bin/bash

## Script made by Robin Stolpe 2024 to be used at https://stolpe.io in the post https://stolpe.io/how-to/secure-ssh/
## sudo chmod +x secure_ssh.sh
## sudo ./secure_ssh.sh

# Variables
SSHConfigFilePath="/etc/ssh/sshd_config"
RestartService=("sshd" "ufw")

# Functions
# Function to prompt for 'y' or 'n' and store the result in a variable
ask_yes_no() {
    local prompt="$1"
    local answer

    while true; do
        read -p "$prompt [y/n]: " answer
        case "$answer" in
        [Yy])
            answer="y"
            break
            ;;
        [Nn])
            answer="n"
            break
            ;;
        *) echo "Please answer y or n." ;;
        esac
    done

    echo $answer
}

# Function to prompt the user for a port number and validate it
get_and_validate_port() {
    local port
    while true; do
        # Prompt user for SSH port number
        read -p "Please enter the SSH port number you want to use, at least two numbers: " port

        # Check if the input contains only numbers
        if [[ ! $port =~ ^[0-9]+$ ]]; then
            echo "Invalid input: The port must contain only numbers."
        # Check if the length of the port is more than two characters
        elif [[ ${#port} -le 2 ]]; then
            echo "Invalid input: The port number must have more than two digits."
        else
            # Valid port number
            echo $port
            return
        fi

        echo "Please try again."
    done
}

# Function to replace lines if they exist
replace_lines() {
    local file="$1"
    shift
    local lines=("$@")

    for line in "${lines[@]}"; do
        IFS=":" read -r search replace <<<"$line"
        if grep -q "^$search$" "$file"; then
            sudo sed -i "s|^$search$|$replace|" "$file"
        fi
    done
}

# Function to check if a port is already allowed in UFW
is_port_allowed() {
    local port="$1"
    sudo ufw status | grep -q "$port"
    return $?
}

manage_service() {
    local action="$1"
    local service_name="$2"

    # Validate inputs
    if [ -z "$action" ] || [ -z "$service_name" ]; then
        echo "Both action and service name are required."
        return 1
    fi

    case "$action" in
    start)
        if systemctl is-active --quiet "$service_name"; then
            # do nothing
            :
        else
            echo "Service $service_name is not running. Starting it..."
            if sudo systemctl start "$service_name"; then
                echo "Service $service_name started successfully."
            else
                echo "Failed to start $service_name."
                return 1
            fi
        fi
        ;;
    enable)
        if systemctl is-enabled --quiet "$service_name"; then
            # do nothing
            :
        else
            echo "Service $service_name is not enabled. Enabling it..."
            if sudo systemctl enable "$service_name"; then
                echo "Service $service_name enabled successfully."
            else
                echo "Failed to enable $service_name."
                return 1
            fi
        fi
        ;;
    restart)
        if systemctl is-active --quiet "$service_name"; then
            echo "Service $service_name is running. Restarting it..."
            if sudo systemctl restart "$service_name"; then
                echo "Service $service_name restarted successfully."
            else
                echo "Failed to restart $service_name."
                return 1
            fi
        fi
        ;;
    reload)
        if systemctl is-active --quiet "$service_name"; then
            echo "Reloading $service_name..."
            if sudo systemctl reload "$service_name"; then
                echo "Service $service_name reloaded successfully."
            else
                echo "Failed to reload $service_name."
                return 1
            fi
        fi
        ;;
    *)
        echo "Invalid action. Valid actions are: start, enable, restart, reload."
        return 1
        ;;
    esac
    return 0
}

ChangeSSHPort=$(ask_yes_no "Do you want to change your SSH port?")
if [ "$ChangeSSHPort" == "y" ]; then
    SSHPort=$(get_and_validate_port)
fi

if [ "$ChangeSSHPort" == "y" ]; then
    SSHConfig=(
        "#Port 22:Port $SSHPort"
        "#PermitRootLogin prohibit-password:PermitRootLogin no"
        "#LoginGraceTime 2m:LoginGraceTime 1m"
        "#MaxAuthTries 6:MaxAuthTries 4"
        "#PermitEmptyPasswords no:PermitEmptyPasswords no"
        "#PermitUserEnvironment no:PermitUserEnvironment no"
        "#MaxSessions 10:MaxSessions 3"
        "#Banner none:Banner none"
    )
else
    # Lines to replace in SSHD configuration
    SSHConfig=(
        "#PermitRootLogin prohibit-password:PermitRootLogin no"
        "#LoginGraceTime 2m:LoginGraceTime 1m"
        "#MaxAuthTries 6:MaxAuthTries 4"
        "#PermitEmptyPasswords no:PermitEmptyPasswords no"
        "#PermitUserEnvironment no:PermitUserEnvironment no"
        "#ClientAliveInterval 0:ClientAliveInterval 60"
        "#ClientAliveCountMax 3:ClientAliveCountMax 10"
        "#Banner none:Banner none"
    )
fi

# Start script
echo "Reconfiguring SSH settings..."
echo "Backing up sshd_config..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Call the function with the file and the array of lines
replace_lines "$SSHConfigFilePath" "${SSHConfig[@]}"

# Open SSH port in UFW
# If it's a DNS opening port 53 for everyone
if ! is_port_allowed "$SSHPort"; then
    sudo ufw allow $SSHPort/tcp >/dev/null 2>&1
    echo "Port $SSHPort/tcp is now allowed in UFW..."
fi

for service in "${RestartService[@]}"; do
    manage_service restart "$service"
done

echo "Finished"
echo "If you disconnect and then connect to this session again you need to change your SSH port in the connection to $SSHPort"

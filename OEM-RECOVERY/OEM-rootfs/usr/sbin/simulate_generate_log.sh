#!/bin/sh
# Check the number of arguments
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <argument>"
    exit 1
fi

# Function to generate dummy log entries
generate_dummy_logs() {
    # Number of log entries to create
    log_entries=100000
    # Loop to generate dummy log entries
    count=0
    # Define the log message
    case $1 in
        "messages")
            log_message="Dummy log entry-----------------------------------------------------------"
            ;;
        "wifi")
            log_message="WIFI Dummy log entry-----------------------------------------------------------"
            ;;
        "mesh")
            log_message="[MESH] Dummy log entry-----------------------------------------------------------"
            ;;
        *)
            echo "Invalid argument: $1"
            exit 1
            ;;
    esac
    
    while [ $count -lt $log_entries ]; do
        message="$log_message $count"
        logger "$message"
        # echo "Logged: $message"
        count=$((count + 1))
    done
    # echo "Finished logging $log_entries entries."
}   

while true; do
    if [[ $1 == "all" ]]; then
        generate_dummy_logs "messages"   
        sleep 1
        generate_dummy_logs "mesh"   
        sleep 1
        generate_dummy_logs "wifi"   
        sleep 1
    else
        generate_dummy_logs "$1"   
        sleep 1
    fi
done
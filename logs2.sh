#!/bin/bash

# Parent directory name
parent_dir="k8s-logs-$(date +"%Y-%m-%d_%H-%M-%S")"

# Function to count lines in a pod's log
count_lines_in_log() {
    local pod_name="$1"
    local namespace="$2"
    local log_count=$(kubectl logs "$pod_name" -n "$namespace" | wc -l)
    echo "Pod: $pod_name, Line Count: $log_count"
}

# Function to list running pods and count lines in their logs
list_and_count_pods() {
    local namespace="$1"
    local pods=($(kubectl get pods -n "$namespace" --output=jsonpath="{.items[*].metadata.name}"))

    for pod in "${pods[@]}"; do
        count_lines_in_log "$pod" "$namespace"
    done
}

# Function to extract and store pod logs in a directory
extract_and_store_logs() {
    local namespace="$1"
    local log_dir="$2"

    # Create the log directory if it doesn't exist
    mkdir -p "$log_dir"

    local pods=($(kubectl get pods -n "$namespace" --output=jsonpath="{.items[*].metadata.name}"))

    # Extract and store the logs for each pod
    for pod in "${pods[@]}"; do
        kubectl logs "$pod" -n "$namespace" > "$log_dir/$pod.log"
    done
}

# Function to compare and extract the difference in logs
final() {
    local namespace="$1"
    local start_dir="$2/start/$namespace"
    local end_dir="$2/end/$namespace"
    local final_dir="$2/final/$namespace"

    # Create the final directory if it doesn't exist
    mkdir -p "$final_dir"

    # Compare and extract the difference in log lines
    pods=($(kubectl get pods -n "$namespace" --output=jsonpath="{.items[*].metadata.name}"))
    for pod in "${pods[@]}"; do
        start_log="$start_dir/$pod.log"
        end_log="$end_dir/$pod.log"
        final_log="$final_dir/$pod.log"

        # Use tail to get new log lines in the 'end' log that are not in the 'start' log
        tail -n +"$(($(wc -l < "$start_log") + 1))" "$end_log" > "$final_log"
    done
}

# Function to validate kubectl cluster-info
validate_kubectl_cluster_info() {
    if ! validate_kubectl_fetch "cluster-info"; then
        echo "Failed to check K8s cluster with kubectl. Exiting."
        exit 1
    fi
}

# Function to check the status of a kubectl command
validate_kubectl_fetch() {
    local command="$1"

    # Run the kubectl command and capture the exit status
    if output=$(kubectl $command 2>&1); then
        echo "kubectl $command executed successfully"
        echo "$output"
        return 0
    else
        echo "Error executing kubectl $command"
        echo "$output"
        return 1
    fi
}

clear
# Validate kubectl cluster-info
validate_kubectl_cluster_info
sleep 2

# Create the parent directory
base_dir="/tmp/$parent_dir"
mkdir -p "$base_dir"

# Create a systeminfo directory to store system information
systeminfo_dir="$base_dir/systeminfo"
mkdir -p "$systeminfo_dir"

# Collect system information at the start
kubectl get nodes > "$systeminfo_dir/nodes.txt"
kubectl describe nodes > "$systeminfo_dir/nodes_describe.txt"
kubectl top nodes > "$systeminfo_dir/top_nodes.txt"
kubectl top pods -A > "$systeminfo_dir/top_pods.txt"
kubectl describe pods -n cattle-system -n ingress-nginx -n cattle-fleet-local-system -n cattle-fleet-system -n cert-manager -n kube-system > "$systeminfo_dir/describe_pods.txt"

# List of namespaces to monitor
namespaces=("cattle-system" "ingress-nginx" "cattle-fleet-local-system" "cattle-fleet-system" "cert-manager" "kube-system" "fleet-default")

# Create subdirectories for each namespace in the "start" directory
for namespace in "${namespaces[@]}"; do
    namespace_dir_start="$base_dir/start/$namespace"
    mkdir -p "$namespace_dir_start"
done

# Request line counts for the first time
clear
echo "Initial Line Counts:"
for namespace in "${namespaces[@]}"; do
    list_and_count_pods "$namespace"
    extract_and_store_logs "$namespace" "$base_dir/start/$namespace"
done

read -p "Press Enter to refresh line counts and store logs..."

# Create a new set of directories for the second print in the "end" directory
for namespace in "${namespaces[@]}"; do
    namespace_dir_end="$base_dir/end/$namespace"
    mkdir -p "$namespace_dir_end"
done

echo ; echo ; echo
echo "Updated Line Counts:"
for namespace in "${namespaces[@]}"; do
    list_and_count_pods "$namespace"
    extract_and_store_logs "$namespace" "$base_dir/end/$namespace"
done

# Collect system information at the end
kubectl get nodes > "$systeminfo_dir/nodes_end.txt"
kubectl describe nodes > "$systeminfo_dir/nodes_describe_end.txt"
kubectl top nodes > "$systeminfo_dir/top_nodes_end.txt"
kubectl top pods -A > "$systeminfo_dir/top_pods_end.txt"
kubectl describe pods -n cattle-system -n ingress-nginx -n cattle-fleet-local-system -n cattle-fleet-system -n cert-manager -n kube-system -n fleet-default > "$systeminfo_dir/describe_pods_end.txt"

read -p "Press Enter to exit..."

# Call the 'final' function to compare and extract the difference in logs for each namespace
for namespace in "${namespaces[@]}"; do
    final "$namespace" "$base_dir"
done
echo; echo; echo;
tar cvzf /tmp/$parent_dir.tgz $base_dir/*
echo
echo
echo "Upload file /tmp/$parent_dir.tgz"
echo
echo "Check data in $base_dir"

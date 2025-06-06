#!/bin/bash

# Storage Configuration Management
# Handles various storage solutions for Pi clusters

# Storage solution options
STORAGE_SOLUTIONS=("glusterfs" "nfs" "longhorn" "local")

# Configuration variables with defaults
STORAGE_SOLUTION="${STORAGE_SOLUTION:-glusterfs}"
STORAGE_DEVICE="${STORAGE_DEVICE:-auto}"  # auto-detect or specify like /dev/sda1
STORAGE_SIZE_MIN="${STORAGE_SIZE_MIN:-100}"  # Minimum storage size in GB
SHARED_STORAGE_PATH="${SHARED_STORAGE_PATH:-/mnt/shared-storage}"
DOCKER_STORAGE_PATH="${DOCKER_STORAGE_PATH:-/mnt/shared-storage/docker-volumes}"

# Function to detect available storage devices
detect_storage_devices() {
    local pi_ip="$1"
    
    ssh_exec "$pi_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
        # Look for storage devices that are likely SSDs
        # Common SSD sizes: 120GB, 240GB, 250GB, 256GB, 480GB, 500GB, 512GB, 1TB, 2TB
        lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk | while read -r line; do
            device_name=\$(echo \"\$line\" | awk '{print \$1}')
            device_size=\$(echo \"\$line\" | awk '{print \$2}')
            mount_point=\$(echo \"\$line\" | awk '{print \$4}')
            
            # Skip if already mounted to root or boot
            if [[ \"\$mount_point\" == \"/\" || \"\$mount_point\" == \"/boot\"* ]]; then
                continue
            fi
            
            # Check if size indicates it's likely an SSD
            if echo \"\$device_size\" | grep -qE '(1[2-9][0-9]|2[4-9][0-9]|[3-9][0-9][0-9]|[1-9]T)G'; then
                echo \"/dev/\$device_name:\$device_size\"
            fi
        done
    "
}

# Function to setup storage based on selected solution
setup_cluster_storage() {
    local pi_ips=("$@")
    
    log INFO "🗄️  Setting up cluster storage solution: $STORAGE_SOLUTION"
    
    case "$STORAGE_SOLUTION" in
        "glusterfs")
            setup_glusterfs_storage "${pi_ips[@]}"
            ;;
        "nfs")
            setup_nfs_storage "${pi_ips[@]}"
            ;;
        "longhorn")
            setup_longhorn_storage "${pi_ips[@]}"
            ;;
        "local")
            setup_local_storage "${pi_ips[@]}"
            ;;
        *)
            log ERROR "Unknown storage solution: $STORAGE_SOLUTION"
            return 1
            ;;
    esac
}

# Function to setup NFS storage (simpler alternative)
setup_nfs_storage() {
    local pi_ips=("$@")
    local nfs_server="${pi_ips[0]}"  # Use first Pi as NFS server
    local export_path="${STORAGE_MOUNT_POINT:-/mnt/nfs-storage}"
    
    log INFO "🗄️  Setting up NFS storage with $nfs_server as server"
    
    # Setup NFS server on first Pi
    log INFO "  Setting up NFS server on $nfs_server..."
    ssh_exec "$nfs_server" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
        # Install NFS server
        sudo apt-get update -qq
        sudo apt-get install -y nfs-kernel-server
        
        # Prepare storage device
        if [[ '$STORAGE_DEVICE' == 'auto' ]]; then
            STORAGE_DEVICE=\$(lsblk -d -o NAME,SIZE,TYPE | grep disk | grep -E '(250|240|256).*G' | head -n1 | awk '{print \"/dev/\" \$1}')
        else
            STORAGE_DEVICE='$STORAGE_DEVICE'
        fi
        
        if [[ -n \"\$STORAGE_DEVICE\" ]]; then
            # Create filesystem if needed
            if ! blkid \$STORAGE_DEVICE | grep -q ext4; then
                sudo mkfs.ext4 -F \$STORAGE_DEVICE
            fi
            
            # Mount storage
            sudo mkdir -p '$export_path'
            if ! grep -q \$STORAGE_DEVICE /etc/fstab; then
                echo \"\$STORAGE_DEVICE $export_path ext4 defaults 0 2\" | sudo tee -a /etc/fstab
            fi
            sudo mount '$export_path' 2>/dev/null || sudo mount \$STORAGE_DEVICE '$export_path'
        else
            sudo mkdir -p '$export_path'
        fi
        
        # Configure NFS export
        if ! grep -q '$export_path' /etc/exports; then
            echo '$export_path *(rw,sync,no_subtree_check,no_root_squash)' | sudo tee -a /etc/exports
        fi
        
        # Restart NFS services
        sudo exportfs -ra
        sudo systemctl restart nfs-kernel-server
        sudo systemctl enable nfs-kernel-server
        
        echo 'NFS server setup completed'
    "
    
    # Setup NFS clients on all Pis
    for pi_ip in "${pi_ips[@]}"; do
        log INFO "  Setting up NFS client on $pi_ip..."
        ssh_exec "$pi_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            # Install NFS client
            sudo apt-get install -y nfs-common
            
            # Create mount point
            sudo mkdir -p '$SHARED_STORAGE_PATH'
            
            # Add to fstab
            if ! grep -q '$nfs_server:$export_path' /etc/fstab; then
                echo '$nfs_server:$export_path $SHARED_STORAGE_PATH nfs defaults 0 0' | sudo tee -a /etc/fstab
            fi
            
            # Mount NFS share
            sudo mount '$SHARED_STORAGE_PATH' 2>/dev/null || sudo mount '$nfs_server:$export_path' '$SHARED_STORAGE_PATH'
            
            # Create Docker directories
            sudo mkdir -p '$SHARED_STORAGE_PATH/docker-volumes'
            sudo chown -R 1000:1000 '$SHARED_STORAGE_PATH/docker-volumes'
            
            echo 'NFS client setup completed on $pi_ip'
        "
    done
    
    log INFO "✅ NFS storage setup completed!"
}

# Function to setup Longhorn distributed storage (Kubernetes-based)
setup_longhorn_storage() {
    local pi_ips=("$@")
    
    log INFO "🗄️  Setting up Longhorn distributed storage"
    log WARN "   Note: Longhorn requires Kubernetes. Ensure your cluster uses Kubernetes instead of Docker Swarm."
    
    # This would require Kubernetes to be set up first
    # Implementation would go here for Kubernetes + Longhorn setup
    log INFO "  Longhorn setup requires Kubernetes - this is a placeholder for future implementation"
    
    return 0
}

# Function to setup local storage on each node
setup_local_storage() {
    local pi_ips=("$@")
    
    log INFO "🗄️  Setting up local storage on each Pi node"
    
    for pi_ip in "${pi_ips[@]}"; do
        log INFO "  Setting up local storage on $pi_ip..."
        ssh_exec "$pi_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            # Detect or use specified storage device
            if [[ '$STORAGE_DEVICE' == 'auto' ]]; then
                STORAGE_DEVICE=\$(lsblk -d -o NAME,SIZE,TYPE | grep disk | grep -E '(250|240|256).*G' | head -n1 | awk '{print \"/dev/\" \$1}')
            else
                STORAGE_DEVICE='$STORAGE_DEVICE'
            fi
            
            if [[ -n \"\$STORAGE_DEVICE\" ]]; then
                # Create filesystem if needed
                if ! blkid \$STORAGE_DEVICE | grep -q ext4; then
                    sudo mkfs.ext4 -F \$STORAGE_DEVICE
                fi
                
                # Mount storage
                sudo mkdir -p '/mnt/local-storage'
                if ! grep -q \$STORAGE_DEVICE /etc/fstab; then
                    echo \"\$STORAGE_DEVICE /mnt/local-storage ext4 defaults 0 2\" | sudo tee -a /etc/fstab
                fi
                sudo mount '/mnt/local-storage' 2>/dev/null || sudo mount \$STORAGE_DEVICE '/mnt/local-storage'
                
                # Create Docker directories
                sudo mkdir -p '/mnt/local-storage/docker-volumes'
                sudo mkdir -p '/mnt/local-storage/docker-data'
                sudo chown -R 1000:1000 '/mnt/local-storage/docker-volumes'
                
                echo 'Local storage setup completed on $pi_ip'
            else
                echo 'Warning: No suitable storage device found on $pi_ip'
            fi
        "
    done
    
    log INFO "✅ Local storage setup completed!"
}

# Function to setup GlusterFS storage (distributed filesystem)
setup_glusterfs_storage() {
    local pi_ips=("$@")
    local volume_name="piswarm-volume"
    local brick_path="/data/glusterfs/brick"
    
    log INFO "  Setting up GlusterFS cluster with ${#pi_ips[@]} nodes..."
    
    # Install GlusterFS on all Pis
    for pi_ip in "${pi_ips[@]}"; do
        log INFO "  Installing GlusterFS on $pi_ip..."
        ssh_exec "$pi_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            # Update package list
            sudo apt-get update -qq
            
            # Install GlusterFS server
            if ! dpkg -l | grep -q glusterfs-server; then
                sudo apt-get install -y glusterfs-server
            fi
            
            # Start and enable GlusterFS daemon
            sudo systemctl start glusterd
            sudo systemctl enable glusterd
            
            # Prepare storage device
            if [[ '$STORAGE_DEVICE' == 'auto' ]]; then
                STORAGE_DEVICE=\$(lsblk -d -o NAME,SIZE,TYPE | grep disk | grep -E '(250|240|256).*G' | head -n1 | awk '{print \"/dev/\" \$1}')
            else
                STORAGE_DEVICE='$STORAGE_DEVICE'
            fi
            
            # Create brick directory
            sudo mkdir -p '$brick_path'
            
            if [[ -n \"\$STORAGE_DEVICE\" ]]; then
                # Create filesystem if needed
                if ! blkid \$STORAGE_DEVICE | grep -q ext4; then
                    sudo mkfs.ext4 -F \$STORAGE_DEVICE
                fi
                
                # Mount storage device
                if ! grep -q \$STORAGE_DEVICE /etc/fstab; then
                    echo \"\$STORAGE_DEVICE $brick_path ext4 defaults 0 2\" | sudo tee -a /etc/fstab
                fi
                sudo mount '$brick_path' 2>/dev/null || sudo mount \$STORAGE_DEVICE '$brick_path'
            fi
            
            # Set proper permissions
            sudo chown -R root:root '$brick_path'
            sudo chmod 755 '$brick_path'
            
            echo 'GlusterFS server setup completed on $pi_ip'
        "
    done
    
    # Peer probe all nodes (create trusted pool)
    local first_node="${pi_ips[0]}"
    for pi_ip in "${pi_ips[@]:1}"; do
        log INFO "  Adding peer $pi_ip to GlusterFS cluster..."
        ssh_exec "$first_node" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            sudo gluster peer probe $pi_ip
        "
    done
    
    # Wait for peers to be connected
    sleep 5
    
    # Create volume
    log INFO "  Creating GlusterFS volume '$volume_name'..."
    local brick_list=""
    for pi_ip in "${pi_ips[@]}"; do
        brick_list="$brick_list $pi_ip:$brick_path/vol"
    done
    
    ssh_exec "$first_node" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
        # Create brick directories
        for pi_ip in ${pi_ips[@]}; do
            ssh \$pi_ip 'sudo mkdir -p $brick_path/vol'
        done
        
        # Create distributed volume
        if ! sudo gluster volume info $volume_name &>/dev/null; then
            sudo gluster volume create $volume_name replica 1 $brick_list force
            sudo gluster volume start $volume_name
        fi
        
        # Configure volume settings for performance
        sudo gluster volume set $volume_name auth.allow '*'
        sudo gluster volume set $volume_name performance.cache-size 256MB
        sudo gluster volume set $volume_name network.ping-timeout 30
    "
    
    # Mount volume on all nodes
    for pi_ip in "${pi_ips[@]}"; do
        log INFO "  Mounting GlusterFS volume on $pi_ip..."
        ssh_exec "$pi_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            # Install GlusterFS client
            if ! dpkg -l | grep -q glusterfs-client; then
                sudo apt-get install -y glusterfs-client
            fi
            
            # Create mount point
            sudo mkdir -p '$SHARED_STORAGE_PATH'
            sudo mkdir -p '$DOCKER_STORAGE_PATH'
            
            # Mount the volume
            if ! mount | grep -q '$SHARED_STORAGE_PATH'; then
                sudo mount -t glusterfs localhost:/$volume_name '$SHARED_STORAGE_PATH'
            fi
            
            # Add to fstab for persistence
            if ! grep -q '$volume_name' /etc/fstab; then
                echo 'localhost:/$volume_name $SHARED_STORAGE_PATH glusterfs defaults,_netdev 0 0' | sudo tee -a /etc/fstab
            fi
            
            # Create Docker volume directory
            sudo mkdir -p '$DOCKER_STORAGE_PATH'
            sudo chown -R 1000:1000 '$SHARED_STORAGE_PATH'
        "
    done
    
    log INFO "  GlusterFS cluster setup completed!"
}

# Function to validate storage setup
validate_storage_setup() {
    local pi_ips=("$@")
    
    log INFO "🔍 Validating storage setup across cluster..."
    
    for pi_ip in "${pi_ips[@]}"; do
        log INFO "  Checking storage on $pi_ip..."
        ssh_exec "$pi_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            echo '=== Storage Status on $pi_ip ==='
            
            # Check mount points
            echo 'Mount points:'
            df -h | grep -E '(shared-storage|local-storage|gluster)'
            
            echo
            echo 'Storage test:'
            # Test write/read to shared storage
            if [[ -d '$SHARED_STORAGE_PATH' ]]; then
                echo 'Testing shared storage...'
                echo 'Test from $pi_ip at \$(date)' > '$SHARED_STORAGE_PATH/test-$pi_ip.txt'
                if [[ -f '$SHARED_STORAGE_PATH/test-$pi_ip.txt' ]]; then
                    echo '✅ Shared storage write test passed'
                else
                    echo '❌ Shared storage write test failed'
                fi
            fi
            
            echo '=========================='
        "
    done
}

# Interactive storage configuration
configure_storage_interactive() {
    echo ""
    echo "🗄️  Storage Configuration"
    echo "========================="
    echo "Your Pi cluster can benefit from shared storage using the SSDs."
    echo ""
    echo "Available storage solutions:"
    echo "1. GlusterFS (Recommended) - Distributed, replicated storage"
    echo "2. NFS - Simple shared storage with one server"
    echo "3. Local Storage - Individual storage on each Pi"
    echo "4. Skip storage setup"
    echo ""
    
    while true; do
        read -p "Select storage solution (1-4): " storage_choice
        case $storage_choice in
            1)
                STORAGE_SOLUTION="glusterfs"
                echo "✅ GlusterFS selected - provides distributed, fault-tolerant storage"
                break
                ;;
            2)
                STORAGE_SOLUTION="nfs"
                echo "✅ NFS selected - simple shared storage solution"
                break
                ;;
            3)
                STORAGE_SOLUTION="local"
                echo "✅ Local storage selected - individual storage per Pi"
                break
                ;;
            4)
                STORAGE_SOLUTION="skip"
                echo "⚠️ Storage setup will be skipped"
                return 0
                ;;
            *)
                echo "❌ Invalid choice. Please enter 1-4."
                ;;
        esac
    done
    
    if [[ "$STORAGE_SOLUTION" != "skip" ]]; then
        echo ""
        echo "Storage device configuration:"
        echo "1. Auto-detect SSD (recommended)"
        echo "2. Specify device path (e.g., /dev/sda1)"
        
        while true; do
            read -p "Select device option (1-2): " device_choice
            case $device_choice in
                1)
                    STORAGE_DEVICE="auto"
                    echo "✅ Will auto-detect SSD devices"
                    break
                    ;;
                2)
                    read -p "Enter device path (e.g., /dev/sda1): " STORAGE_DEVICE
                    if [[ -n "$STORAGE_DEVICE" ]]; then
                        echo "✅ Will use device: $STORAGE_DEVICE"
                        break
                    else
                        echo "❌ Device path cannot be empty"
                    fi
                    ;;
                *)
                    echo "❌ Invalid choice. Please enter 1 or 2."
                    ;;
            esac
        done
    fi
    
    # Export storage configuration
    export STORAGE_SOLUTION
    export STORAGE_DEVICE
    export SHARED_STORAGE_PATH
    export DOCKER_STORAGE_PATH
}

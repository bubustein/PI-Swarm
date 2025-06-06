#!/bin/bash

# GlusterFS Distributed Storage Setup for Pi Cluster
# This script sets up GlusterFS to utilize SSDs on each Pi for shared storage

setup_glusterfs_storage() {
    local pi_ips=("$@")
    local storage_device="${STORAGE_DEVICE:-/dev/sda1}"  # Default SSD device
    local mount_point="${STORAGE_MOUNT_POINT:-/mnt/gluster-storage}"
    local volume_name="${GLUSTER_VOLUME_NAME:-pi-cluster-storage}"
    local replica_count="${GLUSTER_REPLICA_COUNT:-3}"
    
    log INFO "🗄️  Setting up GlusterFS distributed storage across ${#pi_ips[@]} nodes"
    log INFO "   Storage device: $storage_device"
    log INFO "   Mount point: $mount_point"
    log INFO "   Volume name: $volume_name"
    log INFO "   Replica count: $replica_count"
    
    # Phase 1: Install GlusterFS on all nodes
    log INFO "Phase 1: Installing GlusterFS on all Pi nodes..."
    for pi_ip in "${pi_ips[@]}"; do
        log INFO "  Installing GlusterFS on $pi_ip..."
        if ! ssh_exec "$pi_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            # Update package lists
            sudo apt-get update -qq
            
            # Install GlusterFS server and client
            sudo apt-get install -y glusterfs-server glusterfs-client
            
            # Start and enable GlusterFS daemon
            sudo systemctl start glusterd
            sudo systemctl enable glusterd
            
            echo 'GlusterFS installation completed'
        "; then
            log ERROR "Failed to install GlusterFS on $pi_ip"
            return 1
        fi
        log INFO "  ✅ GlusterFS installed on $pi_ip"
    done
    
    # Phase 2: Prepare storage devices
    log INFO "Phase 2: Preparing storage devices on all nodes..."
    for pi_ip in "${pi_ips[@]}"; do
        log INFO "  Preparing storage on $pi_ip..."
        if ! ssh_exec "$pi_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            # Check if storage device exists
            if [[ '$storage_device' == 'auto' ]] || [[ ! -b '$storage_device' ]]; then
                echo 'Auto-detecting storage device...'
                # Look for SSDs around 250GB (could be 240GB, 250GB, 256GB, etc.)
                SSD_DEVICE=\$(lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk | while read -r line; do
                    device_name=\$(echo \"\$line\" | awk '{print \$1}')
                    device_size=\$(echo \"\$line\" | awk '{print \$2}')
                    mount_point=\$(echo \"\$line\" | awk '{print \$4}')
                    
                    # Skip if already mounted to root or boot
                    if [[ \"\$mount_point\" == \"/\" ]] || [[ \"\$mount_point\" == \"/boot\"* ]]; then
                        continue
                    fi
                    
                    # Check for common SSD sizes around 250GB
                    if echo \"\$device_size\" | grep -qE '(2[2-6][0-9]G|25[0-6]G)'; then
                        echo \"/dev/\$device_name\"
                        break
                    fi
                done)
                
                if [[ -n \"\$SSD_DEVICE\" ]]; then
                    echo \"Auto-detected SSD: \$SSD_DEVICE\"
                    STORAGE_DEVICE=\"\$SSD_DEVICE\"
                else
                    echo 'No suitable 250GB SSD found. Checking for any additional storage...'
                    # Fallback: look for any non-root storage device
                    FALLBACK_DEVICE=\$(lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk | while read -r line; do
                        device_name=\$(echo \"\$line\" | awk '{print \$1}')
                        mount_point=\$(echo \"\$line\" | awk '{print \$4}')
                        
                        if [[ \"\$mount_point\" != \"/\" ]] && [[ \"\$mount_point\" != \"/boot\"* ]]; then
                            echo \"/dev/\$device_name\"
                            break
                        fi
                    done)
                    
                    if [[ -n \"\$FALLBACK_DEVICE\" ]]; then
                        echo \"Using fallback storage device: \$FALLBACK_DEVICE\"
                        STORAGE_DEVICE=\"\$FALLBACK_DEVICE\"
                    else
                        echo 'No suitable storage device found. Please check your SSD installation.'
                        echo 'Available devices:'
                        lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT
                        exit 1
                    fi
                fi
            else
                STORAGE_DEVICE='$storage_device'
            fi
            
            # Create filesystem if not exists
            if ! blkid \$STORAGE_DEVICE | grep -q ext4; then
                echo 'Creating ext4 filesystem on '\$STORAGE_DEVICE
                sudo mkfs.ext4 -F \$STORAGE_DEVICE
            fi
            
            # Create mount point
            sudo mkdir -p '$mount_point'
            
            # Add to fstab if not already present
            if ! grep -q \$STORAGE_DEVICE /etc/fstab; then
                echo \"\$STORAGE_DEVICE $mount_point ext4 defaults 0 2\" | sudo tee -a /etc/fstab
            fi
            
            # Mount the device
            sudo mount '$mount_point' 2>/dev/null || sudo mount \$STORAGE_DEVICE '$mount_point'
            
            # Create GlusterFS brick directory with proper permissions
            sudo mkdir -p '$mount_point/brick'
            
            # Create directory for Docker volumes on the shared storage
            sudo mkdir -p '$mount_point/docker-volumes'
            
            # Set proper ownership and permissions
            if id gluster >/dev/null 2>&1; then
                sudo chown -R gluster:gluster '$mount_point/brick'
            else
                # If gluster user doesn't exist yet, set reasonable permissions
                sudo chmod 755 '$mount_point/brick'
            fi
            
            # Make Docker volumes directory accessible
            sudo chmod 755 '$mount_point/docker-volumes'
            
            # Verify mount is successful
            if mountpoint -q '$mount_point'; then
                echo \"✅ Storage successfully mounted at $mount_point\"
                df -h '$mount_point'
            else
                echo \"❌ Failed to mount storage at $mount_point\"
                exit 1
            fi
            
            echo 'Storage preparation completed'
        "; then
            log ERROR "Failed to prepare storage on $pi_ip"
            return 1
        fi
        log INFO "  ✅ Storage prepared on $pi_ip"
    done
    
    # Phase 3: Configure GlusterFS cluster
    log INFO "Phase 3: Configuring GlusterFS cluster..."
    
    # Use first Pi as the primary node for cluster setup
    local primary_pi="${pi_ips[0]}"
    log INFO "  Using $primary_pi as primary node for cluster setup"
    
    # Add peer nodes to the cluster
    if ! ssh_exec "$primary_pi" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
        # Add all other nodes as peers
        for peer_ip in ${pi_ips[@]:1}; do
            echo \"Adding peer: \$peer_ip\"
            sudo gluster peer probe \$peer_ip
            sleep 2
        done
        
        # Wait for peers to be connected
        sleep 5
        
        # Check peer status
        sudo gluster peer status
        
        echo 'Cluster peering completed'
    "; then
        log ERROR "Failed to configure GlusterFS cluster"
        return 1
    fi
    
    # Phase 4: Create distributed volume
    log INFO "Phase 4: Creating GlusterFS distributed volume..."
    
    # Build brick list
    local brick_list=""
    for pi_ip in "${pi_ips[@]}"; do
        brick_list+="${pi_ip}:${mount_point}/brick "
    done
    
    if ! ssh_exec "$primary_pi" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
        # Create the volume
        echo 'Creating GlusterFS volume: $volume_name'
        echo 'Brick list: $brick_list'
        
        # Determine volume type based on number of nodes
        if [[ ${#pi_ips[@]} -ge 3 ]]; then
            # Create replicated volume for redundancy
            sudo gluster volume create '$volume_name' replica $replica_count $brick_list force
        else
            # Create distributed volume
            sudo gluster volume create '$volume_name' $brick_list force
        fi
        
        # Start the volume
        sudo gluster volume start '$volume_name'
        
        # Set volume options for optimization
        sudo gluster volume set '$volume_name' auth.allow '*'
        sudo gluster volume set '$volume_name' nfs.disable on
        sudo gluster volume set '$volume_name' performance.cache-size 256MB
        
        # Show volume info
        sudo gluster volume info '$volume_name'
        
        echo 'GlusterFS volume created and started'
    "; then
        log ERROR "Failed to create GlusterFS volume"
        return 1
    fi
    
    # Phase 5: Mount volume on all nodes
    log INFO "Phase 5: Mounting GlusterFS volume on all nodes..."
    
    local client_mount="/mnt/shared-storage"
    
    for pi_ip in "${pi_ips[@]}"; do
        log INFO "  Mounting shared storage on $pi_ip..."
        if ! ssh_exec "$pi_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            # Install GlusterFS client if not already installed
            sudo apt-get install -y glusterfs-client
            
            # Create client mount point
            sudo mkdir -p '$client_mount'
            
            # Add to fstab for persistent mounting
            if ! grep -q '$volume_name' /etc/fstab; then
                echo 'localhost:/$volume_name $client_mount glusterfs defaults,_netdev 0 0' | sudo tee -a /etc/fstab
            fi
            
            # Mount the volume
            sudo mount -t glusterfs localhost:/$volume_name '$client_mount'
            
            # Set permissions
            sudo chmod 755 '$client_mount'
            
            # Test write access
            echo 'GlusterFS test from $pi_ip at \$(date)' | sudo tee '$client_mount/test-$pi_ip.txt'
            
            echo 'Client mount completed on $pi_ip'
        "; then
            log WARN "Failed to mount GlusterFS volume on $pi_ip (non-fatal)"
        else
            log INFO "  ✅ Shared storage mounted on $pi_ip at $client_mount"
        fi
    done
    
    # Phase 6: Configure Docker to use shared storage
    log INFO "Phase 6: Configuring Docker for shared storage..."
    
    for pi_ip in "${pi_ips[@]}"; do
        if ! ssh_exec "$pi_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            # Create Docker shared storage directories
            sudo mkdir -p '$client_mount/docker-volumes'
            sudo mkdir -p '$client_mount/docker-data'
            
            # Set proper permissions
            sudo chown -R 1000:1000 '$client_mount/docker-volumes'
            
            echo 'Docker storage configuration completed'
        "; then
            log WARN "Failed to configure Docker storage on $pi_ip"
        fi
    done
    
    # Phase 5: Final configuration and exports
    log INFO "Phase 5: Finalizing storage configuration..."
    
    # Export storage paths for Docker configuration
    export SHARED_STORAGE_PATH="$client_mount"
    export DOCKER_STORAGE_PATH="$client_mount/docker-volumes"
    export GLUSTER_VOLUME_PATH="$client_mount"
    
    # Create configuration file for other scripts to source
    mkdir -p "$PROJECT_ROOT/data"
    cat > "$PROJECT_ROOT/data/storage-config.env" << EOF
# Generated GlusterFS storage configuration
STORAGE_SOLUTION="glusterfs"
SHARED_STORAGE_PATH="$client_mount"
DOCKER_STORAGE_PATH="$client_mount/docker-volumes"
GLUSTER_VOLUME_NAME="$volume_name"
GLUSTER_VOLUME_PATH="$client_mount"
STORAGE_CONFIGURED="true"
STORAGE_SETUP_DATE="$(date)"
EOF
    
    log INFO "✅ GlusterFS distributed storage setup completed!"
    log INFO ""
    log INFO "📊 Storage Summary:"
    log INFO "   • Volume name: $volume_name"
    log INFO "   • Mount point: $client_mount"
    log INFO "   • Total nodes: ${#pi_ips[@]}"
    log INFO "   • Replica count: $replica_count"
    log INFO "   • Docker volumes: $client_mount/docker-volumes"
    log INFO ""
    log INFO "💡 Usage examples:"
    log INFO "   • Access shared storage: ls $client_mount"
    log INFO "   • Create Docker volume: docker volume create --driver local --opt type=none --opt device=$client_mount/docker-volumes/myvolume --opt o=bind myvolume"
    log INFO "   • Check cluster status: sudo gluster peer status"
    log INFO "   • Check volume status: sudo gluster volume status"
    
    return 0
}

# Function to check storage requirements
check_storage_requirements() {
    local pi_ips=("$@")
    
    log INFO "🔍 Checking storage requirements on all Pi nodes..."
    
    for pi_ip in "${pi_ips[@]}"; do
        log INFO "  Checking storage on $pi_ip..."
        if ! ssh_exec "$pi_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            echo '=== Storage Information for $pi_ip ==='
            
            # List all block devices
            echo 'Block devices:'
            lsblk
            
            echo
            echo 'Storage devices with size:'
            lsblk -d -o NAME,SIZE,TYPE | grep disk
            
            echo
            echo 'Available space:'
            df -h
            
            # Look for SSDs (common sizes: 240GB, 250GB, 256GB, 500GB, 512GB, 1TB)
            SSD_DEVICES=\$(lsblk -d -o NAME,SIZE,TYPE | grep disk | grep -E '(240|250|256|500|512|1T).*G')
            if [[ -n \"\$SSD_DEVICES\" ]]; then
                echo
                echo 'Potential SSD devices found:'
                echo \"\$SSD_DEVICES\"
            else
                echo
                echo 'Warning: No obvious SSD devices found'
            fi
        "; then
            log WARN "Could not check storage on $pi_ip"
        fi
        echo
    done
}

# Function to remove GlusterFS setup (for cleanup)
remove_glusterfs_storage() {
    local pi_ips=("$@")
    local volume_name="${GLUSTER_VOLUME_NAME:-pi-cluster-storage}"
    
    log WARN "🗑️  Removing GlusterFS storage setup..."
    
    # Stop and delete volume
    local primary_pi="${pi_ips[0]}"
    ssh_exec "$primary_pi" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
        sudo gluster volume stop '$volume_name' force 2>/dev/null || true
        sudo gluster volume delete '$volume_name' 2>/dev/null || true
    "
    
    # Clean up on all nodes
    for pi_ip in "${pi_ips[@]}"; do
        ssh_exec "$pi_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            sudo umount /mnt/shared-storage 2>/dev/null || true
            sudo systemctl stop glusterd 2>/dev/null || true
            sudo systemctl disable glusterd 2>/dev/null || true
            sudo apt-get remove -y glusterfs-server glusterfs-client 2>/dev/null || true
        "
    done
    
    log INFO "✅ GlusterFS storage cleanup completed"
}

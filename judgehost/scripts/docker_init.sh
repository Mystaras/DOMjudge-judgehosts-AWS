#!/bin/bash -eu

echo $USER
# USER=admin

sudo apt-get update
sudo apt-get install ca-certificates curl gnupg lsb-release git jq -y

# Install docker
# sudo apt-get remove docker docker-engine docker.io containerd runc
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y
sudo groupadd -f docker
sudo usermod -aG docker $USER

# Install cgroups
sudo apt-get update
sudo apt install libcgroup-dev -y

# Modify and update grub
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=""/GRUB_CMDLINE_LINUX_DEFAULT="cgroup_enable=memory swapaccount=1 systemd.unified_cgroup_hierarchy=0"/g' /etc/default/grub
sudo update-grub

# Find the judge directory
JUDGE_DIR=/home/$USER/judgehost
echo "judgehost dir found at: $JUDGE_DIR"

# Make the scripts executable
chmod +x $JUDGE_DIR/scripts/docker_start.sh
# chmod +x $JUDGE_DIR/scripts/docker_stop.sh #Not used/required

# Add reboot task
# Run Startup script
echo "@reboot $JUDGE_DIR/scripts/docker_start.sh" >> cron_tmp
sudo -u $USER crontab cron_tmp
rm cron_tmp
sudo reboot
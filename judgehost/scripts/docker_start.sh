#!/bin/bash

# Force script to be parsed
{

# The judge id is the same as the VM id to make it easier to identify the coresponding VM
ec2_id=$(ec2-metadata -i)
ec2_id=${ec2_id:15}

s3_bucket=judgehost-src
judge_pw_secret=prod/judgehost/pw
region=eu-central-1

# Find the judge directory
judge_dir=$(find ~ -type d -name judgehost)
echo "judgehost dir found at: $judge_dir"

# Clean up if container was kept after shutdown
# Can be omited if you wish to keep the container assuming that durring poweroff the container was stoped. 
# Handling the stoping of a container can prove complicated
# as the poweroff signals are sent to docker prior to the execution of any termination script.
(docker rm $(docker ps --filter status=exited -q) || true)

# Sync source code in case of update
# This will also modify the curent script and behaviour can be undefined.
# Mitigated by forcing the entire script to be parsed before runing.
aws s3 sync s3://$s3_bucket /home/$USER/

# Sync judgehost pw in case it changed
printf -- $(aws secretsmanager get-secret-value \
                                --secret-id $judge_pw_secret \
                                --region $region \
                                --query SecretString \
                                --output text | jq .password | tr -d '"' | tr -d '\n') > $judge_dir/secrets/domjudge-mysql-pw-judgehost.secret

# Deploy container
(cd $judge_dir && JUDGE_ID=$ec2_id docker compose up -d)

# Ensure that the file isn't accessed later
[[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
}
#!/bin/bash 

region=eu-central-1 # Region to create bucket, should be the same as in the template

template=judge-hosts.yaml # Template file, path relative to script location
stack_name=JudgeHosts   # Name of the Cloud Formation stack

# Override Template variables here if needed.
## S3 & Secrets Manager
s3_bucket_name=judgehost-src   # s3 bucket name
secret_name=prod/judgehost/pw  # Judgehost password secret
## IAM
role_name=judgehost            # Judgehost IAM role name 
profile_name=judgehostProfile  # Judgehost IAM profile name
s3_bucket_policy_name=judgehostSrcRead # S3 bucket access policy
secret_policy_name=judgehostGetSecret  # Secret access policy name
## EC2
key_pair_name=judgehost-key    # Key pair name (ssh key)
launch_template_name=judgehostEC2Template  # Ec2 judgehost fleat template name
security_group_name=judgehostSecurityGroup # Judgehosts security group name
vm_image=ami-0a5b5c0ea66ec560d # Machine os (modify to the latest Debian)
vm_type=t3.micro               # Machine category/type

curr_dir=$(dirname  $(realpath $0)) # The directory of this script, used for relative paths

# Check that awscli is installed/enabled
aws_cli_version=$(aws --version 2>&1)
if [[ $aws_cli_version == *"command not found"* ]];
then
    printf "$aws_cli_version\n\nawscli not found.\n" 
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi
printf "Using: $aws_cli_version\n"

# Create s3 bucket for judge code
printf "\nCreating S3 bucket: $s3_bucket_name \n"
aws s3api create-bucket --bucket $s3_bucket_name \
                    --region $region \
                    --create-bucket-configuration LocationConstraint=$region \
                    --object-ownership BucketOwnerEnforced | jq .Location

# Upload source code code to s3 bucket
printf "\nUploading code to bucket\n"
aws s3 cp $curr_dir/../judgehost s3://$s3_bucket_name/judgehost --recursive

# Deploy cloud formation stack with 0 judges
printf "\nDeploying stack.\n"
deploy_stack=$(aws cloudformation deploy \
                    --stack-name $stack_name \
                    --template-file $curr_dir/$template \
                    --parameter-overrides TotalCapacity=0 OnDemandCapacity=0 SpotCapacity=0 \
                                BucketName=$s3_bucket_name SecretName=$secret_name \
                                RoleName=$role_name ProfileName=$profile_name \
                                BucketPolicy=$s3_bucket_policy_name SecretPolicy=$secret_policy_name \
                                LaunchTemplateName=$launch_template_name SecurityGroupName=$security_group_name KeyPairName=$key_pair_name \
                                MachineImage=$vm_image MachineType=$vm_type \
                    --capabilities CAPABILITY_NAMED_IAM \
                    --no-execute-changes | tail -n 1)

# Show description of the stack to be created
printf "Description: \n"
eval $deploy_stack | less

read -p "Create stack [Y/N]? " -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    printf "Aborting, cleaning up\n"
    aws s3 rb s3://$s3_bucket_name/ --region $region --force
    aws cloudformation delete-stack --stack-name $stack_name
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

# Validate and initialise stack
execute_change=$(sed "s/describe-change-set/execute-change-set/g" <<< $deploy_stack)
printf "Validating stack:\n$execute_change"
eval $execute_change

# Wit for stack deployment
printf "\nWaiting on stack $stack_name to be up...\n"
stack_status=$(aws cloudformation describe-stacks \
                    --stack-name $stack_name \
                    --query "Stacks[0].StackStatus")
                    
while [ $stack_status != \"CREATE_COMPLETE\" ]
do
    printf "\tStack $stack_name state is $stack_status, checking again in 30 seconds\n"
    sleep 30
    stack_status=$(aws cloudformation describe-stacks \
                    --stack-name $stack_name \
                    --query "Stacks[0].StackStatus")
done

printf "\nThe resources for the judgehosts are ready. By defauilt no judges are up as the password needs to be updated.\n\n"

judge_pw=$(aws secretsmanager get-secret-value \
                    --secret-id $secret_name \
                    --region $region \
                    --query SecretString --output text | jq .password | tr -d '"' | tr -d '\n')
printf "The judgehost password generated is: $judge_pw\nUpdate/Edit the judgehost user using the DOMjudge web interface (<dom_url>/jury/users/).\n\n"

printf "EC2 fleet ressources ready with 0 judgehosts. Refer to the README to see how to increase the number of judgehosts.\n"

# DOMjudge judgehosts on AWS using Docker

In this README you will find instructions on how to deploy judgehosts for DOMjudge using a CloudFormation stack on AWS.

## Requirements
- aws-cli/1.25.60 Python/3.8.10 botocore/1.27.59
    - [Login](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html) to able to use the CLI. The region we use is `eu-central-1`, the code might need to be modified if you wish to use a different region.
    - The reason we use aws-cli v1 is to be able to use a virtual-env but v2 should work as well.
    - The default region used is `eu-central-1`.
- [jq](https://manpages.ubuntu.com/manpages/xenial/man1/jq.1.html)


## Template
The [judge-host.yaml](cloudFormation/judge-hosts.yaml) template will create all the necessary resources for the judge-hosts and deploy and EC2Fleet of the specified number of judgehosts.

What is created?
- `SecretsManager::Secret`: store the judgehost password
- `S3 bucket`: contents of [./judgehosts](./judgehost/) which contains all the required code to setup and deploy the judgehosts
- `AWS::IAM::Role`: role for the judgehosts in order to access the `secret` and `S3 bucket`.
    - `IAM::InstanceProfile`: attach the role the judgehost VMs
    - `IAM::Policy` to access the secret
    - `IAM::Policy` to access the S3 bucket
- Resources to ssh to the judgehost VMs
    - `EC2::SecurityGroup`: Ingress port 22
    - `EC2::KeyPair`: Can be found in `Parameter Store`
- `EC2::EC2Fleet`: EC2 fleet with the judgehost VMs

## IAM Permission:
TODO:

## Configure deployment
1. Modify the `DOM_BASEURL` in [.env](./judgehost/.env) to the base url of your domserver.
2. (Optional) Modify the `Template variables` in the [deploy_judgehosts.sh](./cloudFormation/deploy_judgehosts.sh) script to the names you wish. You can leave the default but make sure there are no conflicts in the names with already existing resources.

## Deployment
Deploying the judgehost stack is as easy as running:
```console
$ chmod +x cloudFormation/deploy_judgehosts.sh
$ ./cloudFormation/deploy_judgehosts.sh
```
The script will ask you to validate the new CloudFormation stack to be created and will output the judgehost password generated that you will need to update on your domserver (`/jury/users/`). Creating the stack might take a few minutes, the script should give you the creation status of the stack every 30seconds.

If you wish to understand what the script is doing or wish to debug read [README_manual](./README_manual.md) for instructions on how to do a manual deployment.

When the script has ended you have successfully cerated all resources with 0 judgehosts. **Update the judgehost user on your domserver or update the secret itself to your already defined secret** 

Once the judgehost secret has been set on your domserver you can modify and run the bellow command to increase the number of judgehost to N `On Demand` VMs. **It is advised not to use `Spot` instances as if they get claimed while a judge is running a task DOMjudge will have a hard time recovering**
```console
$ aws cloudformation update-stack --stack-name JudgeHosts \
                            --use-previous-template \
                            --parameters ParameterKey=CapacityType,ParameterValue=on-demand \
                                            ParameterKey=TotalCapacity,ParameterValue=N \
                                            ParameterKey=OnDemandCapacity,ParameterValue=N \
                                            ParameterKey=SpotCapacity,ParameterValue=0 \
                            --capabilities CAPABILITY_NAMED_IAM 
```

The judge-host(s) should be available in your dom-server interface with 5-10 minutes. 

You can play with the template parameters to change the number of instances. **You do not need to change the template directly** just specify the `--parameters` flag like in the previous command or do it using the AWS console. 


## Starting/Stopping or Scaling-Down judgehost VMs
Upon creation of the judgehost VM, the [docker_start.sh](./judgehost/scripts/docker_start.sh) script is added to the startup of the VM using `crontab`. If you restart or power on a stopped judgehost VM, it will automatically re-connect to the server without you needing to do anything. 

If you terminate a judgehost VM, a new VM will be automatically created by the CloudFormation. If you wish to scale down the number of judgehosts. Either *safely* stop the specific VM if you plan on needing it again and don't mind the cost. Or, decrease the number of judges on the CloudFormation template. 

Keep in mind that:
- if you power off a judgehost VM the data of judge will be lost (see [docker_start.sh](./judgehost/scripts/docker_start.sh) comments)
- when downsizing there is no rule as to which VM will be claimed. Therefore a working judgehost could be claimed. TODO: Research if perhaps powered off instances are prioritized. 

##  Setting up ssh
Once you have deployed your judges you can fetch your ssh key using the AWS console in the `AWS Systems Manager/Parameter Store`. A wildcard ssh `.config` you can use to connect to your judgehosts is:
```ssh-config
Host ec2-*
    User admin
    Hostname %h.eu-central-1.compute.amazonaws.com
    IdentityFile ~/.ssh/judgehost_key.pem
```

## Cleanup or something when wrong when deploying

If the deployment crashes investigate what went wrong. If you wish to cleanup  due to a crash or when you are done. The following commands will clean all resources:

- Delete the cloud formation stack and all resources will be freed. The stack name is the variable in the [deploy_judgehosts.sh](./cloudFormation/deploy_judgehosts.sh) script.
- Delete the previously created bucket. The s3_bucket is the variable in the [deploy_judgehosts.sh](./cloudFormation/deploy_judgehosts.sh) script. 

```console
$ aws cloudformation delete-stack --stack-name $stack_name
$ aws s3 rb s3://$s3_bucket/ --region $region --force
```

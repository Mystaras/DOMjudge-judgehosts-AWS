# DOMjudge judgehosts on AWS using Docker

In this README you will find instructions on how to deploy judgehosts for DOMjudge using a Cloud Formation stack on AWS. The deployment is basic and does not include VPC configurations etc.

## Requirements
- aws-cli/1.25.60 Python/3.8.10 botocore/1.27.59
    - [Login](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html) to able to use the CLI. 
    - The default `eu-central-1`, see [Configure Deployment](README#configure-deployment) if you wish to modify.
    - The reason we use aws-cli v1 is to be able to use a virtual-env but v2 should work as well.
- [jq](https://manpages.ubuntu.com/manpages/xenial/man1/jq.1.html)


## Template
The [judge-host.yaml](cloud-formation/judge-hosts.yaml) template will create all the necessary resources for the judge-hosts and deploy and EC2Fleet of the specified number of judgehosts.

What is created?
- `SecretsManager::Secret`: secret for the judgehost password
- `S3 bucket`: contents of [./judgehosts](./judgehost/) which contains all the required code to setup and deploy the judgehosts
- `AWS::IAM::Role`: role for the judgehosts in order to access the `secret` and `S3 bucket`.
    - `IAM::InstanceProfile`: profile to attach the role the judgehost VMs
    - `IAM::Policy`: policies to access the secret and S3 bucket
- Resources to ssh to the judgehost VMs
    - `EC2::SecurityGroup`: Ingress port 22 (ssh)
    - `EC2::KeyPair`: ssh private key, can be found in `Parameter Store`
- `EC2::EC2Fleet`: EC2 fleet with the judgehost VMs

## IAM Permission:
TODO:

## Configure Deployment
1. Modify the `DOM_BASEURL` in [.env](./judgehost/.env) to the base url of your domserver.
2. (Optional) Modify the `Template variables` in the [deploy_judgehosts.sh](./cloud-formation/deploy_judgehosts.sh) script to the names you wish. You can leave the default but make sure there are no conflicts in the names with already existing resources.

## Deployment
Deploying the judgehost stack is as easy as running:
```bash
chmod +x ./cloud-formation/deploy_judgehosts.sh
./cloud-formation/deploy_judgehosts.sh
```
The script will prompt you to validate the new Cloud Formation stack to be created and will output the judgehost password generated that you will need to update on your domserver (`/jury/users/`). Creating the stack might take several minutes, the script should give you the creation status of the stack every 30 seconds.

If you wish to understand what the script is doing or wish to debug read [README_manual](./README_manual.md) for instructions on how to do a manual deployment.

When the script has ended you have successfully created all resources with 0 judgehosts. **Update the judgehost user password on your domserver or update the secret itself in the `AWS::SecretsManager`** 

Once the judgehost secret has been set on your domserver, you can modify (TotalCapacity, OnDemandCapacity) and run the bellow command to increase the number of judgehost to N `On Demand` VMs. **It is advised not to use `Spot` instances. As if they get claimed while a judge is running a task, DOMjudge will have a hard time recovering**.
```bash
aws cloudformation update-stack --stack-name JudgeHosts \
                            --use-previous-template \
                            --parameters ParameterKey=OnDemandCapacity,ParameterValue={N} \
                                        ParameterKey=TotalCapacity,ParameterValue={N} \
                            --capabilities CAPABILITY_NAMED_IAM 
```

The judgehost(s) should be available to your domserver interface within 5-10 minutes. As they need to install docker and other required packages. And download the [judgehost image](https://hub.docker.com/r/domjudge/judgehost/) and deploy. The judgehost ID is the `EC2 Instance ID` of the specific VM.

You can play with the template parameters to change the number of instances. **You do not need to change the template directly** just specify the `--parameters` flag like in the previous command or do it using the AWS console in `Cloud Formation`. 


## Starting/Stopping or Scaling-Down judgehost VMs
Upon creation of the judgehost VM, the [docker_init.sh](./judgehost/scripts/docker_init.sh) script is executed on the VM. It installs all required resources and adds the [docker_start.sh](./judgehost/scripts/docker_start.sh) script to the startup of the VM using `crontab`. If you restart or power-on a stopped judgehost VM, it will automatically re-connect to the defined server without requiring any action. 

If you terminate a judgehost VM, a new VM will be automatically supplied by the Cloud Formation stack. If you wish to scale down the number of judgehosts. Either *safely* stop the specific VM if you plan on using it again and don't mind the cost of a stopped instance. Or, decrease the number of judges on the Cloud Formation template. 

Keep in mind that:
- If you power-off a judgehost VM the data of judge will be lost (see [docker_start.sh](./judgehost/scripts/docker_start.sh) comments)
- When downsizing there is no rule as to which VM will be claimed. Therefore, a working judgehost could be claimed. TODO: Research if perhaps powered-off instances are prioritized. 

##  Setting up ssh
Once you have deployed your judgehosts, you can fetch your ssh key using the AWS console in the `AWS Systems Manager/Parameter Store` (Change the permission of the key, `600` or `400`). A wildcard ssh `.config` you can use to connect to your judgehosts is:
```ssh-config
Host ec2-*
    User admin
    Hostname %h.eu-central-1.compute.amazonaws.com
    IdentityFile ~/.ssh/judgehost_key.pem
```
And connect using the target instance's `public IPv4 DNS`:
```bash
$ ssh ec2-X-X-X-X
```

## Cleanup / Something when wrong when deploying

- If the deployment crashes investigate what went wrong in the Cloud Formation logs. 
- If the Cloud Formation stack get deployed but the judges never connect to the domserver. Something went wrong in the initialization scripts. Connect to the judge and check the user data log files:
    - `/var/log/cloud-init.log` 
    - `/var/log/cloud-init-output.log`


If you wish to cleanup due to a crash or terminate the judges. The following commands will clean all resources:

- Delete the cloud formation stack and all resources will be freed. The `stack_name` is the variable in the [deploy_judgehosts.sh](./cloud-formation/deploy_judgehosts.sh) script.
- Delete the previously created bucket. The `s3_bucket` and `region` are the variables in the [deploy_judgehosts.sh](./cloud-formation/deploy_judgehosts.sh) script. 

```bash
aws cloudformation delete-stack --stack-name $stack_name
aws s3 rb s3://$s3_bucket/ --region $region --force
```

### S3 bucket
The template requires an s3 bucket populated with the source code for the judge-hosts [judgehost/](./judgehost/). The reason it is not created using the template is the inability to populate it. If that becomes an option implement it!! 
Create a bucket named `judgehost-src`. This can be done by running the bellow cli commands.

```bash
# Create bucket
$ aws s3api create-bucket --bucket judgehost-src \
                    --region eu-central-1 \
                    --create-bucket-configuration LocationConstraint=eu-central-1 \
                    --object-ownership BucketOwnerEnforced

# Upload source code code
$ aws s3 cp ./judgehost s3://judgehost-src/judgehost --recursive
```

### Deployment
You need to create a CloudFormation stack using the [judge-host.yaml](./cloudFormation/judge-hosts.yaml) template. 

1. First deploy it with **zero instances**. You can do so by modifying `TotalCapacity`, `OnDemandCapacity`, `SpotCapacity` in the template parameters or specifying `--parameter-overrides` on CLI (see bellow). 

Then run:
```bash
$ aws cloudformation deploy --stack-name JudgeHosts \
                            --template-file ./cloudFormation/judge-hosts.yaml \
                            --parameter-overrides TotalCapacity=0 OnDemandCapacity=0 SpotCapacity=0 \
                            --capabilities CAPABILITY_NAMED_IAM \
                            --no-execute-changes
```

This will prompt you to review the changes by running:
```bash
$ aws cloudformation describe-change-set --change-set-name <ARN>
```

You can review them and the validate them by running:
```bash
$ aws cloudformation execute-change-set --change-set-name <ARN>
```

This might take some time (5-10 minutes). You can check the status of your stack by running:
```bash
$ aws cloudformation describe-stacks --stack-name JudgeHosts --query "Stacks[0].StackStatus"
```

Or by using the `aws console` in `CloudFormation`. You are ready when `StackStatus` is in state `CREATE_COMPLETE`. If something breaks check the logs.

2. Now that you have created all the resources, you need to fetch the secret that was created for the judges by the template. You can do that by running:
```bash
aws secretsmanager get-secret-value --secret-id prod/judgehost/pw --region eu-central-1 --query SecretString --output text | jq .password | tr -d '"' | tr -d '\n'
```
Or alternatively checking the aws console `Secret Manager` for the `prod/judgehost/pw` secret.

Now go on the dom-servers `<domurl>jury/users` and modify the judgehost password with the newly generated one.
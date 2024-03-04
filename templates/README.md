CloudFormation Template for practicing isucon

## Requirements
- Auth like IAM user who can create resource
- KeyPair for SSH
  - Please replace template's AWS::EC2::Instance's KeyName
```sh
% aws ec2 create-key-pair \
--key-name what_you_want \
--key-type ed25519 \
--key-format pem \
--query "KeyMaterial" \
--output text > what_you_want.pem \
--profile your_auth_user
```
- After that
```sh
% aws cloudformation deploy --template-file isucon.yml --stack-name STACK_NAME --profile your_auth_user`
```

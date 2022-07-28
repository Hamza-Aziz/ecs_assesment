you find here how to run this simple project 👍

add your aws keys to the project or make them as env variables :

  - `export AWS_ACCESS_KEY_ID = "ACCESS-KEY-ID "`
  - `export AWS_SECRET_ACCESS_KEY = "SECRET-ACCESS-KEY"`

to ecs exec to the container change <taskId>  by the task ID that you want to connect to, you can find the task id on the aws console!

    `aws ecs execute-command  \
    --region <AWS_REGION> \
    --cluster terraform-ecs-cluster \
    --task <taskId> \
    --container nginx \
    --command "/bin/bash" \
    --interactive`

PS : you should have aws cli should have the Session Manager plugin if not see https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html


when you're on backend task container , you can curl the nginx service on the front task container by :

`curl front.terraform.local`

and vice versa.
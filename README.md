# S3 Website

Terraform to create a website in the Stile Education AWS account that
is backed by S3. Currently it just uploads a GIF but you could upload
anything and make that the root. The website it creates will be served
at https://terraform-nick.dev.s522.net.

## Running

```
aws-vault exec dev -- terraform apply
```

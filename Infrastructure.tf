  
# setting the provider
provider "aws" {
 region = "ap-south-1"
 profile = "dev"
}

# creation of keys
resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "deploy-key"
  public_key = tls_private_key.key.public_key_openssh
}

# saving key to local file
resource "local_file" "deploy-key" {
  depends_on = [aws_security_group.http_allow, aws_key_pair.generated_key ]
    content  = tls_private_key.key.private_key_pem
    filename = "C:/Users/Shivangi/Downloads/AWS-keys/deploy-key.pem"
}
# Forming security group
resource "aws_security_group" "http_allow" {
  name        = "http_allow"
  description = "Allow inbound traffic"

  ingress {
    description = "HTTP ingress"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  
  }
  ingress {
    description = "jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http"
  }
}

#creating ec2 instance 
resource "aws_instance" "web" {
  depends_on = [aws_security_group.http_allow, local_file.deploy-key ]
 ami = "ami-0447a12f28fddb066"
 instance_type = "t2.micro"
 key_name = "SecKey"
 security_groups = [ "http_allow" ]

 connection {
    type = "ssh"
    user = "ec2-user"
    private_key = file("C:/Users/Shivangi/Downloads/AWS-keys/SecKey.pem")
    host = aws_instance.web.public_ip
 }
 provisioner "remote-exec" {
    inline = [
                "sudo yum install httpd php git docker -y",
                "sudo systemctl start httpd",
                "sudo systemctl enable httpd",
                "sudo service docker start",
                "sudo docker pull jenkins/jenkins",
                "sudo docker run -dit -p 8080:8080 --name jen jenkins/jenkins"
             ]
 }
 tags = {
    name = "first_web"
 }
}
# creating ebs volume
resource "aws_ebs_volume" "web_ebs" {
  availability_zone = aws_instance.web.availability_zone
  size = 1
  tags = {
    name = "web_ebs"
     }
} 
# attaching volume
resource "aws_volume_attachment" "web_ebs_attach" {
  device_name = "/dev/sdh"
  volume_id = "${aws_ebs_volume.web_ebs.id}"
  instance_id = "${aws_instance.web.id}"
  force_detach = true
}
# showing IP of ec2 instance 
output "web_ip" {
  value = aws_instance.web.public_ip
}
# Mounting
resource "null_resource" "null1" {
  
  depends_on = [ 
     aws_volume_attachment.web_ebs_attach, local_file.deploy-key
       ]
  connection{
    type = "ssh"
    user = "ec2-user"
    private_key =file("C:/Users/Shivangi/Downloads/AWS-keys/Seckey.pem")
    host = aws_instance.web.public_ip
   }  
  provisioner "remote-exec" {
    inline= [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/ShivangiSharma77/terraform_code.git /var/www/html/"
      ]
     
   }
}
# website deployment
resource "null_resource" "null2" {
 depends_on = [
     null_resource.null1, aws_cloudfront_distribution.s3_distribution 
   ] 
 provisioner "local-exec"{
       command= "start chrome ${aws_instance.web.public_ip}"
          }
          provisioner "local-exec"{
       command= "start chrome ${aws_instance.web.public_ip}:8080"
          }
}

#creating S3 bucket
resource "aws_s3_bucket" "b" {
  bucket = "shivangibucket777777"
  acl    = "public-read"

  policy = "${file("policy.json")}"
}

#inserting object
resource "aws_s3_bucket_object" "object" {
    depends_on = [
     aws_s3_bucket.b
   ] 
  bucket = "shivangibucket777777"
  key    = "img.jpg"
  source = "F:/HCC/terra/img/img.jpg"
  etag = "F:/HCC/terra/img/img.jpg"
}

#cloudfront identity
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Some comment"
}

locals {
  s3_origin_id = "myS3Origin"
}
# creating aws cloudfront
resource "aws_cloudfront_distribution" "s3_distribution" {
     depends_on = [
     aws_cloudfront_origin_access_identity.origin_access_identity, local_file.deploy-key
   ]
  origin {
    domain_name = aws_s3_bucket.b.bucket_domain_name
    origin_id   = "${local.s3_origin_id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/Shivangi/Downloads/AWS-keys/Seckey.pem")
    host     = aws_instance.web.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo su << EOF",
      "echo \"background-image: <img src='http://${self.domain_name}/${aws_s3_bucket_object.object.key}'>\" >> /var/www/html/index.html",
      "EOF"
    ]
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

#output object link
output "object_link"{
  value="http://${aws_s3_bucket.b.bucket_domain_name}/${aws_s3_bucket_object.object.key}"
}




//login with profile

provider "aws" {
  region  = "ap-south-1"
  profile = "Raghav"
}

//creating  key 

resource "tls_private_key" "task-key" {
  algorithm   = "RSA"
  provisioner "local-exec" {
	command = "echo  ' ${tls_private_key.task-key.private_key_pem}'  >  deployer-key.pem  &&  chmod  400  deployer-key.pem "
         }
}

resource "aws_key_pair" "deployer" {

   depends_on = [
           tls_private_key.task-key,
    ] 


  key_name   = "deployer-key"
  public_key =  tls_private_key.task-key.public_key_openssh
}

//CREATING SECURITY GROUP

resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = "vpc-988994f0"

  ingress {
    description = "TLS from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

 ingress {
    description = "httpd"
    from_port   = 40
    to_port     = 40
    protocol    = "tcp"
    cidr_blocks =["0.0.0.0/0"]
  }

//alowing SSH

ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
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
    Name = "allow_tls"
  }
}

// LAUNCHING INSTANCE AND INSTALLING REQUIRED SOFTWARE

resource "aws_instance" "web" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "deployer-key"
  security_groups = [ "allow_tls" ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task-key.private_key_pem
    host     = aws_instance.web.public_ip
  }

 provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "httpdserver"
  }

}

//launching  EBS volume

resource "aws_ebs_volume" "esb1" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1
  tags = {
    Name = "myebs"
  }
}

//attaching the volume to instance

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.esb1.id}"
  instance_id = "${aws_instance.web.id}"
  force_detach = true
}

output "myos_ip" {
  value = aws_instance.web.public_ip
}


resource "null_resource" "nulllocal2"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.web.public_ip} > publicip.txt"
  	}
}



resource "null_resource" "nullremote3"  {

depends_on = [
    aws_volume_attachment.ebs_att,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key =  tls_private_key.task-key.private_key_pem
    host     = aws_instance.web.public_ip
  }

//creating partitions ,mounting directory and fetching github repository

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",

    ]
  }
}

//creating s3 bucket

resource "aws_s3_bucket" "webbucket" {
depends_on = [
        aws_ebs_volume.esb1
     ]
 
  bucket = "my2000bucket"
  force_destroy = true
  acl    = "public-read"

  tags = {
    Name        = "my2000bucket"
  
  }
}

locals  {
    s3_origin_id = "mys3"
 }

//adding files to the bucket

resource "aws_s3_bucket_object" "dist" {

depends_on = [
   aws_s3_bucket.webbucket ,
  ]

  for_each = fileset("C:/Users/User/Desktop/webdeploy/", "*")
  bucket = "my2000bucket"
  key    = each.value
  source = "C:/Users/User/Desktop/webdeploy/${each.value}"
  etag   = filemd5("C:/Users/User/Desktop/webdeploy/${each.value}")
  acl="public-read"
}

//creating cloudfront

resource "aws_cloudfront_distribution" "s3_distribution" {

depends_on = [
         aws_s3_bucket_object.dist,
     ]   
  
  origin {
    domain_name = aws_s3_bucket.webbucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.webbucket.id
    }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  
  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.webbucket.bucket_domain_name
  }

   default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.webbucket.id

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

 ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = aws_s3_bucket.webbucket.id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.webbucket.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
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

resource "null_resource" "nullremote5"  {

depends_on = [
    aws_volume_attachment.ebs_att,
    aws_cloudfront_distribution.s3_distribution,
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task-key.private_key_pem
    host     = aws_instance.web.public_ip
  }

provisioner "remote-exec" {
    inline = [
      
      "sudo git clone https://github.com/R1999T/hybridtask1.git /var/www/html/",
      "sudo sed -i 's,img_url_1,https://${aws_cloudfront_distribution.s3_distribution.domain_name}/beautiful_evening.jpg,g' /var/www/html/index.html",
      "sudo sed -i 's,img_url_2,https://${aws_cloudfront_distribution.s3_distribution.domain_name}/natural_scenery.jpg,g' /var/www/html/index.html",
      "sudo systemctl restart httpd"
    ]
  }
}

resource "null_resource" "nullremote4"  {

depends_on = [
   null_resource.nullremote5,
  ]

provisioner "local-exec" {
	    command = "start chrome  http://${aws_instance.web.public_ip}/"
  	}
}
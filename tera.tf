# We have to give the service provider information to Terraform.
provider "aws" {
  region = "ap-south-1"
  profile = "abhimanyu"
}

# Create a Security group for RDS. Inside the security group, we have to allow incoming traffic from MySQL port i.e port number 3306.
resource "aws_security_group" "rds" {
  name        = "rds"
  description = "Allow mysql inbound traffic"
  ingress{
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch the database instance for WordPress using the above security group.
resource "aws_db_instance" "wordpressdb" {
 depends_on = [aws_security_group.rds]
 allocated_storage = 20
 storage_type = "gp2"
 engine = "mysql"
 engine_version = "5.7"
 instance_class = "db.t2.micro"
 name = "wordpressdb"
 username = "wordpressuser"
 password = "mysql15.7"
 parameter_group_name = "default.mysql5.7"
 publicly_accessible = true
 skip_final_snapshot = true
 vpc_security_group_ids= [aws_security_group.rds.id]
 tags = {
 name = "wordpres-mysql"
 }
}

# We have to give the Kubernetes service provider information to Terraform.
provider "kubernetes" {
  config_context = "minikube"
}

# Create a new Namespace for WordPress. The namespace provides us logical separation.
resource "kubernetes_namespace" "hybrid-setup" {
 metadata {
 name = "hybrid-setup"
 }
}

resource "kubernetes_persistent_volume_claim" "wordpress_pvc" {
  depends_on = [aws_db_instance.wordpressdb]
  metadata {
    name = "newwordpressclaim"
    namespace = kubernetes_namespace.hybrid-setup.id
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "wordpress" {
  depends_on = [kubernetes_persistent_volume_claim.wordpress_pvc]
  metadata {
    name = "wordpress"
    namespace = kubernetes_namespace.hybrid-setup.id
    labels = {
      Env = "wordpress"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        Env = "wordpress"
      }
    }
    template {
      metadata {
        labels = {
          Env = "wordpress"
        }
      }
      spec {
        container {
          name = "wordpress"
          image = "wordpress:4.8-apache"
          env{
            name = "WORDPRESS_DB_HOST"
            value = aws_db_instance.wordpressdb.address
          }
          env{
            name = "WORDPRESS_DB_USER"
            value = aws_db_instance.wordpressdb.username
          }
          env{
            name = "WORDPRESS_DB_PASSWORD"
            value = aws_db_instance.wordpressdb.password
          }
          env{
          name = "WORDPRESS_DB_NAME"
          value = aws_db_instance.wordpressdb.name
          }
          port {
            container_port = 80
          }
          volume_mount{
            name = "pv-wordpress"
            mount_path = "/var/lib/pam"
          }
        }
        volume{
          name = "pv-wordpress"
          persistent_volume_claim{
            claim_name = kubernetes_persistent_volume_claim.wordpress_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

# Expose this pod to the outside world so that our clients can WordPress site.
resource "kubernetes_service" "expose" {
  depends_on = [kubernetes_deployment.wordpress]
  metadata {
    name = "exposewp"
    namespace = kubernetes_namespace.hybrid-setup.id
  }
  spec {
    selector = {
      Env = "${kubernetes_deployment.wordpress.metadata.0.labels.Env}"
    }
    port {
      node_port   = 32123
      port        = 80
      target_port = 80
    }
    type = "NodePort"
  }
}

# After everything is completed I want to run the WordPress on chrome. For this, I am using null_resource to run commands on windows.
resource "null_resource" "runwebpage" {
 depends_on = [kubernetes_service.expose]
 provisioner "local-exec" {
 command = "chrome http:://192.168.99.102:${kubernetes_service.expose.spec[0].port[0].node_port}"
 }
}
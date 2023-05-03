resource "aws_s3_bucket" "bkt" {
    bucket_prefix = "s3bkt-" 
    force_destroy = true
}
/*
resource "aws_s3_bucket_acl" "bucket_acl" {
  bucket = aws_s3_bucket.bkt.id
  acl    = "private"
}
*/

resource "aws_s3_bucket_lifecycle_configuration" "bucket-config" {

  bucket = aws_s3_bucket.bkt.id

  rule {
    id = "archival"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}


resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  bucket = aws_s3_bucket.bkt.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket = aws_s3_bucket.bkt.id


  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

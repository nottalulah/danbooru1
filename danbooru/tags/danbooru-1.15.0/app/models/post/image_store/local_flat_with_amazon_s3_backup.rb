module PostImageStoreMethods
  module LocalFlatWithAmazonS3Backup
    def move_file
      FileUtils.mv(tempfile_path, file_path)
      FileUtils.chmod(0664, file_path)

      if image?
        FileUtils.mv(tempfile_preview_path, preview_path)
        FileUtils.chmod(0664, preview_path)
      end

      if File.exists?(tempfile_sample_path)
        FileUtils.mv(tempfile_sample_path, sample_path)
        FileUtils.chmod(0664, sample_path)
      end

      self.delete_tempfile()
  
      base64_md5 = Base64.encode64(self.md5.unpack("a2" * (self.md5.size / 2)).map {|x| x.hex.chr}.join)
  
      AWS::S3::Base.establish_connection!(:access_key_id => CONFIG["amazon_s3_access_key_id"], :secret_access_key => CONFIG["amazon_s3_secret_access_key"])
      AWS::S3::S3Object.store(file_name, open(self.file_path, "rb"), CONFIG["amazon_s3_bucket_name"], :access => :public_read, "Content-MD5" => base64_md5)
  
      if image?
        AWS::S3::S3Object.store("preview/#{md5}.jpg", open(self.preview_path, "rb"), CONFIG["amazon_s3_bucket_name"], :access => :public_read)
      end

      if File.exists?(tempfile_sample_path)
        AWS::S3::S3Object.store("sample/" + CONFIG["sample_filename_prefix"] + "#{md5}.jpg", open(self.sample_path, "rb"), CONFIG["amazon_s3_bucket_name"], :access => :public_read)
      end

      return true
    end

    def file_path
      "#{RAILS_ROOT}/public/data/#{file_name}"
    end

    def file_url
      CONFIG["url_base"] + "/data/#{file_name}"
    end

    def preview_path
      if status == "deleted"
        "#{RAILS_ROOT}/public/deleted-preview.png"
      elsif image?
        "#{RAILS_ROOT}/public/data/preview/#{md5}.jpg"
      else
        "#{RAILS_ROOT}/public/download-preview.png"
      end
    end

    def sample_path
      "#{RAILS_ROOT}/public/data/sample/" + CONFIG["sample_filename_prefix"] + "#{md5}.jpg"
    end

    def preview_url
      if self.image?
        CONFIG["url_base"] + "/data/preview/#{md5}.jpg"
      else
        CONFIG["url_base"] + "/download-preview.png"
      end
    end

    def store_sample_url
      CONFIG["url_base"] + "/data/sample/" + CONFIG["sample_filename_prefix"] + "#{md5}.jpg"
    end

    def delete_file
      AWS::S3::Base.establish_connection!(:access_key_id => CONFIG["amazon_s3_access_key_id"], :secret_access_key => CONFIG["amazon_s3_secret_access_key"])
      AWS::S3::S3Object.delete(file_name, CONFIG["amazon_s3_bucket_name"])
      AWS::S3::S3Object.delete("preview/#{md5}.jpg", CONFIG["amazon_s3_bucket_name"])
      AWS::S3::S3Object.delete("sample/#{md5}.jpg", CONFIG["amazon_s3_bucket_name"])
      FileUtils.rm_f(file_path)
      FileUtils.rm_f(preview_path) if image?
      FileUtils.rm_f(sample_path) if image?
    end
  end
end

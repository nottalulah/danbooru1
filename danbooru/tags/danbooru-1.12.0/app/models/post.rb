class Post < ActiveRecord::Base  
  module ParentMethods
    def parent_id=(pid)
      @old_parent_id = self.parent_id
      
      pid = "" if pid.to_i == self.id
      write_attribute(:parent_id, pid)
    end
    
    def validate_parent
      errors.add("parent_id") unless parent_id.nil? or Post.exists?(parent_id)
    end

    def update_parent_on_create
      if self.parent_id
        connection.execute("update posts set has_children = true where id = #{self.parent_id}")
      end
    end
  
    def update_parent_on_update
      if @old_parent_id && nil == connection.select_value("select 1 from posts where parent_id = #{@old_parent_id} limit 1")
        connection.execute("update posts set has_children = false where id = #{@old_parent_id}")
      end
    
      if self.parent_id
        connection.execute("update posts set has_children = true where id = #{self.parent_id}")
      end
    end
  end
  
  module CacheMethods
    def expire_cache_on_create
      unless self.is_pending?
        Cache.expire(:tags => self.cached_tags, :post_id => self.id)
      end
    end

    def expire_cache_on_update
      unless self.is_pending?
        Cache.expire(:tags => self.cached_tags, :post_id => self.id)
      end
    end

    def expire_cache_on_destroy
      unless self.is_pending?
        Cache.expire(:tags => self.cached_tags, :post_id => self.id)
      end
    end
  end
  
  module NeighborMethods
    def update_neighbor_links_on_create
      prev_post = Post.find(:first, :conditions => ["id < ?", id], :order => "id DESC", :select => "id")

      if prev_post != nil
        # should only be nil for very first post created
        connection.execute("UPDATE posts SET prev_post_id = #{prev_post.id} WHERE id = #{self.id}")
        connection.execute("UPDATE posts SET next_post_id = #{self.id} WHERE id = #{prev_post.id}")
      end
    end

    def update_neighbor_links_on_update
      if next_post_id
        connection.execute("UPDATE posts SET prev_post_id = #{id} WHERE id = #{next_post_id}")
      end

      if prev_post_id
        connection.execute("UPDATE posts SET next_post_id = #{id} WHERE id = #{prev_post_id}")
      end
    end
  end
  
  module TagMethods
    # Returns the tags in a URL suitable string
    def tag_title
      return self.cached_tags.gsub(/[^a-z0-9]+/, "-")[0, 50]
    end

    def append_tags(t)
      @new_tags = self.cached_tags + " " + t
    end
    
    def tags
      if self.new_record?
        []
      else
        Tag.find(:all, :joins => "join posts_tags on tags.id = posts_tags.tag_id", :select => "tags.*", :conditions => "posts_tags.post_id = #{self.id}")
      end
    end

    def tags=(t)
      @new_tags = t || ""
    end
    
    # commits the tag changes to the database
    def commit_tags
      return if @new_tags == nil

      logger.error "@new_tags = #{@new_tags}"

      @new_tags = Tag.scan_tags(@new_tags)
      
      if self.old_tags
        # If someone else committed changes to this post before we did, 
        # try to merge the tag changes together.
        current_tags = self.cached_tags.scan(/\S+/)
        self.old_tags = Tag.scan_tags(self.old_tags)
        @new_tags = (current_tags + @new_tags) - self.old_tags + (current_tags & @new_tags)
      end
      
      metatags, @new_tags = @new_tags.partition {|x| x =~ /^(?:rating|parent|pool):/}
      
      metatags.each do |t|
        if t =~ /^rating:([qse])/
          connection.execute(Post.sanitize_sql(["UPDATE posts SET rating = ? WHERE id = ?", $1, self.id]))
        elsif CONFIG["enable_parent_posts"] && t =~ /^parent:(\d+)/
          connection.execute(Post.sanitize_sql(["UPDATE posts SET parent_id = ? WHERE id = ?", $1, self.id]))
          connection.execute("update posts set has_children = true where id = #{$1}")
        elsif t =~ /^pool:(.+)/
          begin
            pool = Pool.find(:first, :conditions => ["lower(name) = lower(?)", $1])
            pool.add_post(self.id) if pool
          rescue Pool::PostAlreadyExistsError
          end
        end
      end

      @new_tags << "tagme" if @new_tags.empty?
      @new_tags = TagAlias.to_aliased(@new_tags).uniq
      @new_tags = TagImplication.with_implied(@new_tags).uniq

      transaction do
        # TODO: be more selective in deleting from the join table
        connection.execute("DELETE FROM posts_tags WHERE post_id = #{self.id}")
        @new_tags = @new_tags.map {|x| Tag.find_or_create_by_name(x)}
        @new_tags.each do |x|
          connection.execute("INSERT INTO posts_tags (post_id, tag_id) VALUES (#{self.id}, #{x.id})")
        end

        tag_string = @new_tags.map {|x| x.name}.sort.join(" ")

        unless PostTagHistory.disable_versioning || connection.select_value("SELECT tags FROM post_tag_histories WHERE post_id = #{id} ORDER BY id DESC LIMIT 1") == tag_string
          PostTagHistory.create(:post_id => self.id, :tags => tag_string, :user_id => self.updater_user_id, :ip_addr => self.updater_ip_addr)
        end
        connection.execute(Post.sanitize_sql(["UPDATE posts SET cached_tags = ? WHERE id = #{id}", tag_string]))
      end
    end
  end

  module SqlMethods
    def generate_sql_range_helper(arr, field, c, p)
      case arr[0]
      when :eq
        c << "#{field} = ?"
        p << arr[1]

      when :gt
        c << "#{field} > ?"
        p << arr[1]
      
      when :gte
        c << "#{field} >= ?"
        p << arr[1]

      when :lt
        c << "#{field} < ?"
        p << arr[1]

      when :lte
        c << "#{field} <= ?"
        p << arr[1]

      when :between
        c << "#{field} BETWEEN ? AND ?"
        p << arr[1]
        p << arr[2]

      else
        # do nothing
      end
    end

    def generate_sql(q, options = {})
      original_query = q

      unless q.is_a?(Hash)
        q = Tag.parse_query(q)
      end

      conds = ["true"]
      joins = ["posts p"]
      join_params = []
      cond_params = []

      generate_sql_range_helper(q[:post_id], "p.id", conds, cond_params)
      generate_sql_range_helper(q[:width], "p.width", conds, cond_params)
      generate_sql_range_helper(q[:height], "p.height", conds, cond_params)
      generate_sql_range_helper(q[:score], "p.score", conds, cond_params)
      generate_sql_range_helper(q[:date], "p.created_at::date", conds, cond_params)

      if q[:md5].is_a?(String)
        conds << "p.md5 = ?"
        cond_params << q[:md5]
      end

      if q[:parent_id].is_a?(Integer)
        conds << "(p.parent_id = ? or p.id = ?)"
        cond_params << q[:parent_id]
        cond_params << q[:parent_id]
      elsif q[:parent_id] == false
        conds << "p.parent_id is null"
      end

      if q[:source].is_a?(String)
        conds << "p.source LIKE ? ESCAPE '\\\\'"
        cond_params << Artist.normalize_url(q[:source])
      end

      if q[:fav].is_a?(String)
        joins << "JOIN favorites f ON f.post_id = p.id JOIN users fu ON f.user_id = fu.id"
        conds << "lower(fu.name) = lower(?)"
        cond_params << q[:fav]
      end

      if q[:user].is_a?(String)
        joins << "JOIN users u ON p.user_id = u.id"
        conds << "lower(u.name) = lower(?)"
        cond_params << q[:user]
      end

      if q[:pool].is_a?(String)
        joins << "JOIN pools_posts ON pools_posts.post_id = p.id JOIN pools ON pools_posts.pool_id = pools.id"
        conds << "pools.name ILIKE ? ESCAPE '\\\\'"
        cond_params << ("%" + q[:pool].to_escaped_for_sql_like + "%")
      end

      if q[:include].any?
        joins << "JOIN posts_tags ipt ON ipt.post_id = p.id"
        conds << "ipt.tag_id IN (SELECT id FROM tags WHERE name IN (?))"
        cond_params << (q[:include] + q[:related])
      elsif q[:related].any?
        q[:related].each_with_index do |rtag, i|
          joins << "JOIN posts_tags rpt#{i} ON rpt#{i}.post_id = p.id AND rpt#{i}.tag_id = (SELECT id FROM tags WHERE name = ?)"
          join_params << rtag
        end
      end

      if q[:exclude].any?
        q[:exclude].each_with_index do |etag, i|
          joins << "LEFT JOIN posts_tags ept#{i} ON p.id = ept#{i}.post_id AND ept#{i}.tag_id = (SELECT id FROM tags WHERE name = ?)"
          conds << "ept#{i}.tag_id IS NULL"
          join_params << etag
        end
      end

      if q[:rating].is_a?(String)
        case q[:rating][0, 1].downcase
        when "s"
          conds << "p.rating = 's'"

        when "q"
          conds << "p.rating = 'q'"

        when "e"
          conds << "p.rating = 'e'"
        end
      end

      if q[:rating_negated].is_a?(String)
        case q[:rating_negated][0, 1].downcase
        when "s"
          conds << "p.rating <> 's'"

        when "q"
          conds << "p.rating <> 'q'"

        when "e"
          conds << "p.rating <> 'e'"
        end
      end

      if q[:unlocked_rating] == true
        conds << "p.is_rating_locked = FALSE"
      end

      if options[:pending]
        conds << "p.status = 'pending'"
      end
      
      if options[:flagged]
        conds << "p.status = 'flagged'"
      end

      if original_query.blank?
        conds << "p.parent_id is null"
      end

      sql = "SELECT "

      if options[:count]
        sql << "COUNT(*)"
      else
        sql << "p.*"
      end

      sql << " FROM " + joins.join(" ")
      sql << " WHERE " + conds.join(" AND ")

      if q[:order] && !options[:count]
        case q[:order]
        when "id"
          sql << " ORDER BY p.id"
          
        when "id_desc"
          sql << " ORDER BY p.id DESC"
          
        when "score"
          sql << " ORDER BY p.score"
          
        when "score_desc"
          sql << " ORDER BY p.score DESC"
          
        else
          sql << " ORDER BY p.id DESC"
        end
      elsif options[:order]
        sql << " ORDER BY " + options[:order]
      end

      if options[:limit]
        sql << " LIMIT " + options[:limit].to_s
      end

      if options[:offset]
        sql << " OFFSET " + options[:offset].to_s
      end

      params = join_params + cond_params
      return Post.sanitize_sql([sql, *params])
    end
  end
  
  module CountMethods
    module ClassMethods
      def fast_count(tags = nil, force_calculation = true)
        if tags.blank?
          return connection.select_value("SELECT row_count FROM table_data WHERE name = 'posts'").to_i
        else
          c = connection.select_value(sanitize_sql(["SELECT post_count FROM tags WHERE name = ?", tags])).to_i
          if c == 0 && force_calculation
            return Post.count_by_sql(Post.generate_sql(tags, :count => true))
          else
            return c
          end
        end
      end
    end
    
    def self.included(m)
      m.extend(ClassMethods)
    end
    
    def update_count
    end

    def increment_count
      connection.execute("update table_data set row_count = row_count + 1 where name = 'posts'")
    end

    def decrement_count
      connection.execute("update table_data set row_count = row_count - 1 where name = 'posts'")
    end
  end
  
  module CommentMethods
    def recent_comments
      Comment.find(:all, :conditions => "post_id = #{self.id}", :order => "id desc", :limit => 6).reverse
    end

    def comment_count
      @comment_count ||= Comment.count_by_sql("SELECT COUNT(*) FROM comments WHERE post_id = #{self.id}")
      return @comment_count
    end
  end
  
  module ImageStoreMethods
    def image_store(type)
      case type
      when :local_flat
        include LocalFlat
        
      when :local_flat_with_amazon_s3_backup
        include LocalFlatWithAmazonS3Backup

      when :local_hierarchy
        include LocalHierarchy

      when :remote_hierarchy
        include RemoteHierarchy

      when :amazon_s3
        include AmazonS3
      end
    end
    
    module LocalFlat
      def file_path
        "#{RAILS_ROOT}/public/data/#{file_name}"
      end

      def file_url
        CONFIG["url_base"] + "/data/#{file_name}"
      end

      def preview_path
        if image?
          "#{RAILS_ROOT}/public/data/preview/#{md5}.jpg"
        else
          "#{RAILS_ROOT}/public/data/preview/default.png"
        end
      end

      def preview_url
        if image?
          CONFIG["url_base"] + "/data/preview/#{md5}.jpg"
        else
          CONFIG["url_base"] + "/data/preview/default.png"
        end
      end

      def delete_file
        FileUtils.rm_f(file_path)
        FileUtils.rm_f(preview_path) if image?
      end

      def move_file
        FileUtils.mv(tempfile_path, file_path)
        FileUtils.chmod(0775, file_path)

        if image?
          FileUtils.mv(tempfile_preview_path, preview_path)
          FileUtils.chmod(0775, preview_path)
        end

        delete_tempfile
      end
    end

    module LocalHierarchy
      def file_hierarchy
        "%s/%s" % [md5[0,2], md5[2,2]]
      end

      def file_path
        "#{RAILS_ROOT}/public/data/#{file_hierarchy}/#{file_name}"
      end

      def file_url
        CONFIG["url_base"] + "/data/#{file_hierarchy}/#{file_name}"
      end

      def preview_path
        if image?
          "#{RAILS_ROOT}/public/data/preview/#{file_hierarchy}/#{md5}.jpg"
        else
          "#{RAILS_ROOT}/public/data/preview/default.png"
        end
      end

      def preview_url
        if image?
          CONFIG["url_base"] + "/data/preview/#{file_hierarchy}/#{md5}.jpg"
        else
          CONFIG["url_base"] + "/data/preview/default.png"
        end
      end

      def delete_file
        FileUtils.rm_f(file_path)
        FileUtils.rm_f(preview_path) if image?
      end

      def move_file
        FileUtils.mkdir_p(File.dirname(file_path), :mode => 0775)
        FileUtils.mv(tempfile_path, file_path)
        FileUtils.chmod(0775, file_path)

        if image?
          FileUtils.mkdir_p(File.dirname(preview_path), :mode => 0775)
          FileUtils.mv(tempfile_preview_path, preview_path)
          FileUtils.chmod(0775, preview_path)
        end

        delete_tempfile
      end
    end

    module RemoteHierarchy
      def file_hierarchy
        "%s/%s" % [md5[0,2], md5[2,2]]
      end

      def select_random_image_server
        CONFIG["image_servers"][rand(CONFIG["image_servers"].size)]
      end

      def file_path
        "#{RAILS_ROOT}/public/data/#{file_hierarchy}/#{file_name}"
      end

      def file_url
        if self.is_warehoused?
          select_random_image_server() + "/data/#{file_hierarchy}/#{file_name}"
        else
          CONFIG["url_base"] + "/data/#{file_hierarchy}/#{file_name}"
        end
      end

      def preview_path
        if image?
          "#{RAILS_ROOT}/public/data/preview/#{file_hierarchy}/#{md5}.jpg"
        else
          "#{RAILS_ROOT}/public/data/preview/default.png"
        end
      end

      def preview_url
        if self.is_warehoused?
          if image?
            select_random_image_server() + "/data/preview/#{file_hierarchy}/#{md5}.jpg"
          else
            select_random_image_server() + "/data/preview/default.png"
          end
        else
          if image?
            CONFIG["url_base"] + "/data/preview/#{file_hierarchy}/#{md5}.jpg"
          else
            CONFIG["url_base"] + "/data/preview/default.png"
          end
        end
      end

      def delete_file
        FileUtils.rm_f(file_path)
        FileUtils.rm_f(preview_path) if image?
      end

      def move_file
        FileUtils.mkdir_p(File.dirname(file_path), :mode => 0775)
        FileUtils.mv(tempfile_path, file_path)
        FileUtils.chmod(0775, file_path)

        if image?
          FileUtils.mkdir_p(File.dirname(preview_path), :mode => 0775)
          FileUtils.mv(tempfile_preview_path, preview_path)
          FileUtils.chmod(0775, preview_path)
        end

        delete_tempfile
      end
    end

    module AmazonS3
      def move_file
        begin
          base64_md5 = Base64.encode64(self.md5.unpack("a2" * (self.md5.size / 2)).map {|x| x.hex.chr}.join)
          
          AWS::S3::Base.establish_connection!(:access_key_id => CONFIG["amazon_s3_access_key_id"], :secret_access_key => CONFIG["amazon_s3_secret_access_key"])
          AWS::S3::S3Object.store(file_name, open(self.tempfile_path, "rb"), CONFIG["amazon_s3_bucket_name"], :access => :public_read, "Content-MD5" => base64_md5, "Cache-Control" => "max-age=315360000")
          
          if image?
            AWS::S3::S3Object.store("preview/#{md5}.jpg", open(self.tempfile_preview_path, "rb"), CONFIG["amazon_s3_bucket_name"], :access => :public_read, "Cache-Control" => "max-age=315360000")
          end

          return true
        ensure
          self.delete_tempfile()
        end
      end

      def file_url
        "http://s3.amazonaws.com/" + CONFIG["amazon_s3_bucket_name"] + "/#{file_name}"
      end

      def preview_url
        if self.image?
          "http://s3.amazonaws.com/" + CONFIG["amazon_s3_bucket_name"] + "/preview/#{md5}.jpg"
        else
          "http://s3.amazonaws.com/" + CONFIG["amazon_s3_bucket_name"] + "/preview/default.png"
        end
      end

      def delete_file
        AWS::S3::Base.establish_connection!(:access_key_id => CONFIG["amazon_s3_access_key_id"], :secret_access_key => CONFIG["amazon_s3_secret_access_key"])
        AWS::S3::S3Object.delete(file_name, CONFIG["amazon_s3_bucket_name"])
        AWS::S3::S3Object.delete("preview/#{md5}.jpg", CONFIG["amazon_s3_bucket_name"])
      end
    end

    module LocalFlatWithAmazonS3Backup
      def move_file
        FileUtils.mv(tempfile_path, file_path)
        FileUtils.chmod(0775, file_path)

        if image?
          FileUtils.mv(tempfile_preview_path, preview_path)
          FileUtils.chmod(0775, preview_path)
        end
        
        self.delete_tempfile()
        
        base64_md5 = Base64.encode64(self.md5.unpack("a2" * (self.md5.size / 2)).map {|x| x.hex.chr}.join)
        
        AWS::S3::Base.establish_connection!(:access_key_id => CONFIG["amazon_s3_access_key_id"], :secret_access_key => CONFIG["amazon_s3_secret_access_key"])
        AWS::S3::S3Object.store(file_name, open(self.file_path, "rb"), CONFIG["amazon_s3_bucket_name"], :access => :private, "Content-MD5" => base64_md5)
        
        if image?
          AWS::S3::S3Object.store("preview/#{md5}.jpg", open(self.preview_path, "rb"), CONFIG["amazon_s3_bucket_name"], :access => :private)
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
        if image?
          "#{RAILS_ROOT}/public/data/preview/#{md5}.jpg"
        else
          "#{RAILS_ROOT}/public/data/preview/default.png"
        end
      end

      def preview_url
        if image?
          CONFIG["url_base"] + "/data/preview/#{md5}.jpg"
        else
          CONFIG["url_base"] + "/data/preview/default.png"
        end
      end

      def delete_file
        AWS::S3::Base.establish_connection!(:access_key_id => CONFIG["amazon_s3_access_key_id"], :secret_access_key => CONFIG["amazon_s3_secret_access_key"])
        AWS::S3::S3Object.delete(file_name, CONFIG["amazon_s3_bucket_name"])
        AWS::S3::S3Object.delete("preview/#{md5}.jpg", CONFIG["amazon_s3_bucket_name"])
        FileUtils.rm_f(file_path)
        FileUtils.rm_f(preview_path) if image?
      end
    end
  end
  
  module VoteMethods
    def vote!(score, ip_addr)
      if self.last_voter_ip == ip_addr
        return false
      else
        self.score += score
        connection.execute("UPDATE posts SET score = #{self.score}, last_voter_ip = '#{ip_addr}' WHERE id = #{self.id}")
      end

      return true
    end
  end
  
  has_many :comments, :order => "id"
  has_many :notes, :order => "id desc"
  has_many :tag_history, :class_name => "PostTagHistory", :table_name => "post_tag_histories", :order => "id desc"
  belongs_to :user
  
  include NeighborMethods
  include TagMethods
  extend SqlMethods
  include CountMethods
  include CommentMethods
  extend ImageStoreMethods
  include VoteMethods
  
  image_store(CONFIG["image_store"])
  
  if CONFIG["enable_caching"]
    include CacheMethods
    after_create :expire_cache_on_create
    after_update :expire_cache_on_update
    before_destroy :expire_cache_on_destroy
  end

  if CONFIG["enable_parent_posts"]
    include ParentMethods
    after_create :update_parent_on_create
    after_update :update_parent_on_update
    validate :validate_parent
  end

  before_validation_on_create :auto_download
  before_validation_on_create :validate_content_type
  before_validation_on_create :generate_hash
  before_validation_on_create :generate_preview
  before_validation_on_create :get_image_dimensions
  before_validation_on_create :move_file
  # before_validation_on_create :validate_file_existence
  before_destroy :delete_file
  before_destroy :update_status_on_destroy
  after_create :update_neighbor_links_on_create
  after_update :update_neighbor_links_on_update
  attr_accessor :updater_ip_addr
  attr_accessor :updater_user_id
  attr_accessor :old_tags
  after_save :commit_tags
  after_save :blank_image_board_sources
  after_create :increment_count
  after_destroy :decrement_count
  after_save :update_count
    
  def validate_content_type
    unless %w(jpg jpeg png gif swf).include?(self.file_ext.downcase)
      self.errors.add(:file, "is an invalid content type")
      return false
    end
  end
  
  def update_status_on_destroy
    self.update_attribute(:status, "deleted")
    return false
  end

  def favorited_by
    User.find(:all, :joins => "JOIN favorites f ON f.user_id = users.id", :select => "users.name, users.id", :conditions => ["f.post_id = ?", self.id], :order => "lower(users.name)")
  end

  def blank_image_board_sources
    if self.source.to_s =~ /moeboard|\/src\/\d{12,}|urnc\.yi\.org/
      connection.execute("UPDATE posts SET source = '' WHERE id = #{self.id}")
    end
  end

  def rating=(r)
    if r == nil && !self.new_record?
      return
    end

    if self.is_rating_locked?
      return
    end

    r = r.to_s.downcase[0, 1]

    @old_rating = self.rating

    if %w(q e s).include?(r)
      write_attribute(:rating, r)
    else
      write_attribute(:rating, 'q')
    end
  end

  def file_name
    md5 + "." + file_ext
  end

  def delete_tempfile
    FileUtils.rm_f(tempfile_path)
    FileUtils.rm_f(tempfile_preview_path)
  end

  def tempfile_path
    "#{RAILS_ROOT}/public/data/#{$$}.upload"
  end

  def tempfile_preview_path
    "#{RAILS_ROOT}/public/data/#{$$}-preview.jpg"
  end

# Generates a MD5 hash for the file
  def generate_hash
    unless File.exists?(tempfile_path)
      errors.add(:file, "not found")
      return false
    end
    
    self.md5 = File.open(tempfile_path, 'rb') {|fp| Digest::MD5.hexdigest(fp.read)}

    if connection.select_value("SELECT 1 FROM posts WHERE md5 = '#{md5}'")
      delete_tempfile
      errors.add "md5", "already exists"
      return false
    else
      return true
    end
  end

  def generate_preview
    return true unless image?
    
    unless File.exists?(tempfile_path)
      errors.add(:file, "not found")
      return false
    end

    begin
      Timeout.timeout(120) do
        retcode = Danbooru.resize_image(file_ext, tempfile_path, tempfile_preview_path)
    
        if retcode == 0
          return true
        else
          errors.add "preview", "couldn't be generated (error code #{retcode})"
          return false
        end
      end
    rescue Timeout::Error
      errors.add "preview", "timed out"
      return false
    end
  end

# automatically downloads from the source url if it's a URL
  def auto_download
    if source =~ /^http:\/\// && file_ext.blank?
      begin
        url = URI.parse(source)
        res = Net::HTTP.start(url.host, url.port) do |http|
          http.read_timeout = 10
          http.get(url.request_uri)
        end
        self.file_ext = content_type_to_file_ext(res.content_type) || find_ext(source)
        File.open(tempfile_path, 'wb') do |out|
          out.write(res.body)
        end

        self.source = Artist.normalize_url(source)

        return true
      rescue Exception => x
        delete_tempfile
        errors.add "source", "couldn't be opened: #{x}"
        return false
      end
    end
  end

# file= assigns a CGI file to the post. This writes the file to disk and generates a unique file name.
  def file=(f)
    return if f.nil? || f.size == 0

    self.file_ext = content_type_to_file_ext(f.content_type) || find_ext(f.original_filename)

    if f.local_path
      # Large files are stored in the temp directory, so instead of
      # reading/rewriting through Ruby, just rely on system calls to
      # copy the file to danbooru's directory.
      FileUtils.cp(f.local_path, tempfile_path)
    else
      File.open(tempfile_path, 'wb') {|nf| nf.write(f.read)}
    end
  end

  def get_image_dimensions
    if image? or flash?
      imgsize = ImageSize.new(File.open(tempfile_path, "rb"))
      self.width = imgsize.get_width
      self.height = imgsize.get_height
    end
  end

# Returns true if the post is an image format that GD can handle.
  def image?
    %w(jpg jpeg gif png).include?(self.file_ext.downcase)
  end

# Returns true if the post is a Flash movie.
  def flash?
    file_ext == "swf"
  end

# Returns either the author's name or the default guest name.
  def author
    if @author
      @author
    elsif user_id
      @author = connection.select_value("SELECT name FROM users WHERE id = #{self.user_id}")
      @author
    else
      CONFIG["default_guest_name"]
    end
  end

  def self.find_by_tags(tags, options = {})
    return find_by_sql(Post.generate_sql(tags, options))
  end

  def pretty_rating
    case rating
    when "q"
      return "Questionable"

    when "e"
      return "Explicit"

    when "s"
      return "Safe"
    end
  end

  def to_json(options = {})
    {:id => id, :tags => cached_tags, :created_at => created_at, :creator_id => user_id, :source => source, :score => score, :md5 => md5, :file_url => file_url, :preview_url => preview_url, :next_post_id => next_post_id, :prev_post_id => prev_post_id, :rating => rating}.to_json(options)
  end

  def to_xml(options = {})
    {:id => id, :tags => cached_tags, :created_at => created_at, :creator_id => user_id, :source => source, :score => score, :md5 => md5, :file_url => file_url, :preview_url => preview_url, :parent_id => parent_id, :next_post_id => next_post_id, :prev_post_id => prev_post_id, :rating => rating}.to_xml(options.merge(:root => "post"))
  end

  def find_ext(file_path)
    ext = File.extname(file_path)
    if ext.blank?
      return "txt"
    else
      return ext[1..-1].downcase
    end
  end

  def content_type_to_file_ext(content_type)
    content_type = content_type.chomp

    case content_type
    when "image/jpeg"
      return "jpg"

    when "image/gif"
      return "gif"

    when "image/png"
      return "png"

    when "application/x-shockwave-flash"
      return "swf"

    else
      nil
    end
  end
  
  def delete_from_database
    connection.execute("delete from posts where id = #{self.id}")
  end
  
  def active_notes
    self.notes.select {|x| x.is_active?}
  end
  
  def is_flagged?
    self.status == "flagged"
  end
  
  def is_pending?
    self.status == "pending"
  end
  
  def is_deleted?
    self.status == "deleted"
  end
  
  def is_active?
    self.status == "active"
  end
  
  def can_view?(user)
    if user == nil || !user.privileged?
      if CONFIG["hide_explicit_posts"] && self.rating == 'e'
        return false
      elsif CONFIG["hide_questionable_posts"] && self.rating != 's'
        return false
      elsif CONFIG["hide_loli_posts"] && self.is_loli?
        return false
      end
    end
    
    return true
  end
  
  def is_loli?
    return self.cached_tags =~ /\b(?:loli|shota)\b/
  end
end

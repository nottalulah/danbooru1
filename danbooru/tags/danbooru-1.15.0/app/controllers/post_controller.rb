class PostController < ApplicationController
  layout 'default'

  verify :method => :post, :only => [:update, :destroy, :create, :revert_tags, :vote, :flag], :redirect_to => {:action => :show, :id => lambda {|c| c.params[:id]}}
  before_filter :member_only, :only => [:create, :upload, :destroy, :delete, :flag, :update, :revert_tags, :random]
  before_filter :janitor_only, :only => [:moderate, :undelete]
  after_filter :save_tags_to_cookie, :only => [:update, :create]
  if CONFIG["load_average_threshold"]
    before_filter :check_load_average, :only => [:index, :popular_by_day, :popular_by_week, :popular_by_month, :random, :atom, :piclens]
  end
  
  if CONFIG["enable_caching"]
    around_filter :cache_action, :only => [:index, :atom, :piclens]
  end

  helper :wiki, :tag, :comment, :pool, :favorite, :advertisement

  def verify_action(options)
    redirect_to_proc = false
    
    if options[:redirect_to] && options[:redirect_to][:id].is_a?(Proc)
      redirect_to_proc = options[:redirect_to][:id]
      options[:redirect_to][:id] = options[:redirect_to][:id].call(self)
    end
    
    result = super(options)
  	
    if redirect_to_proc
      options[:redirect_to][:id] = redirect_to_proc
    end
	  
    return result
  end
  
  def upload
    if params[:url]
      @post = Post.find(:first, :conditions => ["source = ?", params[:url]])
    end
    
    if @post.nil?
      @post = Post.new
    end
  end

  def create
    if @current_user.is_member_or_lower? && Post.count(:conditions => ["user_id = ? AND created_at > ? ", @current_user.id, 1.day.ago]) >= CONFIG["member_post_limit"]
      respond_to_error("Daily limit exceeded", {:action => "index"}, :status => 421)
      return
    end

    if @current_user.is_contributor_or_higher?
      status = "active"
    else
      status = "pending"
    end

    @post = Post.create(params[:post].merge(:updater_user_id => @current_user.id, :updater_ip_addr => request.remote_ip, :user_id => @current_user.id, :ip_addr => request.remote_ip, :status => status))

    if @post.errors.empty?
      if params[:md5] && @post.md5 != params[:md5].downcase
        @post.destroy
        respond_to_error("MD5 mismatch", {:action => "upload"}, :status => 420)
      else
        respond_to_success("Post uploaded", {:controller => "post", :action => "show", :id => @post.id, :tag_title => @post.tag_title}, :api => {:post_id => @post.id, :location => url_for(:controller => "post", :action => "show", :id => @post.id)})
      end
    elsif @post.errors.invalid?(:md5)
      p = Post.find_by_md5(@post.md5)

      update = { :tags => p.cached_tags + " " + params[:post][:tags], :updater_user_id => session[:user_id], :updater_ip_addr => request.remote_ip }
      update[:source] = @post.source if p.source.blank? && !@post.source.blank?
      p.update_attributes(update)

      respond_to_error("Post already exists", {:controller => "post", :action => "show", :id => p.id, :tag_title => @post.tag_title}, :api => {:location => url_for(:controller => "post", :action => "show", :id => p.id)}, :status => 423)
    else
      respond_to_error(@post, :action => "upload")
    end
  end

  def moderate
    if request.post?
      Post.transaction do
        if params[:ids]
          params[:ids].keys.each do |post_id|
            if params[:commit] == "Approve"
              post = Post.find(post_id)
              post.approve!(@current_user.id)
            elsif params[:commit] == "Delete"
              Post.destroy_with_reason(post_id, params[:reason] || params[:reason2], @current_user)
            end
          end
        end
      end

      if params[:commit] == "Approve"
        respond_to_success("Post approved", {:action => "moderate"})
      elsif params[:commit] == "Delete"
        respond_to_success("Post deleted", {:action => "moderate"})
      end
    else
      if params[:query]
        @pending_posts = Post.find_by_sql(Post.generate_sql(params[:query], :pending => true, :order => "id desc"))
        @flagged_posts = Post.find_by_sql(Post.generate_sql(params[:query], :flagged => true, :order => "id desc"))
      else
        @pending_posts = Post.find(:all, :conditions => "status = 'pending'", :order => "id desc")
        @flagged_posts= Post.find(:all, :conditions => "status = 'flagged'", :order => "id desc")
      end
    end
  end

  def update
    @post = Post.find(params[:id])
    user_id = @current_user.id

    if @post.update_attributes(params[:post].merge(:updater_user_id => user_id, :updater_ip_addr => request.remote_ip))
      # Reload the post to send the new status back; not all changes will be reflected in
      # @post due to after_save changes.
      @post.reload
      respond_to_success("Post updated", {:action => "show", :id => @post.id, :tag_title => @post.tag_title}, :api => {:post => @post})
    else
      respond_to_error(@post, :action => "show", :id => params[:id])
    end
  end

  def delete
    @post = Post.find(params[:id])
    
    if @post && @post.parent_id
      @post_parent = Post.find(@post.parent_id)
    end
  end
  
  def destroy
    if params[:commit] == "Cancel"
      redirect_to :action => "show", :id => params[:id]
      return
    end
  
    @post = Post.find(params[:id])

    if @current_user.is_janitor_or_higher?
      if @post.status == "deleted"
        @post.delete_from_database
      else
        Post.destroy_with_reason(@post.id, params[:reason], @current_user)
      end

      respond_to_success("Post deleted", :action => "index")
    else
      access_denied()
    end
  end
  
  def deleted_index
    if params[:user_id]
      @posts = Post.paginate(:per_page => 25, :order => "flagged_post_details.created_at DESC", :joins => "JOIN flagged_post_details ON flagged_post_details.post_id = posts.id", :select => "flagged_post_details.reason, posts.cached_tags, posts.id, posts.user_id", :conditions => ["posts.status = 'deleted' AND posts.user_id = ? ", params[:user_id]], :page => params[:page])
    else
      @posts = Post.paginate(:per_page => 25, :order => "flagged_post_details.created_at DESC", :joins => "JOIN flagged_post_details ON flagged_post_details.post_id = posts.id", :select => "flagged_post_details.reason, posts.cached_tags, posts.id, posts.user_id", :conditions => ["posts.status = 'deleted'"], :page => params[:page])
    end
  end

  def index
    tags = params[:tags].to_s
    split_tags = QueryParser.parse(tags)
    page = params[:page].to_i
    limit = params[:limit].to_i
    limit = 20 if limit == 0
    limit = 1000 if limit > 1000
    count = 0
    
    if @current_user.is_member_or_lower? && split_tags.size > 2
      respond_to_error("You can only search up to two tags at once with a basic account", :action => "index")
      return
    elsif split_tags.size > 6
      respond_to_error("You can only search up to six tags at once", :action => "index")
      return
    end
    
    begin
      count = Post.fast_count(tags)
    rescue => x
      respond_to_error("Error: #{x}", :action => "index")
      return
    end

    set_title "/" + tags.tr("_", " ")

    if count < 20 && split_tags.size == 1 && !split_tags[0].include?("_")
      # TODO: Am I double escaping here?
      search_for = split_tags[0].to_escaped_for_sql_like
      @tag_suggestions = Tag.find(:all, :conditions => ["(name LIKE ? OR name LIKE ?) AND name <> ?", "%" + search_for, search_for + "%", split_tags[0]], :order => "post_count DESC", :limit => 6, :select => "name").map(&:name).sort
    end
    
    @ambiguous_tags = Tag.select_ambiguous(split_tags)
    
    @posts = WillPaginate::Collection.create(page, limit, count) do |pager|
      pager.replace(Post.find_by_sql(Post.generate_sql(tags, :order => "p.id DESC", :offset => pager.offset, :limit => pager.per_page)))
    end

    respond_to do |fmt|
      fmt.html do        
        if split_tags.any?
          @tags = Tag.parse_query(tags)
        elsif CONFIG["enable_caching"]
          @tags = Cache.get("$poptags", 1.hour) do
            {:include => Tag.count_by_period(1.day.ago, Time.now, :limit => 25)}
          end
        else
          @tags = {:include => Tag.count_by_period(1.day.ago, Time.now, :limit => 25)}
        end
      end
      fmt.xml do
        render :layout => false
      end
      fmt.json {render :json => @posts.to_json}
    end
  end

  def atom
    @posts = Post.find_by_sql(Post.generate_sql(params[:tags], :limit => 20, :order => "p.id DESC"))
    headers["Content-Type"] = "application/atom+xml"
    render :layout => false
  end

  def piclens
    @posts = WillPaginate::Collection.create(params[:page], 20, Post.fast_count(params[:tags])) do |pager|
      pager.replace(Post.find_by_sql(Post.generate_sql(params[:tags], :order => "p.id DESC", :offset => pager.offset, :limit => pager.per_page)))
    end
    
    headers["Content-Type"] = "application/rss+xml"
    render :layout => false
  end

  def show
    begin
      if params[:md5]
        @post = Post.find_by_md5(params[:md5].downcase) || raise(ActiveRecord::RecordNotFound)
      else
        @post = Post.find(params[:id])
      end
      
      @pools = Pool.find(:all, :joins => "JOIN pools_posts ON pools_posts.pool_id = pools.id", :conditions => "pools_posts.post_id = #{@post.id}", :order => "pools.name", :select => "pools.name, pools.id")
      @tags = {:include => @post.cached_tags.split(/ /)}
      set_title @post.cached_tags.tr("_", " ")
    rescue ActiveRecord::RecordNotFound
      render :action => "show_empty", :status => 404
    end
  end

  def popular_by_day
    if params[:year] && params[:month] && params[:day]
      @day = Time.gm(params[:year].to_i, params[:month], params[:day])
    else
      @day = Time.new.getgm.at_beginning_of_day
    end

    set_title "Exploring #{@day.year}/#{@day.month}/#{@day.day}"

    @posts = Post.find(:all, :conditions => ["posts.created_at >= ? AND posts.created_at <= ? ", @day, @day.tomorrow], :order => "score DESC", :limit => 20)

    respond_to_list("posts")
  end

  def popular_by_week
    if params[:year] && params[:month] && params[:day]
      @start = Time.gm(params[:year].to_i, params[:month], params[:day]).beginning_of_week
    else
      @start = Time.new.getgm.beginning_of_week
    end

    @end = @start.next_week

    set_title "Exploring #{@start.year}/#{@start.month}/#{@start.day} - #{@end.year}/#{@end.month}/#{@end.day}"

    @posts = Post.find(:all, :conditions => ["posts.created_at >= ? AND posts.created_at < ? ", @start, @end], :order => "score DESC", :limit => 20)

    respond_to_list("posts")
  end

  def popular_by_month
    if params[:year] && params[:month]
      @start = Time.gm(params[:year].to_i, params[:month], 1)
    else
      @start = Time.new.getgm.beginning_of_month
    end

    @end = @start.next_month

    set_title "Exploring #{@start.year}/#{@start.month}"

    @posts = Post.find(:all, :conditions => ["posts.created_at >= ? AND posts.created_at < ? ", @start, @end], :order => "score DESC", :limit => 20)

    respond_to_list("posts")
  end

  def revert_tags
    user_id = @current_user.id
    @post = Post.find(params[:id])
    @post.update_attributes(:tags => PostTagHistory.find(params[:history_id].to_i).tags, :updater_user_id => user_id, :updater_ip_addr => request.remote_ip)

    respond_to_success("Tags reverted", :action => "show", :id => @post.id, :tag_title => @post.tag_title)
  end

  def vote
    p = Post.find(params[:id])
    score = params[:score].to_i
    
    begin
      p.vote!(@current_user, score, request.remote_ip)
      respond_to_success("Vote saved", {:action => "show", :id => params[:id], :tag_title => p.tag_title}, :api => {:score => p.score, :post_id => p.id})
    rescue PostVoteMethods::InvalidScoreError
      respond_to_error("Invalid score", {:action => "show", :id => params[:id], :tag_title => p.tag_title}, :status => 424)
    rescue PostVoteMethods::AlreadyVotedError
      respond_to_error("Already voted", {:action => "show", :id => params[:id], :tag_title => p.tag_title}, :status => 423)
    end
  end

  def flag
    post = Post.find(params[:id])
    if post.status != "active"
      respond_to_error("Can only flag active posts", :action => "show", :id => params[:id])
      return
    end

    post.flag!(params[:reason], @current_user.id)
    respond_to_success("Post flagged", :action => "show", :id => params[:id])
  end
  
  def random
    max_id = Post.maximum(:id)
    
    10.times do
      post = Post.find(:first, :conditions => ["id = ? AND status <> 'deleted'", rand(max_id) + 1], :select => "id, cached_tags, status")

      if post != nil && post.can_be_seen_by?(@current_user)
        redirect_to :action => "show", :id => post.id, :tag_title => post.tag_title
        return
      end
    end
    
    flash[:notice] = "Couldn't find a post in 10 tries. Try again."
    redirect_to :action => "index"
  end
  
  def undelete
    post = Post.find(params[:id])
    post.undelete!
    respond_to_success("Post was undeleted", :action => "show", :id => params[:id])
  end
  
  def exception
    raise "error"
  end
end

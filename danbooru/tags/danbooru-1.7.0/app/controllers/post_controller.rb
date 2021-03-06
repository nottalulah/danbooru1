# For API documentation, consult http://miezaru.donmai.us/help/api

class PostController < ApplicationController
  layout 'default'

  verify :method => :post, :only => [:update, :destroy, :create, :revert_tags, :vote], :render => {:nothing => true}

  if CONFIG["enable_anonymous_post_access"]
    if CONFIG["enable_anonymous_post_uploads"]
      before_filter :user_only, :only => [:destroy]
    else
      before_filter :user_only, :only => [:destroy, :create, :upload]
    end
  else
    before_filter :user_only
  end

  if CONFIG["enable_caching"]
    around_filter :cache_action, :only => [:index, :atom]
  end

  before_filter :admin_only, :only => [:moderate]
  after_filter :save_tags_to_cookie, :only => [:update, :create]
  helper :wiki, :tag, :comment, :pool, :favorite

  def create
		if @current_user && @current_user.view_only?
			respond_to do |fmt|
				fmt.html {flash[:notice] = "Your account has been blocked from uploading new posts."; redirect_to(:controller => "post", :action => "index")}
				fmt.js {render :json => {:success => false, :reason => "account blocked"}.to_json}
				fmt.xml {render :xml => {:success => false, :reason => "account blocked"}.to_xml(:root => "response")}
			end
			return
		end
		
		if @current_user
			user_id = @current_user.id
		else
			user_id = nil
		end
    
    logger.info "COMMIT TAGS: params[:post][:tags]=#{params[:post][:tags]}"

    @post = Post.create(params[:post].merge(:updater_user_id => user_id, :updater_ip_addr => request.remote_ip, :user_id => user_id, :ip_addr => request.remote_ip))

    if @post.errors.empty?
      if params[:md5] && @post.md5 != params[:md5].downcase
        @post.destroy
        respond_to do |fmt|
          fmt.html {flash[:notice] = "MD5 mismatch"; redirect_to(:controller => "post", :action => "index")}
          fmt.xml {render :xml => {:success => false, :reason => "md5 mismatch"}.to_xml(:root => "response")}
          fmt.js {render :json => {:success => false, :reason => "md5 mismatch"}.to_json}
        end
      else
        respond_to do |fmt|
          fmt.html {flash[:notice] = "Post successfully uploaded"; redirect_to(:controller => "post", :action => "show", :id => @post.id)}
          fmt.xml {render :xml => {:success => true, :location => url_for(:controller => "post", :action => "show", :id => @post.id)}.to_xml(:root => "response")}
          fmt.js {render :json => {:success => true, :location => url_for(:controller => "post", :action => "show", :id => @post.id)}.to_json}
        end
      end
    elsif @post.errors.invalid?(:md5)
      p = Post.find_by_md5(@post.md5)

			if p.source.blank? && !@post.source.blank?
				p.update_attributes(:source => @post.source, :updater_user_id => session[:user_id], :updater_ip_addr => request.remote_ip, :tags => p.cached_tags + " " + params[:post][:tags])
      else
        p.update_attributes(:tags => p.cached_tags + " " + params[:post][:tags], :updater_user_id => session[:user_id], :updater_ip_addr => request.remote_ip, :rating => params[:post][:rating])
			end

      respond_to do |fmt|
        fmt.html {flash[:notice] = "That post already exists"; redirect_to(:controller => "post", :action => "show", :id => p.id)}
        fmt.xml {render :xml => {:success => false, :reason => "duplicate", :location => url_for(:controller => "post", :action => "show", :id => p.id)}.to_xml(:root => "response")}
        fmt.js {render :json => {:success => false, :reason => "duplicate", :location => url_for(:controller => "post", :action => "show", :id => p.id)}.to_json}
      end
    else
      respond_to do |fmt|
        fmt.html {render_error(@post)}
        fmt.xml {render :xml => {:success => false, :reason => @post.errors.full_messages.join(" ")}.to_xml(:root => "response"), :status => 500}
        fmt.js {render :json => {:success => false, :reason => @post.errors.full_messages.join(" ")}.to_json, :status => 500}
      end
    end
  end

  def upload #:nodoc:
    @post = Post.new
  end

  def moderate
    if request.post?
      @posts = Post.find(:all, :conditions => ["id in (?)", params[:ids].keys])
      @posts.each do |post|
        if params[:commit] == "Unflag"
          post.update_attribute(:is_flagged, false)
        else
          post.destroy
        end
      end

      redirect_to :action => "moderate"
    else
      @posts = Post.find(:all, :conditions => "is_flagged = TRUE", :order => "id")
    end
  end

  def update
    @post = Post.find(params[:id])
		if @current_user
    	user_id = @current_user.id
		else
			user_id = nil
		end

    # Make sure this gets assigned first in case we want to change this and change the post's rating at once.
    @post.is_rating_locked = params[:post][:is_rating_locked] if params[:post][:is_rating_locked]

    if @post.update_attributes(params[:post].merge(:updater_user_id => user_id, :updater_ip_addr => request.remote_ip))
      respond_to do |fmt|
        fmt.html {flash[:notice] = "Post updated"; redirect_to(:action => "show", :id => @post.id)}
        fmt.xml {render :xml => {:success => true}.to_xml(:root => "response")}
        fmt.js {render :json => {:success => true}.to_json}
      end
    else
      respond_to do |fmt|
        fmt.html {render_error(@post)}
        fmt.xml {render :xml => {:success => false, :reason => @post.errors.full_messages.join(" ")}.to_xml(:root => "response"), :status => 500}
        fmt.js {render :json => {:success => false, :reason => @post.errors.full_messages.join(" ")}.to_json, :status => 500}
      end
    end
  end

  def destroy
		if params[:commit] == "Cancel"
			redirect_to :action => "show", :id => params[:id]
			return
		end
	
    @post = Post.find(params[:id])
    if @current_user.has_permission?(@post)
      @post.destroy
    end

    respond_to do |fmt|
      fmt.html {flash[:notice] = "Post deleted"; redirect_to(:action => "index")}
      fmt.xml {render :xml => {:success => true}.to_xml(:root => "response")}
      fmt.js {render :json => {:success => true}.to_json}
    end
  end

  def index
    set_title "/#{params[:tags]}"

    if @current_user == nil && CONFIG["enable_multi-tag_search_for_anonymous"] == false && params[:tags].to_s.include?(" ")
      flash[:notice] = "You must be logged in to search for more than one tag at a time."
      redirect_to :controller => "user", :action => "login"
      return
    end

    limit = params[:limit].to_i
    if limit == 0 || limit > 100
      limit = 15
    end

    @ambiguous = Tag.select_ambiguous(params[:tags])
    @pages = Paginator.new(self, Post.fast_count(params[:tags], is_safe_mode?), limit, params[:page])
    @posts = Post.find_by_sql(Post.generate_sql(params[:tags], :order => "p.id DESC", :offset => @pages.current.offset, :limit => @pages.items_per_page, :safe_mode => is_safe_mode?))

    if @posts.empty? && !params[:tags].blank? && CONFIG["enable_suggestions_on_no_results"]
      @suggestions = Tag.find(:all, :conditions => ["name LIKE ? ESCAPE '\\\\'", "%" + params[:tags].to_escaped_for_sql_like + "%"], :order => "name").map {|x| x.name}
    else
      @suggestions = []
    end

    respond_to do |fmt|
      fmt.html do
        if params[:tags]
          @tags = Tag.parse_query(params[:tags])
        else
          @tags = {:include => Tag.count_by_period(3.days.ago, Time.now, :limit => 25, :safe_mode => is_safe_mode?)}
        end
      end
      fmt.xml {render :xml => @posts.to_xml}
      fmt.js {render :json => @posts.to_json}
    end
  end

  def atom #:nodoc:
    @posts = Post.find_by_sql(Post.generate_sql(params[:tags], :limit => 24, :order => "p.id DESC", :safe_mode => is_safe_mode?))
    render :layout => false
  end

  def show #:nodoc:
    begin
      @post = Post.find(params[:id])
      if is_safe_mode? && @post.rating != 's'
        flash[:notice] = "You must be logged in to view this post"
        redirect_to :controller => "user", :action => "login"
        return
      end
      @tags = {:include => @post.cached_tags.split(/ /)}
      set_title @post.cached_tags
    rescue ActiveRecord::RecordNotFound
      flash.now[:notice] = "That post ID was not found"
      @post = nil
    end
  end

  def popular_by_day
    if params[:year] && params[:month] && params[:day]
      @day = Time.gm(params[:year].to_i, params[:month], params[:day])
    else
      @day = Time.new.getgm.at_beginning_of_day
    end

    set_title "Exploring #{@day.year}/#{@day.month}/#{@day.day}"

    @posts = Post.find(:all, :conditions => ["posts.created_at >= ? AND posts.created_at <= ?", @day, @day.tomorrow], :order => "score DESC", :limit => 20, :include => [:user])
    respond_to do |fmt|
      fmt.html
      fmt.xml {render :xml => @posts.to_xml}
      fmt.js {render :json => @posts.to_json}
    end
  end

  def popular_by_week
    if params[:year] && params[:month] && params[:day]
      @start = Time.gm(params[:year].to_i, params[:month], params[:day]).beginning_of_week
    else
      @start = Time.new.getgm.beginning_of_week
    end

    @end = @start.next_week

    set_title "Exploring #{@start.year}/#{@start.month}/#{@start.day} - #{@end.year}/#{@end.month}/#{@end.day}"

    @posts = Post.find(:all, :conditions => ["posts.created_at >= ? AND posts.created_at < ?", @start, @end], :order => "score DESC", :limit => 20, :include => [:user])

    respond_to do |fmt|
      fmt.html
      fmt.xml {render :xml => @posts.to_xml}
      fmt.js {render :json => @posts.to_json}
    end
  end

  def popular_by_month
    if params[:year] && params[:month]
      @start = Time.gm(params[:year].to_i, params[:month], 1)
    else
      @start = Time.new.getgm.beginning_of_month
    end

    @end = @start.next_month

    set_title "Exploring #{@start.year}/#{@start.month}"

    @posts = Post.find(:all, :conditions => ["posts.created_at >= ? AND posts.created_at < ?", @start, @end], :order => "score DESC", :limit => 20, :include => [:user])

    respond_to do |fmt|
      fmt.html
      fmt.xml {render :xml => @posts.to_xml}
      fmt.js {render :json => @posts.to_json}
    end
  end

  def revert_tags
    user_id = @current_user.id rescue nil
    @post = Post.find(params[:id])
    @post.update_attributes(:tags => @post.tag_history.find(params[:history_id]).tags, :updater_user_id => user_id, :updater_ip_addr => request.remote_ip)

    respond_to do |fmt|
      fmt.html {flash[:notice] = "Tags reverted"; redirect_to(:action => "show", :id => @post.id)}
      fmt.xml {render :xml => {:success => true}.to_xml(:root => "response")}
      fmt.js {render :json => {:success => true}.to_json}
    end
  end

  def tag_history
    set_title "Tag History"

		params[:limit] ||= 100
    params[:limit] = params[:limit].to_i

    if params[:post_id]
      conditions = ["post_id = ?", params[:post_id]]
    else
      conditions = nil
    end

    respond_to do |fmt|
      fmt.html {@pages, @changes = paginate :post_tag_histories, :order => "id DESC", :per_page => params[:limit], :conditions => conditions}
      fmt.xml {render :xml => PostTagHistory.find(:all, :limit => params[:limit], :offset => params[:offset], :order => "id DESC", :conditions => conditions).to_xml}
      fmt.js {render :json => PostTagHistory.find(:all, :limit => params[:limit], :offset => params[:offset], :order => "id DESC", :conditions => conditions).to_json}
    end
  end

  def favorites
    set_title "Users who favorited this post"
    @post = Post.find(params["id"])
    @users = User.find_people_who_favorited(params["id"])

    respond_to do |fmt|
      fmt.html
      fmt.xml {render :xml => @users.to_xml}
      fmt.js {render :json => @users.to_json}
    end
  end

  def vote
    p = Post.find(params[:id])
    score = params[:score].to_i

    unless score == 1 || score == -1
      respond_to do |fmt|
        fmt.html {flash[:notice] = "Invalid score"; redirect_to(:action => "show", :id => params[:id])}
        fmt.xml {render :xml => {:success => false, :reason => "invalid score"}.to_xml(:root => "response"), :status => 409}
        fmt.js {render :json => {:success => false, :reason => "invalid score"}.to_json, :status => 409}
      end
      return
    end

    if p.vote!(score, request.remote_ip)
      respond_to do |fmt|
        fmt.html {flash[:notice] = "Vote saved"; redirect_to(:action => "show", :id => params[:id])}
        fmt.xml {render :xml => {:success => true, :score => p.score, :post_id => p.id}.to_xml(:root => "response")}
        fmt.js {render :json => {:success => true, :score => p.score, :post_id => p.id}.to_json}
      end
    else
      respond_to do |fmt|
        fmt.html {flash[:notice] = "You've already voted for this post"; redirect_to(:action => "show", :id => params[:id])}
        fmt.xml {render :xml => {:success => false, :reason => "already voted"}.to_xml(:root => "response"), :status => 409}
        fmt.js {render :json => {:success => false, :reason => "already voted"}.to_json, :status => 409}
      end
    end
  end

	def delete
		@post = Post.find(params[:id])
	end
end

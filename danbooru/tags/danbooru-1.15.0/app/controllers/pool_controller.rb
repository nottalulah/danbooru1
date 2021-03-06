class PoolController < ApplicationController
  layout "default"
  before_filter :member_only, :only => [:create, :destroy, :update]
  helper :post
  
  def index
    if params[:query]
      @pools = Pool.paginate :order => "updated_at desc", :conditions => ["lower(name) like ?", "%" + params[:query].to_escaped_for_sql_like + "%"], :per_page => 20, :page => params[:page]
    else
      @pools = Pool.paginate :order => "updated_at desc", :per_page => 20, :page => params[:page]
    end
    
    respond_to_list("pools")
  end
  
  def show
    @pool = Pool.find(params[:id])
    @posts = Post.paginate :per_page => 24, :order => "pools_posts.sequence, pools_posts.post_id", :joins => "JOIN pools_posts ON posts.id = pools_posts.post_id", :conditions => ["pools_posts.pool_id = ? AND posts.status <> 'deleted'", params[:id]], :select => "posts.*", :page => params[:page]

    respond_to do |fmt|
      fmt.html
      fmt.xml do
        builder = Builder::XmlMarkup.new(:indent => 2)
        builder.instruct!

        xml = @pool.to_xml(:builder => builder, :skip_instruct => true) do
          builder.posts do
            @posts.each do |post|
              post.to_xml(:builder => builder, :skip_instruct => true)
            end
          end
        end
        render :xml => xml
      end
    end
  end

  def update
    @pool = Pool.find(params[:id])

    unless @pool.can_be_updated_by?(@current_user)
      access_denied()
      return
    end

    if request.post?
      @pool.update_attributes(params[:pool])
      respond_to_success("Pool updated", :action => "show", :id => params[:id])
    end
  end
  
  def create
    if request.post?
      @pool = Pool.create(params[:pool].merge(:user_id => @current_user.id))
      
      if @pool.errors.empty?
        respond_to_success("Pool created", :action => "show", :id => @pool.id)
      else
        respond_to_error(@pool, :action => "index")
      end
    else
      @pool = Pool.new(:user_id => @current_user.id)
    end
  end
  
  def destroy
    @pool = Pool.find(params[:id])

    if request.post?
      if @pool.can_be_updated_by?(@current_user)
        @pool.destroy
        respond_to_success("Pool deleted", :action => "index")
      else
        access_denied()
      end
    end
  end
  
  def add_post
    if request.post?
      @pool = Pool.find(params[:pool_id])
      session[:last_pool_id] = @pool.id
      
      if params[:pool] && !params[:pool][:sequence].blank?
        sequence = params[:pool][:sequence]
      else
        sequence = nil
      end
      
      begin
        @pool.add_post(params[:post_id], :sequence => sequence, :user => @current_user)
        respond_to_success("Post added", :controller => "post", :action => "show", :id => params[:post_id])
      rescue Pool::PostAlreadyExistsError
        respond_to_error("Post already exists", {:controller => "post", :action => "show", :id => params[:post_id]}, :status => 423)
      rescue Pool::AccessDeniedError
        access_denied()
      rescue Exception => x
        respond_to_error(x.class, :controller => "post", :action => "show", :id => params[:post_id])
      end
    else
      if @current_user.is_anonymous?
        @pools = Pool.find(:all, :order => "name", :conditions => "is_active = TRUE AND is_public = TRUE")
      else
        @pools = Pool.find(:all, :order => "name", :conditions => ["is_active = TRUE AND (is_public = TRUE OR user_id = ?)", @current_user.id])
      end
      
      @post = Post.find(params[:post_id])
    end
  end
  
  def remove_post
    if request.post?
      @pool = Pool.find(params[:pool_id])
      
      begin
        @pool.remove_post(params[:post_id], :user => @current_user)
      rescue Pool::AccessDeniedError
        access_denied()
        return
      end
      
      response.headers["X-Post-Id"] = params[:post_id]
      respond_to_success("Post removed", :controller => "post", :action => "show", :id => params[:post_id])
    else
      @pool = Pool.find(params[:pool_id])
      @post = Post.find(params[:post_id])
    end
  end
  
  def order
    @pool = Pool.find(params[:id])

    unless @pool.can_be_updated_by?(@current_user)
      access_denied()
      return
    end

    if request.post?
      PoolPost.transaction do
        params[:pool_post_sequence].each do |i, seq|
          PoolPost.update(i, :sequence => seq)
        end
        
        @pool.reload
        @pool.update_pool_links
      end
      
      flash[:notice] = "Ordering updated"
      redirect_to :action => "show", :id => params[:id]
    else
      @pool_posts = PoolPost.find(:all, :conditions => ["pool_id = ?", params[:id]], :order => "sequence, post_id")
    end
  end
  
  def import
    @pool = Pool.find(params[:id])
    
    unless @pool.can_be_updated_by?(@current_user)
      access_denied()
      return
    end
    
    if request.post?
      if params[:posts].is_a?(Hash)
        ordered_posts = params[:posts].sort { |a,b| a[1]<=>b[1] }.map { |a| a[0] }

        PoolPost.transaction do
          ordered_posts.each do |post_id|
            begin
              @pool.add_post(post_id, :skip_update_pool_links => true)
            rescue Pool::PostAlreadyExistsError
              # ignore
            end
          end
          @pool.update_pool_links
        end
      end
      
      redirect_to :action => "show", :id => @pool.id
    else
      respond_to do |fmt|
        fmt.html
        fmt.js do
          @posts = Post.find_by_tags(params[:query], :order => "id desc", :limit => 500)
          @posts = @posts.select {|x| x.can_be_seen_by?(@current_user)}
        end
      end
    end
  end
  
  def select
    if @current_user.is_anonymous?
      @pools = Pool.find(:all, :order => "name", :conditions => "is_active = TRUE AND is_public = TRUE")
    else
      @pools = Pool.find(:all, :order => "name", :conditions => ["is_active = TRUE AND (is_public = TRUE OR user_id = ?)", @current_user.id])
    end
    
    render :layout => false
  end
end

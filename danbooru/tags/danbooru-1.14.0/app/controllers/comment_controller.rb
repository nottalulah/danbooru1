class CommentController < ApplicationController
  layout "default"

  verify :method => :post, :only => [:create, :destroy, :update, :mark_as_spam]
  before_filter :member_only, :only => [:create, :destroy, :update, :index, :show]
  before_filter :janitor_only, :only => [:moderate]

  def edit
    @comment = Comment.find(params[:id])
  end
  
  def update
    comment = Comment.find(params[:id])
    if @current_user.has_permission?(comment)
      comment.update_attributes(params[:comment])
      respond_to_success("Comment updated", {:action => "index"})
    else
      access_denied()
    end
  end

  def destroy
    comment = Comment.find(params[:id])
    if @current_user.has_permission?(comment)
      comment.destroy
      respond_to_success("Comment deleted", :controller => "post", :action => "show", :id => comment.post_id)
    else
      access_denied()
    end
  end

  def create
    if @current_user.is_member_or_lower? && params[:comment][:do_not_bump_post].blank? && Comment.count(:conditions => ["user_id = ? AND created_at > ?", @current_user.id, 1.hour.ago]) >= CONFIG["member_comment_limit"]
      # TODO: move this to the model
      respond_to_error("Hourly limit exceeded (check \"do not bump post\" to post more comments)", {:action => "index"}, :status => 421)
      return
    end

    if params[:commit] == "Post as Anonymous" && @current_user.is_privileged_or_higher?
      user_id = nil
    else
      user_id = session[:user_id]
    end

    comment = Comment.create(params[:comment].merge(:ip_addr => request.remote_ip, :user_id => user_id))
    if comment.errors.empty?
      respond_to_success("Comment created", :action => "index")
    else
      respond_to_error(comment, :action => "index")
    end
  end

  def show
    set_title "Comment"
    @comment = Comment.find(params[:id])

    respond_to_list("comment")
  end
  
  def index
    set_title "Comments"
    
    if params[:format] == "json" || params[:format] == "xml"
      @comments = Comment.paginate(Comment.generate_sql(params).merge(:per_page => 25, :page => params[:page], :order => "id DESC"))
      respond_to_list("comments")
    else
      @posts = Post.paginate :order => "last_commented_at DESC", :conditions => "last_commented_at IS NOT NULL AND status <> 'deleted'", :per_page => 10, :page => params[:page]
      @posts = @posts.select {|x| x.can_be_seen_by?(@current_user)}
    end
  end

  def moderate
    set_title "Moderate Comments"

    if request.post?
      ids = params["c"].keys
      coms = Comment.find(:all, :conditions => ["id IN (?)", ids])

      if params["commit"] == "Delete"
        coms.each do |c|
          c.destroy
        end
      elsif params["commit"] == "Approve"
        coms.each do |c|
          c.update_attribute(:is_spam, false)
        end
      end

      redirect_to :action => "moderate"
    else
      @comments = Comment.find(:all, :conditions => "is_spam = TRUE", :order => "id DESC")
    end
  end

  def mark_as_spam
    @comment = Comment.find(params[:id])
    @comment.update_attributes(:is_spam => true)
    respond_to_success("Comment marked as spam", :action => "index")
  end
end

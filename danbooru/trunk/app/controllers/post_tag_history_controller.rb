class PostTagHistoryController < ApplicationController
  layout 'default'
  before_filter :member_only, :only => [:revert, :undo]
  verify :method => :post, :only => [:undo]
  
  def index
    @changes = PostTagHistory.paginate(PostTagHistory.generate_sql(params).merge(:order => "id DESC", :per_page => 1000, :select => "post_tag_histories.*", :page => params[:page]))    
    @change_list = @changes.map do |c|
      { :parent_id => c.parent_id, :change => c, :ip_addr => c.ip_addr }.merge(c.tag_changes(c.previous))
    end
    
    respond_to_list("changes")
  end
  
  def revert
    @change = PostTagHistory.find(params[:id])
    @post = Post.find(@change.post_id)
    
    if request.post?
      @post.update_attributes(:updater_ip_addr => request.remote_ip, :updater_user_id => @current_user.id, :tags => @change.tags, :rating => @change.rating, :parent_id => @change.parent_id)
      respond_to_success("Tag changes reverted", :action => "index")
    end
  end

  def undo
    ids = params[:id].split(/,/)
    
    if ids.length > 1 && !@current_user.is_privileged_or_higher?
      respond_to_error("Only privileged users can undo more than one change at once", :status => 403)
      return
    end

    options = {
      :update_options => { :updater_ip_addr => request.remote_ip, :updater_user_id => @current_user.id }
    }

    ids.each do |id|
      @change = PostTagHistory.find(id)
      @change.undo(options)
    end

    options[:posts].each do |id, post|
      post.save!
    end

    respond_to_success("Tag changes undone", :action => "index")
  end
end

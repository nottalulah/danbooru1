class CommentController < ApplicationController
	layout "default"

	if CONFIG["enable_comment_spam_filter"]
		before_filter :spam_filter, :only => :create
	end
	
	if CONFIG["enable_anonymous_comment_access"]
		if CONFIG["enable_anonymous_comment_responses"]
			before_filter :user_only, :only => :destroy
		else
			before_filter :user_only, :only => [:create, :destroy]
		end
	else
		before_filter :user_only
	end

	before_filter :mod_only, :only => [:moderate]
	verify :method => :post, :only => [:create, :destroy, :mark_as_spam]

	def spam_filter
		return false unless params[:email].blank?
		return false if params[:comment][:body].scan(/http/).size > 2
		return true
	end

	def destroy
		comment = Comment.find(params[:id])
		if @current_user.has_permission?(comment)
			comment.destroy

			respond_to do |fmt|
				fmt.html {flash[:notice] = "Comment deleted"; redirect_to(:controller => "post", :action => "show", :id => comment.post_id)}
				fmt.xml {render :xml => {:success => true}.to_xml}
				fmt.js {render :json => {:success => true}.to_json}
			end
		else
			access_denied()
		end
	end	

	def create
		if params[:comment][:anonymous] == "1"
			user_id = nil
			params[:comment].delete(:anonymous)
		else
			user_id = session[:user_id]
		end

		comment = Comment.create(params[:comment].merge(:ip_addr => request.remote_ip, :user_id => user_id))
		if comment.errors.empty?
			respond_to do |fmt|
				fmt.html {flash[:notice] = "Comment added"; redirect_to(:action => "index")}
				fmt.xml {render :xml => {:success => true}.to_xml(:root => "response")}
				fmt.js {render :json => {:success => true}.to_json}
			end
		else
			error_messages = comment.errors.full_messages.join(", ")
			respond_to do |fmt|
				fmt.html {flash[:notice] = "Error: #{h(error_messages)}"; redirect_to(:action => "show", :id => comment.post_id)}
				fmt.xml {render :xml => {:success => false, :reason => h(error_messages)}.to_xml(:root => "response")}
				fmt.js {render :json => {:success => false, :reason => error_messages}.to_json}
			end
		end
	end

	def show
		set_title "Comment"
		@comment = Comment.find(params[:id])

		respond_to do |fmt|
			fmt.html 
			fmt.xml {render :xml => @comment.to_xml}
			fmt.js {render :json => @comment.to_json}
		end
	end

	def index
		set_title "Comments"

		cond = ["TRUE"]
		cond_params = []

		if params[:post_id]
			cond << "post_id = ?"
			cond_params << params[:post_id].to_i
		end

		respond_to do |fmt|
			fmt.html do
				@pages, @posts = paginate :posts, :order => "last_commented_at DESC", :conditions => "last_commented_at IS NOT NULL", :per_page => 10
			end
			fmt.xml {render :xml => Comment.find(:all, :conditions => [cond.join(" AND "), *cond_params], :limit => (params[:limit] || 25), :order => "id DESC", :offset => params[:offset]).to_xml}
			fmt.js {render :json => Comment.find(:all, :conditions => [cond.join(" AND "), *cond_params], :limit => (params[:limit] || 25), :order => "id DESC", :offset => params[:offset]).to_json}
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
			elsif params["commit"] == "Accept"
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
		comment = Comment.find(params[:id])

		if comment.is_spam == false
			respond_to do |fmt|
				fmt.html {flash[:notice] = "This comment has already been marked as not spam"; redirect_to(:controller => "post", :action => "show", :id => comment.post_id)}
				fmt.xml {render :xml => {:success => false, :reason => "not spam"}.to_xml, :status => 409}
				fmt.js {render :json => {:success => false, :reason => "not spam"}.to_json, :status => 409}
			end
		elsif comment.is_spam == nil
			comment.update_attribute(:is_spam, true)
			if comment.post.comments.size == 0
				comment.post.update_attribute(:last_commented_at, nil)
			end
			respond_to do |fmt|
				fmt.html {flash[:notice] = "Comment marked as spam"; redirect_to(:action => "index")}
				fmt.xml {render :xml => {:success => true}.to_xml}
				fmt.js {render :json => {:success => true}.to_json}
			end
		end
	end
end if CONFIG["enable_comments"]

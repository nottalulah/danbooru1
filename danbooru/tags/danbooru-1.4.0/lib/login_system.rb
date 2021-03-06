require_dependency "user"

module LoginSystem
	protected
	def access_denied
		respond_to do |fmt|
			fmt.html {flash[:notice] = "Access denied"; redirect_to(:controller => "user", :action => "login")}
			fmt.xml {render :xml => {:success => false, :reason => "access denied"}.to_xml, :status => 403}
			fmt.js {render :json => {:success => false, :reason => "access denied"}.to_json, :status => 403}
		end
	end

	def current_user
		if @current_user == nil && session[:user_id]
			@current_user = User.find(session[:user_id])
		end

		if @current_user == nil && params[:login] && params[:password_hash]
			@curent_user = User.authenticate_hash(params[:login], params["password_hash"])
		end

		if @current_user == nil && params[:login] && params["password"]
			@current_user = User.authenticate(params[:login], params["password"])
		end

		if @current_user == nil && cookies[:login] && cookies["pass_hash"]
			@current_user = User.authenticate_hash(cookies[:login], cookies["pass_hash"])
		end

		if @current_user == nil && params[:user]
			@current_user = User.authenticate(params[:user][:name], params[:user][:password])
		end

		if @current_user
			session[:user_id] = @current_user.id
		end

		return @current_user
	end

	def mod_only
		if @current_user && @current_user.role?(:mod)
			return true
		else
			access_denied
			return false
		end
	end

	def admin_only
		if @current_user && @current_user.role?(:admin)
			return true
		else
			access_denied
			return false
		end
	end

	def user_only
		if @current_user && @current_user.role?(:member)
			return true
		else
			access_denied
			return false
		end
	end

	def user_only_api
		if (current_user.role?(:member) rescue false)
			return true
		else
			render :text => "Only registered users can use this feature", :status => 403
			return false
		end
	end
end

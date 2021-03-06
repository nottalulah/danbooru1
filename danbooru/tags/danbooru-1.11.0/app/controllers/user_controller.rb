require 'digest/sha2'

class UserController < ApplicationController
  layout "default"
  verify :method => :post, :only => [:authenticate, :update, :create, :add_favorite, :delete_favorite]
  before_filter :blocked_only, :only => [:authenticate, :update, :edit]
  before_filter :privileged_only, :only => [:invites]
  before_filter :mod_only, :only => [:block_account]
  helper :post
  filter_parameter_logging :password
  auto_complete_for :user, :name

  protected
  def save_cookies(user)
    cookies[:login] = {:value => user.name, :expires => 1.year.from_now}
    cookies[:pass_hash] = {:value => user.password_hash, :expires => 1.year.from_now}
    session[:user_id] = user.id
  end

  public
  def auto_complete_for_member_name
    @users = User.find(:all, :order => "lower(name)", :conditions => ["level = ? AND name ilike ? escape '\\\\'", User::LEVEL_MEMBER, params[:member][:name] + "%"])
    render :layout => false, :text => "<ul>" + @users.map {|x| "<li>" + x.name + "</li>"}.join("") + "</ul>"
  end

  def show
    @user = User.find(params[:id])
  end
  
  def invites
    if request.post?
      if params[:member]
        if @current_user.invite_count < 1
          flash[:notice] = "You are out of invites"
        else
          user = User.find(:first, :conditions => ["lower(name) = lower(?)", params[:member][:name]])

          if user == nil
            flash[:notice] = "User #{params[:member][:name]} was not found"
            redirect_to :action => "invites"
            return
          end
          
          if UserRecord.count(:conditions => ["user_id = ? AND is_positive = false AND reported_by IN (SELECT id FROM users WHERE level >= ?)", user.id, User::LEVEL_MOD]) > 0 && !@current_user.mod?
            flash[:notice] = "This user has negative feedback on his record and can only be invited by a moderator"
            redirect_to :action => "invites"
            return
          end

          user.level = User::LEVEL_PRIVILEGED
          user.invited_by = @current_user.id
          User.transaction do
            user.save!
            @current_user.decrement! :invite_count
          end
          flash[:notice] = "You have invited #{CGI.escapeHTML(user.pretty_name)}"
        end
      end
      
      redirect_to :action => "invites"
    else
      @invited_users = User.find(:all, :conditions => ["invited_by = ?", @current_user.id], :order => "lower(name)")
    end
  end
  
  def home
    set_title "My Account"
  end

  def index
    set_title "Users"
    
    conds = []
    cond_params = []
    
    if params[:name]
      conds << "name ilike ? escape '\\\\'"
      cond_params << "%" + params[:name].to_escaped_for_sql_like + "%"
    end
    
    if params[:id]
      conds << "id = ?"
      cond_params << params[:id]
    end
    
    if params[:level] && params[:level] != "any"
      conds << "level = ?"
      cond_params << params[:level]
    end
    
    order = case params[:order]
    when "name"
      "lower(name)"
      
    when "posts"
      "(select count(*) from posts where user_id = users.id) desc"
      
    when "favorites"
      "(select count(*) from favorites where user_id = users.id) desc"
      
    when "notes"
      "(select count(*) from note_versions where user_id = users.id) desc"
      
    else
      "created_at desc"
    end
    
    conds << "true" if conds.empty?

    @pages, @users = paginate :users, :order => order, :conditions => [conds.join(" and "), *cond_params], :per_page => 20

    respond_to do |fmt|
      fmt.html
      fmt.xml {render :xml => @users.to_xml(:root => "users")}
      fmt.js {render :json => @users.to_json}
    end
  end

  def authenticate
    save_cookies(@current_user)
    @current_user.increment! :login_count
    
    respond_to do |fmt|
      fmt.html {flash[:notice] = "You are now logged in"; redirect_to(:action => "home")}
      fmt.xml {render :xml => {:success => true}.to_xml(:root => "response")}
      fmt.js {render :json => {:success => true}.to_json}
    end
  end

  def login
    set_title "Login"
  end

  def create
    user = User.new(params[:user])
    user.name = params[:user][:name]
    user.ip_addr = request.remote_ip
    user.save

    if user.errors.empty?
      save_cookies(user)

      if CONFIG["enable_account_email_activation"]
        UserMailer::deliver_confirmation_email(user, User.confirmation_hash(user.name))
        notice = "New account created. Confirmation email sent to #{user.email}"
      else
        notice = "New account created"
      end

      flash[:notice] = notice
      redirect_to :action => "home"
    else
      error = user.errors.full_messages.join(", ")
      flash[:notice] = "Error: " + error
      redirect_to :action => "signup"
    end
  end

  def signup
    set_title "Signup"
    @user = User.new
  end

  def logout
    set_title "Logout"
    session[:user_id] = nil
    cookies[:login] = nil
    cookies[:pass_hash] = nil

    respond_to do |fmt|
      fmt.html {flash[:notice] = "You are now logged out"; redirect_to(:action => "home")}
      fmt.xml {render :xml => {:success => true}.to_xml(:root => "response")}
      fmt.js {render :json => {:success => true}.to_json}
    end
  end

  def update
    if params[:commit] == "Cancel"
      redirect_to :action => "home"
      return
    end
    
    if @current_user.update_attributes(params[:user])
      flash[:notice] = "Account settings saved"
      redirect_to :action => "home"
    else
      error = @current_user.errors.full_messages.join(", ")
      flash[:notice] = "Error: " + error
      redirect_to :back
    end
  end

  def edit
    set_title "Edit Account"
    @user = @current_user
  end
  
  def reset_password
    set_title "Reset Password"

    if request.post?
      @user = User.find_by_name(params[:user][:name])
      
      if @user
        if @user.email.blank?
          flash[:notice] = "You never supplied an email address, therefore you cannot have your password automatically reset"
          redirect_to :action => "login"
        else
          new_password = @user.reset_password
          UserMailer.deliver_new_password(@user, new_password)

          flash[:notice] = "Password reset. Check your email in a few minutes"
          redirect_to :action => "login"
        end
      else
        flash[:notice] = "That account does not exist"
        redirect_to :action => "reset_password"
      end
    else
      @user = User.new
    end
  end
  
  def block_account
    @user = User.find(params[:id])
    
    if request.post?
      if @user.mod?
        flash[:notice] = "You can not ban other moderators or administrators"
        redirect_to :action => "block_account"
        return
      end
      
      @user.update_attribute(:level, User::LEVEL_BLOCKED)
      Ban.create(params[:ban].merge(:banned_by => @current_user.id))
      redirect_to :action => "show", :id => @user.id
    else
      @ban = Ban.new(:user_id => @user.id, :duration => "1")
    end
  end
  
  if CONFIG["enable_account_email_activation"]
    def resend_confirmation
      user = @current_user
      if user.activated?
        flash[:notice] = "Account already activated"
        redirect_to :action => "home"
        return
      end

      UserMailer::deliver_confirmation_email(user, User.confirmation_hash(user.name))
      flash[:notice] = "Confirmation email sent to #{user.email}"
      redirect_to :action => "home"
    end

    def activate_user
      if params["id"] !~ /\A[0-9a-f]{64}\Z/
        flash[:notice] = "Invalid confirmation code"
        redirect_to :action => "home"
        return
      end

      flash[:notice] = "Invalid confirmation code"
      
      users = User.find(:all, :conditions => ["level = ?", User::LEVEL_UNACTIVATED])
      users.each do |user|
        if User.confirmation_hash(user.name) == params["hash"]
          user.update_attribute(:level, User::LEVEL_MEMBER)
          flash[:notice] = "Account has been activated"
          break
        end
      end

      redirect_to :action => "home"
    end
  end
end

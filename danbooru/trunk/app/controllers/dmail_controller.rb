class DmailController < ApplicationController
  before_filter :blocked_only
  layout "default"
  
  def auto_complete_for_dmail_to_name
    @users = User.find(:all, :order => "lower(name)", :conditions => ["name ilike ? escape '\\\\'", params[:dmail][:to_name] + "%"])
    render :layout => false, :text => "<ul>" + @users.map {|x| "<li>" + x.name + "</li>"}.join("") + "</ul>"
  end
  
  def show_previous_messages
    @dmails = Dmail.find(:all, :conditions => ["parent_id = ? and id < ?", params[:parent_id], params[:id]], :order => "id asc")
    render :layout => false
  end
  
  def compose
    @dmail = Dmail.new
  end
  
  def create
    @dmail = Dmail.create(params[:dmail].merge(:from_id => @current_user.id))
    
    if @dmail.errors.empty?
      flash[:notice] = "Message sent to #{params[:dmail][:to_name]}"
      redirect_to :action => "inbox"
    else
      flash[:notice] = "Error: " + @dmail.errors.full_messages.join(", ")
      render :action => "compose"
    end
  end
  
  def inbox
    @dmails = Dmail.paginate :conditions => ["to_id = ? or from_id = ?", @current_user.id, @current_user.id], :order => "created_at desc", :per_page => 25, :page => params[:page]
  end
  
  def show
    @dmail = Dmail.find(params[:id])

    if @dmail.to_id != @current_user.id && @dmail.from_id != @current_user.id
      flash[:notice] = "Access denied"
      redirect_to :controller => "user", :action => "login"
      return
    end

    if @dmail.to_id == @current_user.id
      @dmail.update_attribute(:has_seen, true)
    
      unless Dmail.exists?(["has_seen = false and to_id = ?", @current_user.id])
        @current_user.update_attribute(:has_mail, false)
      end
    end
  end
end

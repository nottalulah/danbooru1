class WikiController < ApplicationController
  layout 'default'
  before_filter :member_only, :only => [:update, :create, :edit, :revert]
  before_filter :mod_only, :only => [:lock, :unlock, :destroy, :rename]
  verify :method => :post, :only => [:lock, :unlock, :destroy, :update, :create, :revert]

  def destroy
    page = WikiPage.find_page(params[:title])
    page.destroy
    respond_to_success("Page deleted", :action => "show", :title => params[:title])
  end

  def lock
    page = WikiPage.find_page(params[:title])
    page.lock!
    respond_to_success("Page locked", :action => "show", :title => params[:title])
  end

  def unlock
    page = WikiPage.find_page(params["title"])
    page.unlock!
    respond_to_success("Page unlocked", :action => "show", :title => params[:title])
  end

  def index
    set_title "Wiki"
    
    if params[:order] == "date"
      order = "updated_at"
    else
      order = "lower(title)"
    end
    
    limit = params[:limit] || 25

    if params[:query]
      query = params[:query].scan(/\S+/).join(" & ")
      @wiki_pages = WikiPage.paginate :order => order, :per_page => limit, :conditions => ["text_search_index @@ plainto_tsquery(?)", query], :page => params[:page]
    else
      @wiki_pages = WikiPage.paginate :order => order, :per_page => limit, :page => params[:page]
    end

    respond_to_list("wiki_pages")
  end

  def preview
    render :inline => "<%= wikilize(params[:body]) %>"
  end

  def add
    @wiki_page = WikiPage.new
    @wiki_page.title = params[:title] || "Title"
  end

  def create
    page = WikiPage.create(params[:wiki_page].merge(:ip_addr => request.remote_ip, :user_id => session[:user_id]))
    if page.errors.empty?
      respond_to_success("Page created", {:action => "show", :title => page.title}, :location => url_for(:action => "show", :title => page.title))
    else
      respond_to_error(page, :action => "index")
    end
  end

  def update
    @page = WikiPage.find_page(params[:title] || params[:wiki_page][:title])

    if @page.is_locked?
      respond_to_error("Page is locked", {:action => "show", :title => params[:title]}, :status => 422)
    else
      if @page.update_attributes(params[:wiki_page].merge(:ip_addr => request.remote_ip, :user_id => session[:user_id]))
        respond_to_success("Page created", :action => "show", :title => @page.title)
      else
        respond_to_error(@page)
      end
    end
  end

  def show
    if params[:title] == nil
      render :text => "no title specified"
      return
    end

    @page = WikiPage.find_page(params[:title], params[:version])
    set_title params[:title].tr("_", " ")
  end

  def edit
    if params[:title] == nil
      render :text => "no title specified"
    else
      @wiki_page = WikiPage.find_page(params[:title], params[:version])

      if @wiki_page == nil
        redirect_to :action => "add", :title => params[:title]
      end
    end
  end

  def revert
    @page = WikiPage.find_page(params[:title])

    if @page.is_locked?
      respond_to_error("Page is locked", {:action => "show", :title => params[:title]}, :status => 422)
    else
      @page.revert_to(params[:version])
      @page.ip_addr = request.remote_ip
      @page.user_id = @current_user.id

      if @page.save
        respond_to_success("Page reverted", :action => "show", :title => params[:title])
      else
        respond_to_error(@page)
      end
    end
  end

  def recent_changes
    set_title "Recent Changes"

    @wiki_pages = WikiPage.paginate :order => "updated_at DESC", :per_page => (params[:per_page] || 25), :page => params[:page]
    respond_to_list("wiki_pages")
  end

  def history
    set_title "Wiki History"

    @wiki_pages = WikiPageVersion.find(:all, :conditions => ["title = ?", params[:title]], :order => "updated_at DESC")

    respond_to_list("wiki_pages")
  end

  def diff
    set_title "Wiki Diff"

    if params[:redirect]
      redirect_to :action => "diff", :title => params[:title], :from => params[:from], :to => params[:to]
      return
    end

    if params[:title].blank? || params[:to].blank? || params[:from].blank?
      flash[:notice] = "No title was specificed"
      redirect_to :action => "index"
      return
    end

    @oldpage = WikiPage.find_page(params[:title], params[:from])
    @difference = @oldpage.diff(params[:to])
  end
  
  def rename
    @wiki_page = WikiPage.find_page(params[:title])
  end
end

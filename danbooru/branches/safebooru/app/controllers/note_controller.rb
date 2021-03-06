class NoteController < ApplicationController
  layout 'default', :only => [:index, :history, :search]
  before_filter :member_only, :only => [:destroy, :update, :revert]
  verify :method => :post, :only => [:update, :revert, :destroy]
  helper :post

  def search
    if params[:query]
      query = params[:query].scan(/\S+/).join(" & ")
      @notes = Note.paginate(Note.generate_sql(params).merge(:order => "id desc", :per_page => 25, :page => params[:page]))
      respond_to_list("notes")
    end    
  end
  
  def index
    set_title "Notes"
    
    if params[:post_id]
      @posts = Post.paginate :order => "last_noted_at DESC", :conditions => ["id = ? AND rating = 's'", params[:post_id]], :per_page => 100, :page => params[:page]
    else
      @posts = Post.paginate :order => "last_noted_at DESC", :conditions => "last_noted_at IS NOT NULL AND rating = 's'", :per_page => 16, :page => params[:page]
    end

    respond_to do |fmt|
      fmt.html
      fmt.xml {render :xml => @posts.map {|x| x.notes}.flatten.to_xml(:root => "notes")}
      fmt.json {render :json => @posts.map {|x| x.notes}.flatten.to_json}
    end
  end

  def history
    set_title "Note History"

    if params[:id]
      @notes = NoteVersion.paginate(:page => params[:page], :per_page => 25, :order => "id DESC", :conditions => ["note_id = ?", params[:id]])
    elsif params[:post_id]
      @notes = NoteVersion.paginate(:page => params[:page], :per_page => 50, :order => "id DESC", :conditions => ["post_id = ?", params[:post_id]])
    elsif params[:user_id]
      @notes = NoteVersion.paginate(:page => params[:page], :per_page => 50, :order => "id DESC", :conditions => ["user_id = ?", params[:user_id]])
    else
      @notes = NoteVersion.paginate(:page => params[:page], :per_page => 25, :order => "id DESC")
    end
    
    respond_to_list("notes")
  end

  def revert
    note = Note.find(params[:id])

    if note.is_locked?
      respond_to_error("Post is locked", {:action => "history", :id => note.id}, :status => 422)
      return
    end

    note.revert_to(params[:version])
    note.ip_addr = request.remote_ip
    note.user_id = @current_user.id

    if note.save
      respond_to_success("Note reverted", :action => "history", :id => note.id)
    else
      render_error(note)
    end
  end

  def update
    if params[:note][:post_id]
      note = Note.new(:post_id => params[:note][:post_id])
    else
      note = Note.find(params[:id])
    end

    if note.is_locked?
      respond_to_error("Post is locked", {:controller => "post", :action => "show", :id => note.post_id}, :status => 422)
      return
    end

    note.attributes = params[:note]
    note.user_id = @current_user.id
    note.ip_addr = request.remote_ip

    if note.save
      respond_to_success("Note updated", {:action => "index"}, :api => {:new_id => note.id, :old_id => params[:id].to_i, :formatted_body => HTML5Sanitizer::hs(note.formatted_body)})
    else
      respond_to_error(note, :controller => "post", :action => "show", :id => note.post_id)
    end
  end
end

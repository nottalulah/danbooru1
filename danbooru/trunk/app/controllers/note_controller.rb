class NoteController < ApplicationController
  layout 'default', :only => [:index, :history, :history_for_post]
  verify :method => :post, :only => [:change, :revert, :remove]
  helper :post

  if !CONFIG["enable_anonymous_note_edits"]
    before_filter :user_only, :only => [:remove, :change, :revert]
  end

# Show a paginated list of every note.
  def index
    set_title "Notes"

    if params[:post_id]
      @pages, @posts = paginate :posts, :order => "last_noted_at DESC", :conditions => ["post_id = ?", params[:post_id]], :per_page => 100
    else
      @pages, @posts = paginate :posts, :order => "last_noted_at DESC", :conditions => "last_noted_at IS NOT NULL", :per_page => 12
    end

    respond_to do |fmt|
      fmt.html
      fmt.xml {render :xml => @posts.to_xml}
      fmt.js {render :json => @posts.to_json}
    end
  end

# Show the history of a note if an id is supplied, otherwise show the history
# for all notes.
  def history
    set_title "Note History"

    if params[:id]
      @pages = Paginator.new self, NoteVersion.count(["note_id = ?", params[:id]]), 25, params[:page]
      @notes = NoteVersion.find(:all, :order => "id desc", :limit => @pages.items_per_page, :offset => @pages.current.offset, :conditions => ["note_id = ?", params[:id]])
    elsif params[:post_id]
      @pages = Paginator.new self, NoteVersion.count(["post_id = ?", params[:post_id]]), 50, params[:page]
      @notes = NoteVersion.find(:all, :order => "id desc", :conditions => ["post_id = ?", params[:post_id]])
    else
      @pages = Paginator.new self, NoteVersion.count, 25, params[:page]
      @notes = NoteVersion.find(:all, :order => "id desc", :limit => @pages.items_per_page, :offset => @pages.current.offset)
    end
  end

# Revert a note to a previous version.
  def revert
    note = Note.find(params["id"])

    if note.locked?
      flash[:notice] = "This post is locked and notes cannot be altered"
      redirect_to :action => "history", :id => note.id
      return
    end

    note.revert_to(params["version"])
    note.ip_addr = request.remote_ip

    if note.save_without_revision
      flash[:notice] = "Note reverted"
      redirect_to :action => "history", :id => note.id
    else
      render_error(note)
    end
  end

# save a note
  def change
    if params["note"]["post_id"]
      note = Note.new(:post_id => params["note"]["post_id"])
    else
      note = Note.find(params['id'])
    end

    if note.locked?
      render :text => "This post is locked and notes cannot be altered.", :status => 500
      return
    end

    note.attributes = params["note"]
    note.user_id = current_user.id rescue nil
    note.ip_addr = request.remote_ip

    if note.save
      render :json => {:new_id => note.id, :old_id => params[:id].to_i, :formatted_body => note.formatted_body}.to_json
    else
      render_error(note)
    end
  end

# Removes a note by setting its active flag to false.
  def remove
    note = Note.find(params['id'])

    if note.locked?
      render :text => "This post is locked and notes cannot be altered", :status => 500
      return
    end

    note.is_active = false
    note.ip_addr = request.remote_ip

    if note.save
      render :text => note.id.to_s
    else
      render_error(note)
    end
  end
end

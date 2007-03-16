class TagController < ApplicationController
	layout 'default'

	before_filter :admin_only, :only => [:create_alias, :destroy_alias, :create_implication, :destroy_implication]
	before_filter :mod_only, :only => [:batch_edit]

	def list
		redirect_to :action => "list_by_name"
	end

	def list_cloud
		set_title "Tags"

		@tags = Tag.find(:all, :conditions => "post_count > 0", :order => "post_count DESC", :limit => 100).sort {|a, b| a.name <=> b.name}
	end

	def list_artists
		set_title "Artist Tags"

		@tags = Tag.find(:all, :conditions => "tag_type = #{Tag::TYPE_ARTIST}", :order => "name")
	end

	def list_ambiguous
		set_title "Ambiguous Tags"

		@tags = Tag.find(:all, :conditions => "tag_type = #{Tag::TYPE_AMBIGUOUS}", :order => "name")
		render :action => "list_artists"
	end

	def list_copyrights
		set_title "Copyright Tags"
		@tags = Tag.find(:all, :conditions => "tag_type = #{Tag::TYPE_COPYRIGHT}", :order => "name")
		render :action => "list_artists"
	end

	def list_characters
		set_title "Character Tags"
		@tags = Tag.find(:all, :conditions => "tag_type = #{Tag::TYPE_CHARACTER}", :order => "name")
		render :action => "list_artists"
	end

	def list_by_name
		set_title "Tags by Name"
		@pages, @tags = paginate :tags, :order => "name", :per_page => 50
	end

	def list_by_created_at
		set_title "Tags by Creation Date"
		@pages, @tags = paginate :tags, :order => "id desc", :per_page => 50
		render :action => "list_by_name"
	end

	def list_by_count
		set_title "Tags by Post Count"
		@pages, @tags = paginate :tags, :order => "post_count desc", :per_page => 50
		render :action => "list_by_name"
	end

	def batch_edit
		set_title "Batch Edit"

		if request.post?
			if params["start"].blank?
				flash[:notice] = "You must fill the start tag field"
				redirect_to :action => "batch_edit"
				return
			end

			Post.find_by_sql(Post.generate_sql(params["start"])).each do |p|
				updated_tags = (p.cached_tags.split(/ /) - Tag.to_aliased(Tag.scan_tags(params["start"])) + Tag.to_aliased(Tag.scan_tags(params["result"]))).join(" ")
				p.update_attributes(:tags => updated_tags, :updater_user_id => session[:user_id], :updater_ip_addr => request.remote_ip)
			end

			flash[:notice] = "Tag changes saved"
			redirect_to :action => "batch_edit"
		end
	end

	def batch_edit_preview
		@posts = Post.find_by_sql(Post.generate_sql(params["tags"], :order => "p.id DESC"))
		render :layout => false
	end

	def destroy_alias
		TagAlias.destroy_all(["name = ?", params["name"]])
		Tag.update_cached_tags([params["name"]])
		flash[:notice] = "Tag alias deleted"
		redirect_to :action => "list_aliases"
	end

	def create_alias
		TagAlias.create(:name => params["name"], :alias => params["alias"])
		Tag.update_cached_tags([params["name"]])
		flash[:notice] = "Tag alias created"
		redirect_to :action => "list_aliases"
	end

	def destroy_implication
		TagImplication.destroy_all(["parent_id = ? and child_id = ?", params["parent_id"], params["child_id"]])
		flash[:notice] = "Tag implication deleted"
		redirect_to :action => "list_implications"
	end

	def create_implication
		TagImplication.create(:parent => params["parent"], :child => params["child"])
		flash[:notice] = "Tag implication created"
		redirect_to :action => "list_implications"
	end

	def list_aliases
		set_title "Tag Aliases"
		@aliases = TagAlias.find(:all, :order => "name")
	end

	def list_implications
		set_title "Tag Implications"
		@implications = TagImplication.find(:all, :order => "(SELECT name FROM tags WHERE id = tag_implications.child_id)")
	end

	def set_type
		if request.post?
			params["tags"].split(/,\s*/).each do |tag|
				t = Tag.find_or_create_by_name(tag)

				case params["type"]
				when "general"
					t.tag_type = 0

				else
					t.tag_type = Tag.const_get("Tag::TYPE_%s" % params["type"].upcase)
				end

				t.save
			end

			flash[:notice] = "Tag type changed"
			redirect_to :action => "set_type"
		end
	end

	def search
		set_title "Search Tags"

		if request.post?
			name = params["name"]

			case params["type"]
			when "search"
				escaped_name = name.gsub(/\\/, '\\\\').gsub(/%/, '\\%').gsub(/_/, '\\_')
				@tags = Tag.find(:all, :conditions => ["name LIKE ? ESCAPE '\\\\'", escaped_name.gsub(/^/, '%').gsub(/$/, '%').gsub(/ +/, '%')], :order => "name")

			when "artist"
				if name[/^http/]
					escaped_name = File.dirname(name).gsub(/\\/, '\\\\').gsub(/%/, '\\%').gsub(/_/, '\\_') + "%"
					@tags = Tag.find(:all, :conditions => ["id IN (SELECT tag_id FROM posts_tags WHERE post_id IN (SELECT id FROM posts WHERE source LIKE ? ESCAPE '\\\\')) AND tag_type = 1", escaped_name], :order => "name", :limit => 25)
				else
					@tags = Tag.find(:all, :conditions => ["id IN (SELECT tag_id FROM posts_tags WHERE post_id IN (SELECT post_id FROM posts_tags WHERE tag_id = (SELECT id FROM tags WHERE name = ?))) AND tag_type = 1", name], :order => "name", :limit => 25)
				end
			end
		end
	end
end

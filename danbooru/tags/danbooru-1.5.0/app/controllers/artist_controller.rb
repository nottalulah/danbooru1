class ArtistController < ApplicationController
	layout "default"

	before_filter :mod_only, :only => [:destroy]
	verify :method => :post, :only => [:destroy, :update, :create]

# Parameters
# - id: the ID number of the artist to delete
	def destroy
		artist = Artist.find(params[:id])
		artist.destroy

		respond_to do |fmt|
			fmt.html {flash[:notice] = "Artist deleted"; redirect_to(:action => "index", :page => params[:page])}
		end
	end

# Parameters
# - id: the ID number of the artist to update
# - artist[name]: the artist's name
# - artist[url_a]: base URL of the artist's home page
# - artist[url_b]: base URL of the site storing the artist's images
# - artist[url_c]: extra base URL
# - artist[alias]: artist this artist is an alias for
# - artist[group]: artist group this artist belongs to
	def update
		artist = Artist.find(params[:id])
		artist.update_attributes(params[:artist])

		if artist.errors.empty?
			respond_to do |fmt|
				fmt.html {flash[:notice] = "Artist entry updated"; redirect_to(:action => "show", :id => artist.id)}
				fmt.xml {render :xml => {:sucess => true}.to_xml}
				fmt.js {render :json => {:success => true}.to_json}
			end
		else
			respond_to do |fmt|
				fmt.html {flash[:notice] = "Error: " + errors; redirect_to(:action => "edit", :id => artist.id)}
				fmt.xml {render :xml => {:success => false, :reason => errors}.to_xml}
				fmt.js {render :json => {:success => false, :reason => errors}.to_json}
			end
		end
	end

# Parameters
# - artist[name]: the artist's name
# - artist[url_a]: base URL of the artist's home page
# - artist[url_b]: base URL of the site storing the artist's images
# - artist[url_c]: extra base URL
# - artist[alias]: artist this artist is an alias for
# - artist[group]: artist group this artist belongs to
	def create
		artist = Artist.create(params[:artist])

		if artist.errors.empty?
			respond_to do |fmt|
				fmt.html {flash[:notice] = "Artist created"; redirect_to(:action => "show", :id => artist.id)}
				fmt.xml {render :xml => {:success => true}.to_xml}
				fmt.js {render :json > {:success => true}.to_json}
			end
		else
			errors = artist.errors.full_messages.join(", ")
			respond_to do |fmt|
				fmt.html {flash[:notice] = "Error: " + errors; redirect_to(:action => "add", :alias_id => params[:alias_id])}
				fmt.xml {render :xml => {:success => false, :reason => errors}.to_xml}
				fmt.js {render :json => {:success => false, :reason => errors}.to_json}
			end
		end
	end

	def edit
		@artist = Artist.find(params["id"])
	end

	def add
		@artist = Artist.new

		if params[:alias_id]
			@artist.alias_id = params[:alias_id]
		end
	end

# Parameters
# - name: the artist's name. If you supply a URL beginning with http, Danbooru will search against the URL database. Danbooru will automatically progressively shorten the supplied URL until either a match is found or the string is too short (so you can supply direct links to images and Danbooru will find a match).
	def index
		if params[:name]
			name = params[:name]

			if name =~ /^http/
				@artists = []

				while @artists.empty? && name.size > 10
					escaped_name = name.gsub(/'/, "''").gsub(/\\/, '\\\\')
					@pages, @artists = paginate :artists, :conditions => "url_a LIKE '#{escaped_name}%' ESCAPE '\\\\' OR url_b LIKE '#{escaped_name}%' ESCAPE '\\\\' OR url_c LIKE '#{escaped_name}%' ESCAPE '\\\\'", :order => "name", :per_page => 25
					name = File.dirname(name)
				end
			else
				name = name.gsub(/'/, "''").gsub(/\\/, '\\\\')
				@pages, @artists = paginate :artists, :conditions => "name LIKE '%#{name}%' ESCAPE '\\\\'", :order => "name", :per_page => 25
			end
		else
			@pages, @artists = paginate :artists, :conditions => "name <> ''", :order => "name", :per_page => 25
		end

		respond_to do |fmt|
			fmt.html
			fmt.xml {render :xml => @artists.to_xml}
			fmt.js {render :json => @artists.to_json}
		end
	end

	def show
		@artist = Artist.find(params[:id])
	end
end

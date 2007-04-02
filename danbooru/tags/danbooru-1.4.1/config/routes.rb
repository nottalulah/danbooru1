ActionController::Routing::Routes.draw do |map|
	map.connect "", :controller => "static", :action => "index"
	map.connect "comment/*junk", :controller => "static", :action => "notfound" unless CONFIG["enable_comments"]
	map.connect ":controller/:action/:id.:format"
	map.connect ":controller/:action/:id"
	map.connect ":controller/:action.:format"
end

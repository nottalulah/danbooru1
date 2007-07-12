var db_page = 1
var db_offset = -1
var db_tags = ""
var db_posts = []
var db_on_load = null
var db_post_limit = 40

function db_notice(msg) {
	$("notice").innerHTML = msg
}

function db_decrement_offset() {
	db_offset -= 1
	if (db_offset == -1) {
		db_offset = db_post_limit
		db_page -= 1
		db_on_load = db_show_prev
		db_get_posts()
		return false
	}
	
	return true
}

function db_increment_offset() {
	db_offset += 1
	if (db_offset == db_post_limit) {
		db_offset = -1
		db_page += 1
		db_on_load = db_show_next
		db_get_posts()
		return false
	}
	
	return true
}

function db_curl_handler(output) {
	if (output.status == 0) {
		db_notice("")
		db_posts = eval(output.outputString)
		
		// preload the images
		var x = new Image()
		for (var i=0; i<db_posts.length; ++i) {
			x.src = db_posts[i].preview_url
		}
		
		if (db_on_load) {
			db_on_load()
			db_on_load = null
		}
	} else {
		db_notice("Error: curl failed")
	}
}

function db_get_posts() {
	if (window.widget) {
		db_notice("Getting page " + db_page + "...")	
		widget.system("/usr/bin/curl 'http://miezaru.donmai.us/post/index.js?limit=" + db_post_limit + "&page=" + db_page + "'", db_curl_handler)
	}
}

function db_show_prev() {
	if (db_decrement_offset()) {
		var post = db_posts[db_offset]
		$("image").src = post.preview_url
	}
}

function db_show_next() {
	if (db_increment_offset()) {
		var post = db_posts[db_offset]
		$("image").src = post.preview_url
	}
}

function db_init() {
	db_notice("Initializing")
	db_done_button = new AppleGlassButton($("done-button"), "Done", db_hide_prefs)
  db_info_button = new AppleInfoButton($("info-button"), $("front"), "white", "white", db_show_prefs)
	db_on_load = db_show_next
	db_get_posts()
}

db_show_prefs = function() {
	if (window.widget) {
		widget.prepareForTransition("ToBack")
	}
	
	$("front").style.display = "none"
	$("back").style.display = "block"

	if (window.widget) {
		setTimeout("widget.performTransition();", 0)
	}
}

db_hide_prefs = function() {
	if (window.widget) {
		widget.prepareForTransition("ToFront")
	}
	
	$("front").style.display = "block"
	$("back").style.display = "none"

	if (window.widget) {
		setTimeout("widget.performTransition();", 0)
	}
}

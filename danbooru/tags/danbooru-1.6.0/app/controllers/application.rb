require 'login_system'

class ApplicationController < ActionController::Base
  include LoginSystem
  include ExceptionNotifiable
  local_addresses.clear
  
  helper_method :is_safe_mode?
  before_filter :set_title
  before_filter :current_user
  
  protected
  def is_safe_mode?
    @current_user == nil && CONFIG["enable_anonymous_safe_post_mode"]
  end

  def render_error(record)
    @record = record
    render :status => 500, :layout => "bare", :inline => "<%= error_messages_for('record') %>"
  end
  
  def set_title(title = CONFIG["app_name"])
    @page_title = title
  end

  def save_tags_to_cookie
    if params[:tags] || (params[:post] && params[:post][:tags])
      tags = params[:tags] || params[:post][:tags]
      prev_tags = cookies["recent_tags"].to_s.gsub(/(?:character|char|ch|copyright|copy|ambiguous|amb|artist):/, "").scan(/\S+/)[0..20].join(" ")
      cookies["recent_tags"] = {:value => (tags + " " + prev_tags), :expires => 1.year.from_now}
    end
  end
  
  def cache_key
    a = "#{params[:controller]}/#{params[:action]}"
    tags = params[:tags].to_s.downcase.scan(/\S+/).sort.map do |x|
      version = CACHE.get("tag:" + x, true).to_i
      "#{x}:#{version}"
    end.join(",")

    case a
    when "post/index"
      if tags.empty?
        key = "p/i/p=#{params[:page].to_i}&v=#{$cache_version}"
      else
        key = "p/i/t=#{tags}&p=#{params[:page].to_i}"
      end
      
    when "post/atom"
      if tags.empty?
        key = "p/a/v=#{$cache_version}"
      else
        key = "p/a/t=#{tags}"
      end
    end

    logger.info "  Cache Key: #{key}"
    return key
  end
  
  def cache_action
    cache = false
    
    if CONFIG["cache_level"] == 1
      cache = (@current_user == nil && request.method == :get)
    elsif CONFIG["cache_level"] == 2
      cache = (request.method == :get)
    end

    if params[:format] == "xml" || params[:format] == "js"
      cache = false
    end
    
    if cache == true
      key = cache_key()
      cached = Cache.get(key)
      if cached != nil
        render :text => cached, :layout => false
        return false
      end

      yield
      
      Cache.put(key, response.body)
    else
      yield
    end
  end
  
  public
  def local_request?
    false
  end
end
